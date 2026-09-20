import Foundation

/// Polls the USGS Water Services instantaneous-values REST API for gage height
/// (parameter `00065`) at the New Jersey sites in `NJStationCatalog`.
///
/// The API is public and needs no key, so the app talks to it directly instead of
/// going through the StormWatch backend. The `usgs_worker.py` script in `backend/`
/// does the same polling server-side on a 15-minute schedule.
@MainActor
final class USGSService: ObservableObject {
    @Published private(set) var stations: [USGSStation] = NJStationCatalog.stations
    @Published private(set) var isLoading = false
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var lastError: String?
    /// Set while "Simulate Nor'easter" is on, so a background refresh does not
    /// overwrite the storm readings with live calm-weather data.
    @Published var isSimulating = false

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    var stationsNeedingAttention: [USGSStation] {
        stations.filter { $0.alert != .normal }
    }

    func refresh() async {
        guard !isSimulating else { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let readings = try await fetchReadings()
            guard !readings.isEmpty else {
                lastError = "USGS returned no gage-height readings for these sites."
                return
            }
            stations = stations.map { station in
                guard let reading = readings[station.siteID] else { return station }
                var updated = station
                updated.currentGaugeHeightFt = reading.heightFt
                updated.lastUpdated = reading.timestamp
                updated.stationName = reading.siteName
                return updated
            }
            lastRefreshed = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Pushes every gauge to or past flood stage so the map and alerts can be
    /// demonstrated on a clear day. Clearly labelled as simulated in the UI.
    func applySimulatedStorm() {
        isSimulating = true
        stations = stations.map { station in
            var updated = station
            let surge = Double.random(in: 0.2...1.4)
            updated.currentGaugeHeightFt = (station.floodStageFt + surge).rounded(toPlaces: 2)
            updated.lastUpdated = Date()
            return updated
        }
        lastRefreshed = Date()
        lastError = nil
    }

    func clearSimulation() async {
        isSimulating = false
        stations = NJStationCatalog.stations
        await refresh()
    }

    // MARK: - Networking

    private struct Reading {
        let heightFt: Double
        let timestamp: Date?
        /// USGS's own name for the site, adopted so the catalog cannot drift.
        let siteName: String
    }

    private func fetchReadings() async throws -> [String: Reading] {
        var components = URLComponents(string: "https://waterservices.usgs.gov/nwis/iv/")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "sites", value: NJStationCatalog.siteIDList),
            URLQueryItem(name: "parameterCd", value: "00065"),
            URLQueryItem(name: "siteStatus", value: "active")
        ]

        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw USGSError.badStatus(http.statusCode)
        }

        let payload = try JSONDecoder().decode(USGSResponse.self, from: data)
        var readings: [String: Reading] = [:]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for series in payload.value.timeSeries {
            guard let siteCode = series.sourceInfo.siteCode.first?.value,
                  let point = series.values.first?.value.last,
                  let height = Double(point.value),
                  // USGS uses -999999 as its "no data" sentinel.
                  height > -900_000 else { continue }
            // USGS suffixes every site name with " NJ"; the county is shown separately.
            let name = series.sourceInfo.siteName.replacingOccurrences(of: " NJ", with: "")
            readings[siteCode] = Reading(heightFt: height,
                                         timestamp: formatter.date(from: point.dateTime),
                                         siteName: name)
        }
        return readings
    }

    enum USGSError: LocalizedError {
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code):
                return "USGS Water Services returned HTTP \(code)."
            }
        }
    }
}

// MARK: - USGS JSON shape

private struct USGSResponse: Decodable {
    let value: Value

    struct Value: Decodable {
        let timeSeries: [TimeSeries]
    }

    struct TimeSeries: Decodable {
        let sourceInfo: SourceInfo
        let values: [ValueBlock]
    }

    struct SourceInfo: Decodable {
        let siteName: String
        let siteCode: [SiteCode]
    }

    struct SiteCode: Decodable {
        let value: String
    }

    struct ValueBlock: Decodable {
        let value: [Point]
    }

    struct Point: Decodable {
        let value: String
        let dateTime: String
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
