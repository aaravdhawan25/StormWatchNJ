import Foundation

/// Who is signed in.
struct Account: Codable, Equatable {
    let id: String
    let email: String
    var role: String
    var township: String?

    var isTownship: Bool { role == "township" }
}

enum AccountKind: String, CaseIterable, Identifiable {
    case resident
    case township

    var id: String { rawValue }
    var label: String { self == .resident ? "Resident" : "Township" }
}

struct TownshipDomain: Decodable, Identifiable {
    let domain: String
    let name: String
    let county: String

    var id: String { domain }
}

/// Sign-in state, backed by Supabase Auth.
///
/// An account is what makes "three people say it's gone" mean three people, and
/// what lets a reporter — and only that reporter — take down their own report.
///
/// Whether an account is a township account is decided on the server, from a
/// confirmed email on a municipal domain. Nothing here can grant it.
@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var account: Account?
    /// Set while an emailed confirmation is outstanding for this address.
    @Published var pendingEmail: String? {
        didSet { if pendingEmail == nil { pendingPassword = nil } }
    }
    /// A one-line message for the sign-in screen, e.g. after a confirmation link.
    @Published var notice: String?

    /// Kept in memory only, so that coming back from the confirmation link signs
    /// the person straight in. Never written to disk.
    private var pendingPassword: String?
    private var pendingKind: AccountKind = .resident

    /// Where the confirmation link should send people: straight back into the
    /// app. Supabase uses it only if it is in the project's Redirect URLs list;
    /// otherwise the link goes to the Site URL (the website), which offers a
    /// button back to the app.
    static let callbackURL = "stormwatchnj://auth-callback"
    private static var redirectQuery: [URLQueryItem] { [URLQueryItem(name: "redirect_to", value: callbackURL)] }

    private var session: StoredSession?
    private static let sessionKey = "session"
    private static let accountKey = "account"

    init() {
        if let saved = Keychain.read(Self.sessionKey),
           let session = try? JSONDecoder().decode(StoredSession.self, from: Data(saved.utf8)) {
            self.session = session
            // Sign-in is required, so the last known account is restored at once:
            // someone already signed in should not be locked out of the map with
            // no signal. `restore()` then checks the session with the server.
            if let saved = Keychain.read(Self.accountKey) {
                self.account = try? JSONDecoder().decode(Account.self, from: Data(saved.utf8))
            }
        }
    }

    var isSignedIn: Bool { account != nil }

    // MARK: - Session

    /// A current access token, refreshed first if it is about to expire.
    /// Returns nil when signed out. If the server rejects the refresh — the
    /// session was revoked — this signs out; if the network is down it keeps the
    /// session and returns the old token.
    func validToken() async -> String? {
        guard let session else { return nil }
        guard session.expiresAt.timeIntervalSinceNow < 60 else { return session.accessToken }
        do {
            let fresh: SessionResponse = try await BackendAPI().send(
                "POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                body: ["refresh_token": session.refreshToken])
            store(fresh)
            return fresh.access_token
        } catch let error as APIError where error.status != nil {
            clearSession()
            return nil
        } catch {
            return session.accessToken
        }
    }

    /// A client carrying the current session, or nil when signed out.
    func authorizedAPI() async -> BackendAPI? {
        guard let token = await validToken() else { return nil }
        return BackendAPI(token: token)
    }

    /// Re-validates a saved session on launch and refreshes the role.
    func restore() async {
        guard session != nil else { return }
        await loadProfile()
    }

    // MARK: - Signing in

    func signUp(email: String, password: String, kind: AccountKind) async throws {
        let email = Self.normalise(email)
        if kind == .township { try await requireTownshipDomain(email) }
        let reply: SignUpResponse = try await BackendAPI().send("POST", "auth/v1/signup", query: Self.redirectQuery, body: [
            "email": email, "password": password, "data": ["account_type": kind.rawValue]
        ])
        if let token = reply.access_token, let refresh = reply.refresh_token, let user = reply.user {
            // Only when the project has email confirmation switched off.
            store(SessionResponse(access_token: token, refresh_token: refresh,
                                  expires_in: reply.expires_in ?? 3600, user: user))
            await loadProfile()
        } else {
            pendingEmail = email
            pendingPassword = password
            pendingKind = kind
        }
    }

    func signIn(email: String, password: String, kind: AccountKind) async throws {
        let email = Self.normalise(email)
        do {
            let reply: SessionResponse = try await BackendAPI().send(
                "POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")],
                body: ["email": email, "password": password])
            try await adopt(reply, kind: kind)
        } catch let error as APIError where error.code == "email_not_confirmed" {
            // Right password, unconfirmed address: send a fresh email.
            pendingEmail = email
            pendingPassword = password
            pendingKind = kind
            try? await resendCode()
        }
    }

    func verify(code: String) async throws {
        guard let pendingEmail else { return }
        let reply: SessionResponse = try await BackendAPI().send("POST", "auth/v1/verify", body: [
            "type": "signup", "email": pendingEmail, "token": code.trimmingCharacters(in: .whitespaces)
        ])
        try await adopt(reply, kind: pendingKind)
    }

    func resendCode() async throws {
        guard let pendingEmail else { return }
        let _: BackendAPI.Empty = try await BackendAPI().send("POST", "auth/v1/resend", query: Self.redirectQuery,
                                                              body: ["type": "signup", "email": pendingEmail])
    }

    /// If a confirmation is outstanding and the address has since been confirmed
    /// (the person tapped the link), signs in with the password they just typed.
    /// Quiet when it isn't confirmed yet. Returns true if it signed in.
    @discardableResult
    func checkPendingConfirmation() async -> Bool {
        guard let email = pendingEmail, let password = pendingPassword, account == nil else { return false }
        guard let reply: SessionResponse = try? await BackendAPI().send(
            "POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")],
            body: ["email": email, "password": password]) else { return false }
        do {
            try await adopt(reply, kind: pendingKind)
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    /// Handles stormwatchnj:// links: the confirmation email (when Supabase sends
    /// it straight here, with a session in the fragment) and the website's
    /// "Open the app" button (no session; sign in with the pending password).
    func handle(url: URL) async {
        guard url.scheme == "stormwatchnj" else { return }
        var params: [String: String] = [:]
        for part in [url.fragment, URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery] {
            for pair in (part ?? "").split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
                if kv.count == 2 { params[kv[0]] = kv[1].replacingOccurrences(of: "+", with: " ") }
            }
        }
        if let error = params["error_description"] {
            notice = error.contains("expired") || error.contains("invalid")
                ? "That link has expired or was already used. Sign in — if your email still needs confirming, we'll send a new link."
                : error
            return
        }
        if let access = params["access_token"], let refresh = params["refresh_token"] {
            do {
                let user: AuthUser = try await BackendAPI(token: access).send("GET", "auth/v1/user")
                let expires = Int(params["expires_in"] ?? "") ?? 3600
                try await adopt(SessionResponse(access_token: access, refresh_token: refresh, expires_in: expires, user: user),
                                kind: pendingKind)
            } catch {
                notice = "Your email is confirmed. Sign in to continue."
            }
            return
        }
        if account == nil, !(await checkPendingConfirmation()) {
            notice = "Your email is confirmed. Sign in to continue."
        }
    }

    func signInWithGoogle(kind: AccountKind) async throws {
        let idToken = try await GoogleSignIn.idToken()
        let reply: SessionResponse = try await BackendAPI().send(
            "POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "id_token")],
            body: ["provider": "google", "id_token": idToken])
        try await adopt(reply, kind: kind)
    }

    func signOut() async {
        if let token = session?.accessToken {
            let _: BackendAPI.Empty? = try? await BackendAPI(token: token).send("POST", "auth/v1/logout")
        }
        AppServices.shared.notifications.reset()
        clearSession()
    }

    func townshipDomains() async -> [TownshipDomain] {
        (try? await BackendAPI().send("GET", "rest/v1/township_domains", query: [
            URLQueryItem(name: "select", value: "domain,name,county"),
            URLQueryItem(name: "order", value: "name")
        ])) ?? []
    }

    // MARK: - Internals

    private static func normalise(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Fails early, with a clear message, when a township sign-up or sign-in uses
    /// an address that is not on a municipal domain. The server enforces the same
    /// rule; this only spares the person a confusing error.
    private func requireTownshipDomain(_ email: String) async throws {
        let township: String? = try await BackendAPI().send("POST", "rest/v1/rpc/township_for_email",
                                                            body: ["p_email": email])
        if township == nil {
            throw APIError.server(status: 400, detail: "That email is not on a recognised township domain. Use your official municipal address, or sign in as a resident instead.", code: "not_township")
        }
    }

    private func adopt(_ reply: SessionResponse, kind: AccountKind) async throws {
        if kind == .township {
            do {
                try await requireTownshipDomain(reply.user.email ?? "")
            } catch {
                let _: BackendAPI.Empty? = try? await BackendAPI(token: reply.access_token).send("POST", "auth/v1/logout")
                throw error
            }
        }
        store(reply)
        pendingEmail = nil
        notice = nil
        await loadProfile()

        // Someone with a confirmed municipal address who first signed up as a
        // resident (or with Google) is asking to be treated as township staff.
        // Recording that request is all the app can do; the server grants the role
        // only because the address is confirmed and on the list.
        if kind == .township, account?.isTownship == false, let token = session?.accessToken {
            let _: BackendAPI.Empty? = try? await BackendAPI(token: token).send(
                "PUT", "auth/v1/user", body: ["data": ["account_type": "township"]])
            await loadProfile()
        }
    }

    private func loadProfile() async {
        guard let api = await authorizedAPI(), let session else { return }
        guard let rows: [Profile] = try? await api.send("GET", "rest/v1/profiles", query: [
            URLQueryItem(name: "select", value: "role,township")
        ]) else { return }   // Offline: keep whatever was restored.
        let profile = rows.first
        let current = Account(id: session.userID, email: session.email,
                              role: profile?.role ?? "resident", township: profile?.township)
        account = current
        if let data = try? JSONEncoder().encode(current) {
            Keychain.save(String(decoding: data, as: UTF8.self), for: Self.accountKey)
        }
    }

    private func store(_ reply: SessionResponse) {
        let stored = StoredSession(accessToken: reply.access_token,
                                   refreshToken: reply.refresh_token,
                                   expiresAt: Date().addingTimeInterval(TimeInterval(reply.expires_in)),
                                   userID: reply.user.id,
                                   email: reply.user.email ?? "")
        session = stored
        if let data = try? JSONEncoder().encode(stored) {
            Keychain.save(String(decoding: data, as: UTF8.self), for: Self.sessionKey)
        }
        if account == nil {
            account = Account(id: stored.userID, email: stored.email, role: "resident", township: nil)
        }
    }

    private func clearSession() {
        session = nil
        account = nil
        pendingEmail = nil
        Keychain.delete(Self.sessionKey)
        Keychain.delete(Self.accountKey)
    }

    private struct StoredSession: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let userID: String
        let email: String
    }

    private struct AuthUser: Decodable {
        let id: String
        let email: String?
    }

    private struct SessionResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int
        let user: AuthUser
    }

    /// Sign-up answers with a bare user while confirmation is pending, or with a
    /// full session when confirmation is switched off.
    private struct SignUpResponse: Decodable {
        let access_token: String?
        let refresh_token: String?
        let expires_in: Int?
        let user: AuthUser?
    }

    private struct Profile: Decodable {
        let role: String
        let township: String?
    }
}
