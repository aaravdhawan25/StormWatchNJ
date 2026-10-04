import Foundation

/// Files a report with the StormWatch backend's Open311 GeoReport v2 endpoint,
/// which stores it, publishes it in the GeoJSON feed and forwards it to the
/// town's public works desk if that town has opted in.
///
/// The photo is not uploaded — it stays on the device, as the app promises — so
/// `media_url` is never sent.
enum MunicipalRelay {
    enum RelayError: LocalizedError {
        case notConfigured
        case rejected(Int, String)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "No backend address is set."
            case .rejected(let code, let detail): return "The relay refused the report (\(code)). \(detail)"
            case .unreadable: return "The relay's reply could not be read."
            }
        }
    }

    /// Returns the `service_request_id` the backend assigned.
    static func send(_ report: HazardReport, baseURL: URL?, apiKey: String) async throws -> String {
        guard let baseURL, baseURL.scheme != nil else { throw RelayError.notConfigured }

        var fields: [(String, String)] = [
            ("service_code", report.reportType.rawValue),
            ("lat", String(report.latitude)),
            ("long", String(report.longitude)),
            ("description", report.details),
            ("attribute[severity]", report.severity.rawValue),
            ("attribute[road_status]", report.roadStatus.rawValue),
            ("attribute[utility_lines_involved]", report.utilityLinesInvolved ? "true" : "false"),
            ("attribute[municipality]", report.municipality)
        ]
        if !apiKey.isEmpty { fields.append(("api_key", apiKey)) }
        if let address = report.address { fields.append(("address_string", address)) }
        if let postalCode = report.postalCode { fields.append(("attribute[zipcode]", postalCode)) }

        var request = URLRequest(url: baseURL.appendingPathComponent("georeport/v2/requests.json"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        // Open311 specifies form encoding for POST, not JSON.
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .map { "\(formEncode($0.0))=\(formEncode($0.1))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSONDecoder().decode([Open311Error].self, from: data))?.first?.description ?? ""
            throw RelayError.rejected(status, detail)
        }
        guard let ticket = try? JSONDecoder().decode([Receipt].self, from: data).first else {
            throw RelayError.unreadable
        }
        return ticket.service_request_id
    }

    private struct Receipt: Decodable {
        let service_request_id: String
    }

    private struct Open311Error: Decodable {
        let description: String
    }

    /// Strict form encoding: `urlQueryAllowed` leaves `&`, `+` and `=` intact,
    /// which would corrupt a description containing any of them.
    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

/// Runs the after-posting work for a report: resolve its street address, then
/// forward it to the municipal relay if the resident has turned that on.
///
/// Kept off the submit path so posting stays instant and works offline; the
/// report is already saved locally before any of this starts.
@MainActor
enum ReportFollowUp {
    static func run(for report: HazardReport, store: HazardStore, settings: AppSettings) async {
        var current = report
        if current.address == nil,
           let resolved = await AddressResolver.resolve(latitude: report.latitude, longitude: report.longitude) {
            current.address = resolved.singleLine
            current.postalCode = resolved.postalCode
            store.update(current)
        }
        guard settings.forwardToPublicWorks, current.relayTicketID == nil else { return }
        await forward(current, store: store, settings: settings)
    }

    /// Returns nil on success, or a message to show.
    @discardableResult
    static func forward(_ report: HazardReport, store: HazardStore, settings: AppSettings) async -> String? {
        do {
            var sent = report
            sent.relayTicketID = try await MunicipalRelay.send(report,
                                                               baseURL: settings.backendURL,
                                                               apiKey: settings.relayAPIKey)
            store.update(sent)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
