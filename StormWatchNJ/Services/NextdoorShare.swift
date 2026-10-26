import Foundation
import UIKit

// cross-posts a hazard report to the reporter's Nextdoor neighborhood
enum NextdoorShare {
    // identifies StormWatch NJ as the share source to Nextdoor
    static let source = "stormwatchnj"

    // Nextdoor caps the pre-filled body at 3,500 characters
    static let bodyLimit = 3_500

    // builds the neighborhood post text
    static func composeBody(for report: HazardReport) -> String {
        var lines: [String] = []
        lines.append("⚠️ \(report.reportType.label) — \(report.severity.label.uppercased())")
        lines.append("")
        lines.append(report.details)
        lines.append("")
        lines.append("Road status: \(report.roadStatus.label)")
        lines.append("Area: \(report.municipality), NJ")

        if report.utilityLinesInvolved {
            lines.append("")
            lines.append("⚡️ Utility lines are involved. Treat any downed wire as energized — stay well back and call 911 and your utility.")
        }

        lines.append("")
        lines.append("Reported via StormWatch NJ, a neighbor-powered storm hazard map.")

        let body = lines.joined(separator: "\n")
        guard body.count > bodyLimit else { return body }
        return String(body.prefix(bodyLimit - 1)) + "…"
    }

    // the `sharekit` URL that opens Nextdoor's composer
    static func shareURL(for report: HazardReport) -> URL? {
        var components = URLComponents(string: "https://nextdoor.com/sharekit/")
        components?.queryItems = [
            URLQueryItem(name: "source", value: source),
            URLQueryItem(name: "body", value: composeBody(for: report))
        ]
        return components?.url
    }

    // opens the composer
    @MainActor
    static func open(_ report: HazardReport, completion: ((Bool) -> Void)? = nil) {
        guard let url = shareURL(for: report) else {
            completion?(false)
            return
        }
        UIApplication.shared.open(url, options: [:]) { didOpen in
            completion?(didOpen)
        }
    }
}
