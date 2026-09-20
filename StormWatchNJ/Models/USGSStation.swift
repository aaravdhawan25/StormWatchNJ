import CoreLocation
import Foundation
import SwiftUI

enum GaugeAlert: String, Codable, CaseIterable {
    case normal = "NORMAL"
    case action = "ACTION"
    case flood = "FLOOD"
    case major = "MAJOR"

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .action: return "Action Stage"
        case .flood: return "Flood Stage"
        case .major: return "Major Flooding"
        }
    }

    var tint: Color {
        switch self {
        case .normal: return .green
        case .action: return .yellow
        case .flood: return .orange
        case .major: return .red
        }
    }
}

/// A New Jersey river gauge polled from the USGS Water Services API.
struct USGSStation: Identifiable, Codable, Hashable {
    /// USGS site number, e.g. `01400500` (Millstone River at Blackwells Mills).
    let siteID: String
    var stationName: String
    var county: String
    var latitude: Double
    var longitude: Double
    /// Threshold at which crews stage equipment.
    var actionStageFt: Double
    /// Threshold at which low-lying roads begin to flood.
    var floodStageFt: Double
    var currentGaugeHeightFt: Double?
    var lastUpdated: Date?

    var id: String { siteID }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var alert: GaugeAlert {
        guard let height = currentGaugeHeightFt else { return .normal }
        if height >= floodStageFt + 3 { return .major }
        if height >= floodStageFt { return .flood }
        if height >= actionStageFt { return .action }
        return .normal
    }

    /// How close the river is to flood stage, clamped to 0...1 for the gauge bar.
    var floodProgress: Double {
        guard let height = currentGaugeHeightFt, floodStageFt > 0 else { return 0 }
        return min(max(height / floodStageFt, 0), 1)
    }

    var feetBelowFloodStage: Double? {
        guard let height = currentGaugeHeightFt else { return nil }
        return floodStageFt - height
    }
}
