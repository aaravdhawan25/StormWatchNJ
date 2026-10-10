import CoreLocation
import Foundation
import SwiftUI

/// Mirrors the `report_type` column in the PostGIS `hazard_reports` table.
enum HazardType: String, Codable, CaseIterable, Identifiable {
    case cloggedDrain = "CLOGGED_DRAIN"
    case streetFlooding = "STREET_FLOODING"
    case downedTree = "DOWNED_TREE"
    case downedWire = "DOWNED_WIRE"
    case other = "OTHER"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cloggedDrain: return "Clogged Storm Drain"
        case .streetFlooding: return "Street Flooding"
        case .downedTree: return "Downed Tree"
        case .downedWire: return "Downed Wire"
        case .other: return "Other Hazard"
        }
    }

    /// Compact name for filter chips, where the full label does not fit.
    var shortLabel: String {
        switch self {
        case .cloggedDrain: return "Drains"
        case .streetFlooding: return "Flooding"
        case .downedTree: return "Trees"
        case .downedWire: return "Wires"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .cloggedDrain: return "drop.triangle.fill"
        case .streetFlooding: return "water.waves"
        case .downedTree: return "leaf.fill"
        case .downedWire: return "bolt.trianglebadge.exclamationmark.fill"
        case .other: return "exclamationmark.triangle.fill"
        }
    }
}

enum Severity: String, Codable, CaseIterable, Identifiable {
    case low = "LOW"
    case moderate = "MODERATE"
    case impassable = "IMPASSABLE"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .impassable: return "Impassable"
        }
    }

    var tint: Color {
        switch self {
        case .low: return .yellow
        case .moderate: return .orange
        case .impassable: return .red
        }
    }

    /// Ranking used when sorting a mixed list of reports.
    var weight: Int {
        switch self {
        case .low: return 0
        case .moderate: return 1
        case .impassable: return 2
        }
    }
}

enum RoadStatus: String, Codable, CaseIterable, Identifiable {
    case clearToPass = "CLEAR_TO_PASS"
    case oneLaneOpen = "ONE_LANE_OPEN"
    case impassable = "IMPASSABLE"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clearToPass: return "Clear to pass"
        case .oneLaneOpen: return "One lane open"
        case .impassable: return "Impassable"
        }
    }
}

enum ReportStatus: String, Codable, CaseIterable, Identifiable {
    case active = "ACTIVE"
    case inProgress = "IN_PROGRESS"
    case resolved = "RESOLVED"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active: return "Active"
        case .inProgress: return "DPW en route"
        case .resolved: return "Resolved"
        }
    }
}

/// One crowdsourced, AI-triaged hazard. Field-for-field equivalent of a row in
/// the `hazard_reports` table from the project blueprint.
struct HazardReport: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var reportType: HazardType
    var severity: Severity
    var roadStatus: RoadStatus
    var utilityLinesInvolved: Bool
    var details: String
    /// File name inside the app's `photos/` directory, not a full path, so the
    /// store survives the container path changing between simulator launches.
    var photoFilename: String?
    var latitude: Double
    var longitude: Double
    var municipality: String
    var status: ReportStatus = .active
    var upvotes: Int = 1
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Street address from reverse geocoding, filled in shortly after posting.
    var address: String?
    var postalCode: String?
    /// Ticket id from the municipal relay, once the report has been forwarded.
    var relayTicketID: String?
    /// Server-side facts, present only for reports in the shared database.
    /// Optional so reports saved by older builds still decode.
    var isMine: Bool?
    var notThereVotes: Int?
    var iVotedNotThere: Bool?

    /// Whether this report lives in the shared database rather than only here.
    var isShared: Bool { relayTicketID != nil }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
