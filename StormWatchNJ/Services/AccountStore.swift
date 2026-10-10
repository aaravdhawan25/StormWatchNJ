import Foundation

/// Who is signed in.
struct Account: Codable, Equatable {
    let id: String
    let email: String
    let role: String
    let township: String?

    var isTownship: Bool { role == "township" }
}

enum AccountKind: String, CaseIterable, Identifiable {
    case resident
    case township

    var id: String { rawValue }
    var label: String { self == .resident ? "Resident" : "Township" }
}

/// Sign-in state, backed by the StormWatch backend.
///
/// An account is what makes "three people say it's gone" mean three people, and
/// what lets a reporter — and only that reporter — take down their own report.
@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var account: Account?
    /// Set while an emailed verification code is outstanding for this address.
    @Published var pendingEmail: String?

    private let settings: AppSettings
    private static let tokenKey = "token"
    private(set) var token: String?

    init(settings: AppSettings) {
        self.settings = settings
        self.token = Keychain.read(Self.tokenKey)
    }

    var isSignedIn: Bool { account != nil }

    /// A client carrying the current session, or nil when no backend is set.
    var api: BackendAPI? { BackendAPI(baseURL: settings.backendURL, token: token) }

    private func requireAPI() throws -> BackendAPI {
        guard let api else { throw APIError.notConfigured }
        return api
    }

    /// Re-validates a saved session on launch. A rejected token is discarded; a
    /// server that cannot be reached leaves it alone to try again later.
    func restore() async {
        guard token != nil, let api else { return }
        do {
            account = try await api.send("GET", "api/v1/auth/me")
        } catch let error as APIError where error.status == 401 {
            clearSession()
        } catch {
            // Offline: keep the token.
        }
    }

    func signUp(email: String, password: String, kind: AccountKind) async throws {
        let _: Pending = try await requireAPI().send("POST", "api/v1/auth/signup", body: [
            "email": email, "password": password, "account_type": kind.rawValue
        ])
        pendingEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
    }

    func signIn(email: String, password: String) async throws {
        do {
            let session: Session = try await requireAPI().send("POST", "api/v1/auth/login", body: [
                "email": email, "password": password
            ])
            adopt(session)
        } catch let error as APIError where error.code == "verification_required" {
            // Right password, unverified address: the server has sent a fresh code.
            pendingEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        }
    }

    func verify(code: String) async throws {
        guard let pendingEmail else { return }
        let session: Session = try await requireAPI().send("POST", "api/v1/auth/verify", body: [
            "email": pendingEmail, "code": code
        ])
        adopt(session)
    }

    func resendCode() async throws {
        guard let pendingEmail else { return }
        let _: BackendAPI.Empty = try await requireAPI().send("POST", "api/v1/auth/resend",
                                                              body: ["email": pendingEmail])
    }

    func signInWithGoogle(kind: AccountKind) async throws {
        let idToken = try await GoogleSignIn.idToken()
        let session: Session = try await requireAPI().send("POST", "api/v1/auth/google", body: [
            "id_token": idToken, "account_type": kind.rawValue
        ])
        adopt(session)
    }

    func signOut() async {
        if let api { let _: BackendAPI.Empty? = try? await api.send("POST", "api/v1/auth/logout") }
        clearSession()
    }

    func townshipDomains() async -> [TownshipDomain] {
        guard let api = BackendAPI(baseURL: settings.backendURL) else { return [] }
        return (try? await api.send("GET", "api/v1/auth/township-domains")) ?? []
    }

    private func adopt(_ session: Session) {
        token = session.token
        Keychain.save(session.token, for: Self.tokenKey)
        account = session.user
        pendingEmail = nil
    }

    private func clearSession() {
        token = nil
        Keychain.delete(Self.tokenKey)
        account = nil
        pendingEmail = nil
    }

    private struct Session: Decodable {
        let token: String
        let user: Account
    }

    private struct Pending: Decodable {
        let status: String
    }
}

struct TownshipDomain: Decodable, Identifiable {
    let domain: String
    let name: String
    let county: String

    var id: String { domain }
}
