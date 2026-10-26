import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

// Google sign-in using the system web authentication session, OAuth 2.0
enum GoogleSignIn {
    enum Failure: LocalizedError {
        case notConfigured
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Google sign-in has not been set up for this build."
            case .cancelled: return "Sign-in was cancelled."
            case .failed(let reason): return "Google sign-in failed. \(reason)"
            }
        }
    }

    static var clientID: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String) ?? ""
        return value.isEmpty ? nil : value
    }

    static var isConfigured: Bool { clientID != nil }

    // Google's iOS redirect scheme is the reversed client ID
    private static func redirectScheme(for clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    @MainActor
    static func idToken() async throws -> String {
        guard let clientID else { throw Failure.notConfigured }
        let scheme = redirectScheme(for: clientID)
        let redirectURI = "\(scheme):/oauth2redirect"

        let verifier = randomURLSafe(bytes: 32)
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = randomURLSafe(bytes: 16)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        let callback = try await authenticate(url: components.url!, scheme: scheme)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // a mismatched state means this response was not the answer to our request
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw Failure.failed("The response from Google could not be verified.")
        }
        return try await exchange(code: code, verifier: verifier, clientID: clientID, redirectURI: redirectURI)
    }

    @MainActor
    private static func authenticate(url: URL, scheme: String) async throws -> URL {
        let anchor = PresentationAnchor()
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: Failure.cancelled)
                } else {
                    continuation.resume(throwing: Failure.failed(error?.localizedDescription ?? ""))
                }
            }
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = false
            // the system holds these weakly; keep them alive while the sheet is up
            activeSession = session
            activeAnchor = anchor
            if !session.start() {
                continuation.resume(throwing: Failure.failed("The sign-in window could not be opened."))
            }
        }
    }

    private static func exchange(code: String, verifier: String,
                                 clientID: String, redirectURI: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let token = (try? JSONDecoder().decode(TokenResponse.self, from: data))?.id_token else {
            throw Failure.failed("Google did not return an identity token.")
        }
        return token
    }

    @MainActor private static var activeSession: ASWebAuthenticationSession?
    @MainActor private static var activeAnchor: PresentationAnchor?

    private struct TokenResponse: Decodable {
        let id_token: String?
    }

    private static func randomURLSafe(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
