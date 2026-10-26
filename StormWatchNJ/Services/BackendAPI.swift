import Foundation

// a failure talking to the backend, phrased for the person using the app
enum APIError: LocalizedError {
    case unreachable
    case server(status: Int, detail: String, code: String?)

    var errorDescription: String? {
        switch self {
        case .unreachable:
            return "Couldn't reach StormWatch. Check your connection and try again."
        case .server(_, let detail, _):
            return detail
        }
    }

    var code: String? {
        if case .server(_, _, let code) = self { return code }
        return nil
    }

    var status: Int? {
        if case .server(let status, _, _) = self { return status }
        return nil
    }
}

// JSON client for Supabase
struct BackendAPI {
    var token: String?

    // decodes from any JSON object, for calls whose reply does not matter
    struct Empty: Decodable {}

    func send<Response: Decodable>(_ method: String,
                                   _ path: String,
                                   query: [URLQueryItem] = [],
                                   body: [String: Any]? = nil) async throws -> Response {
        var components = URLComponents(url: SupabaseConfig.url.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? SupabaseConfig.publishableKey)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.unreachable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Self.failure(status: status, data: data)
        }
        // sign-out answers 204 with no body
        return try JSONDecoder().decode(Response.self, from: data.isEmpty ? Data("{}".utf8) : data)
    }

    // the auth service and the database API report errors in different shapes
    private static func failure(status: Int, data: Data) -> APIError {
        let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = (raw["error_code"] ?? raw["code"]) as? String
        let message = (raw["msg"] ?? raw["message"] ?? raw["error_description"] ?? raw["detail"]) as? String

        let friendly: String?
        switch code {
        case "invalid_credentials": friendly = "Incorrect email or password."
        case "email_not_confirmed": friendly = "Check your email to finish setting up your account."
        case "user_already_exists", "email_exists": friendly = "An account with that email already exists. Sign in instead."
        case "otp_expired": friendly = "That code is wrong or has expired. Request a new one."
        case "over_email_send_rate_limit":
            friendly = "Too many emails have been sent in the last hour, so a new one can't go out yet. Try again later, or use the link in an email you already have."
        case "over_request_rate_limit":
            friendly = "Too many attempts. Wait a minute and try again."
        case "weak_password": friendly = "Choose a stronger password."
        case "email_address_invalid", "validation_failed": friendly = "Enter a valid email address."
        default: friendly = nil
        }
        return .server(status: status,
                       detail: friendly ?? message ?? "Something went wrong (\(status)).",
                       code: code)
    }
}
