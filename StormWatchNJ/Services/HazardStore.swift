import CoreLocation
import Foundation
import UIKit

/// Local persistence for hazard reports and their photos.
///
/// Reports are written to `Documents/hazard_reports.json` and photos to
/// `Documents/photos/`, so everything a judge submits during a demo survives an
/// app relaunch without needing the backend to be running.
@MainActor
final class HazardStore: ObservableObject {
    @Published private(set) var reports: [HazardReport] = []
    /// Reports added by the nor'easter simulation, tracked so it can be undone.
    @Published private(set) var simulatedReportIDs: Set<UUID> = []

    private let fileManager = FileManager.default

    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var storeURL: URL {
        documentsURL.appendingPathComponent("hazard_reports.json")
    }

    private var photosURL: URL {
        documentsURL.appendingPathComponent("photos", isDirectory: true)
    }

    init() {
        try? fileManager.createDirectory(at: photosURL, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Queries

    /// Client-side equivalent of the blueprint's `ST_DWithin` query: active reports
    /// within `radiusMiles` of the commuter, nearest first.
    func nearby(_ coordinate: CLLocationCoordinate2D, radiusMiles: Double) -> [HazardReport] {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let radiusMeters = radiusMiles * 1609.34
        return reports
            .filter { $0.status != .resolved }
            .compactMap { report -> (HazardReport, Double)? in
                let distance = origin.distance(from: report.location)
                return distance <= radiusMeters ? (report, distance) : nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    func distanceMiles(to report: HazardReport, from coordinate: CLLocationCoordinate2D) -> Double {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return origin.distance(from: report.location) / 1609.34
    }

    // MARK: - Mutations

    func add(_ report: HazardReport, photo: UIImage?) {
        var stored = report
        if let photo, let filename = savePhoto(photo, id: report.id) {
            stored.photoFilename = filename
        }
        reports.insert(stored, at: 0)
        persist()
    }

    /// Replaces a stored report with an edited copy, e.g. once its address resolves.
    func update(_ report: HazardReport) {
        guard let index = reports.firstIndex(where: { $0.id == report.id }) else { return }
        // The photo is attached by `add`; an edited copy made before that must not drop it.
        var merged = report
        merged.photoFilename = reports[index].photoFilename
        reports[index] = merged
        persist()
    }

    func upvote(_ report: HazardReport) {
        guard let index = reports.firstIndex(where: { $0.id == report.id }) else { return }
        reports[index].upvotes += 1
        reports[index].updatedAt = Date()
        persist()
    }

    func setStatus(_ status: ReportStatus, for report: HazardReport) {
        guard let index = reports.firstIndex(where: { $0.id == report.id }) else { return }
        reports[index].status = status
        reports[index].updatedAt = Date()
        persist()
    }

    func delete(_ report: HazardReport) {
        if let filename = report.photoFilename {
            try? fileManager.removeItem(at: photosURL.appendingPathComponent(filename))
        }
        reports.removeAll { $0.id == report.id }
        simulatedReportIDs.remove(report.id)
        persist()
    }

    func resetToSeedData() {
        for report in reports {
            if let filename = report.photoFilename {
                try? fileManager.removeItem(at: photosURL.appendingPathComponent(filename))
            }
        }
        reports = DemoData.seedReports()
        simulatedReportIDs = []
        persist()
    }

    // MARK: - Nor'easter simulation

    func applySimulatedStorm() {
        let storm = DemoData.stormSurgeReports()
        simulatedReportIDs.formUnion(storm.map(\.id))
        reports.insert(contentsOf: storm, at: 0)
        persist()
    }

    func clearSimulatedStorm() {
        reports.removeAll { simulatedReportIDs.contains($0.id) }
        simulatedReportIDs = []
        persist()
    }

    // MARK: - Photos

    func photo(for report: HazardReport) -> UIImage? {
        guard let filename = report.photoFilename else { return nil }
        let url = photosURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func savePhoto(_ image: UIImage, id: UUID) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let filename = "\(id.uuidString).jpg"
        do {
            try data.write(to: photosURL.appendingPathComponent(filename))
            return filename
        } catch {
            return nil
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder.stormWatch.decode([HazardReport].self, from: data),
              !decoded.isEmpty else {
            reports = DemoData.seedReports()
            persist()
            return
        }
        reports = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder.stormWatch.encode(reports) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var stormWatch: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var stormWatch: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
