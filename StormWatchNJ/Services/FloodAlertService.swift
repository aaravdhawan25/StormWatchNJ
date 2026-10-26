import CoreLocation
import Foundation
import SwiftUI

// one flood alert, from either source
struct FloodAlert: Identifiable, Hashable {
    enum Source: String {
        // live from the National Weather Service, in effect right now
        case live
        // from FEMA's IPAWS archive, already at least a day old
        case archive
    }

    let id: String
    let source: Source
    let event: String
    let headline: String
    let severity: String
    let area: String
    let sender: String
    let sent: Date?
    let expires: Date?
    let details: String
    let instruction: String

    var tint: Color {
        switch severity.lowercased() {
        case "extreme", "severe": return .red
        case "moderate": return .orange
        default: return .yellow
        }
    }

    // white text is unreadable on the yellow used for minor alerts
    var textOnTint: Color {
        switch severity.lowercased() {
        case "extreme", "severe", "moderate": return .white
        default: return .black.opacity(0.85)
        }
    }
}

// flood alerts from NWS (now) and FEMA (past)
@MainActor
final class FloodAlertService: ObservableObject {
    @Published private(set) var active: [FloodAlert] = []
    @Published private(set) var recent: [FloodAlert] = []
    @Published private(set) var isLoading = false
    @Published private(set) var liveError: String?
    @Published private(set) var archiveError: String?
    @Published private(set) var lastChecked: Date?

    // how far back the FEMA history looks
    static let historyDays = 90

    func load(at coordinate: CLLocationCoordinate2D) async {
        isLoading = true
        defer { isLoading = false }
        let point = Self.debugPoint ?? coordinate

        async let live = Self.fetchLive(at: point)
        async let archive = Self.fetchArchive(at: point)

        switch await live {
        case .success(let alerts): active = alerts; liveError = nil
        case .failure(let error): liveError = error.localizedDescription
        }
        switch await archive {
        case .success(let alerts): recent = alerts; archiveError = nil
        case .failure(let error): archiveError = error.localizedDescription
        }
        lastChecked = Date()
    }

    // debug: -alertTestPoint "lat,lon"
    private static var debugPoint: CLLocationCoordinate2D? {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "alertTestPoint") else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return parts.count == 2 ? CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1]) : nil
        #else
        return nil
        #endif
    }

    private struct FetchError: LocalizedError {
        let errorDescription: String?
    }

    private static func isFlood(_ event: String) -> Bool {
        event.lowercased().contains("flood")
    }

    // MARK: - National Weather Service (live)

    private static func fetchLive(at point: CLLocationCoordinate2D) async -> Result<[FloodAlert], Error> {
        var components = URLComponents(string: "https://api.weather.gov/alerts/active")!
        components.queryItems = [URLQueryItem(name: "point", value: String(format: "%.4f,%.4f", point.latitude, point.longitude))]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        // NWS asks every client to identify itself
        request.setValue("StormWatchNJ/1.0 (iOS; civic storm hazard map)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let features = root["features"] as? [[String: Any]] else {
                return .failure(FetchError(errorDescription: "The National Weather Service didn't answer. Live alerts may be missing."))
            }
            let alerts = features.compactMap { feature -> FloodAlert? in
                guard let p = feature["properties"] as? [String: Any],
                      let event = p["event"] as? String, isFlood(event),
                      (p["status"] as? String) == "Actual",
                      (p["messageType"] as? String) != "Cancel" else { return nil }
                return FloodAlert(id: (p["id"] as? String) ?? UUID().uuidString,
                                  source: .live,
                                  event: event,
                                  headline: (p["headline"] as? String) ?? event,
                                  severity: (p["severity"] as? String) ?? "Unknown",
                                  area: (p["areaDesc"] as? String) ?? "",
                                  sender: (p["senderName"] as? String) ?? "National Weather Service",
                                  sent: date(p["sent"]),
                                  // `ends` is when the flooding is expected to end
                                  expires: date(p["ends"]) ?? date(p["expires"]),
                                  details: (p["description"] as? String) ?? "",
                                  instruction: (p["instruction"] as? String) ?? "")
            }
            return .success(alerts.sorted { ($0.sent ?? .distantPast) > ($1.sent ?? .distantPast) })
        } catch {
            return .failure(FetchError(errorDescription: "Couldn't reach the National Weather Service. Live alerts may be missing."))
        }
    }

    // MARK: - FEMA IPAWS archive (history)

    private static func fetchArchive(at point: CLLocationCoordinate2D) async -> Result<[FloodAlert], Error> {
        let since = Date().addingTimeInterval(-Double(historyDays) * 86_400)
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var components = URLComponents(string: "https://www.fema.gov/api/open/v1/IpawsArchivedAlerts")!
        components.queryItems = [
            URLQueryItem(name: "$select", value: "identifier,sent,status,msgType,info"),
            URLQueryItem(name: "$orderby", value: "sent desc"),
            URLQueryItem(name: "$top", value: "100"),
            URLQueryItem(name: "$filter", value:
                "sent ge '\(stamp.string(from: since))' and geo.intersects(searchGeometry, geography'POINT(\(point.longitude) \(point.latitude))')")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = root["IpawsArchivedAlerts"] as? [[String: Any]] else {
                return .failure(FetchError(errorDescription: "FEMA's alert archive didn't answer."))
            }
            var seen: Set<String> = []
            let alerts = rows.compactMap { row -> FloodAlert? in
                guard (row["status"] as? String) == "Actual",
                      let type = row["msgType"] as? String, type == "Alert" || type == "Update",
                      let info = (row["info"] as? [[String: Any]])?.first,
                      let event = info["event"] as? String, isFlood(event) else { return nil }
                let area = ((info["area"] as? [[String: Any]])?.first?["areaDesc"] as? String) ?? ""
                let id = (row["identifier"] as? String) ?? UUID().uuidString
                guard seen.insert(id).inserted else { return nil }
                return FloodAlert(id: id,
                                  source: .archive,
                                  event: event,
                                  headline: (info["headline"] as? String) ?? event,
                                  severity: (info["severity"] as? String) ?? "Unknown",
                                  area: area,
                                  sender: (info["senderName"] as? String) ?? "",
                                  sent: date(row["sent"]),
                                  expires: date(info["expires"]),
                                  details: (info["description"] as? String) ?? "",
                                  instruction: (info["instruction"] as? String) ?? "")
            }
            return .success(alerts)
        } catch {
            return .failure(FetchError(errorDescription: "Couldn't reach FEMA's alert archive."))
        }
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
