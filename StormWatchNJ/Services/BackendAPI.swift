import Foundation

/// A failure talking to the StormWatch backend, phrased for the person using the app.
enum APIError: LocalizedError {
    case notConfigured
    case unreachable
    case server(status: Int, detail: String, code: String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No backend address is set. Add one in the DPW tab."
        case .unreachable:
            return "Couldn't reach the StormWatch server. Check your connection and the backend address."
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

/// JSON client for the backend's account and hazard endpoints.
struct BackendAPI {
    let baseURL: URL
    var token: String?

    init?(baseURL: URL?, token: String? = nil) {
        guard let baseURL, baseURL.scheme != nil else { return nil }
        self.baseURL = baseURL
        self.token = token
    }

    struct Empty: Decodable {}

    func send<Response: Decodable>(_ method: String,
                                   _ path: String,
                                   body: [String: String]? = nil) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 15
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
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
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            throw APIError.server(status: status,
                                  detail: failure?.detail ?? "The server returned an error (\(status)).",
                                  code: failure?.code)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private struct Failure: Decodable {
        let detail: String?
        let code: String?
    }
}
