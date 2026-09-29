import Foundation
import UIKit

/// Cross-posts a hazard report to the reporter's Nextdoor neighborhood.
///
/// Uses Nextdoor's **Share Plugin** (`https://nextdoor.com/sharekit/`), which is
/// an open offering — no API key, no approval, no account linking. It opens
/// Nextdoor's own post composer pre-filled with our text; the neighbor reviews it
/// and taps Post themselves.
///
/// Nextdoor's other option, the Publish API, can post natively but requires
/// applying for access and OAuth-linking each user's Nextdoor account, and
/// Nextdoor still requires the post to originate from a real Nextdoor user rather
/// than from the partner platform. Until StormWatch NJ has that partnership — most
/// plausibly as a municipal Public Agency — the Share Plugin is the honest path,
/// and it keeps a human in the loop on the way out just as the triage flow does on
/// the way in.
///
/// Docs: https://developer.nextdoor.com/reference/share-plugin
enum NextdoorShare {
    /// Identifies StormWatch NJ as the share source to Nextdoor.
    static let source = "stormwatchnj"

    /// Nextdoor caps the pre-filled body at 3,500 characters.
    static let bodyLimit = 3_500

    /// Builds the neighborhood post text.
    ///
    /// Deliberately omits the raw coordinate: the municipality and the reporter's
    /// own description are what a neighbor needs, and a Nextdoor post is public to
    /// the neighborhood. That matches the app's promise that a precise location is
    /// never published on its own.
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

    /// The `sharekit` URL that opens Nextdoor's composer.
    ///
    /// Returns nil only if the body cannot be percent-encoded, which should not
    /// happen for text we generated ourselves.
    static func shareURL(for report: HazardReport) -> URL? {
        var components = URLComponents(string: "https://nextdoor.com/sharekit/")
        components?.queryItems = [
            URLQueryItem(name: "source", value: source),
            URLQueryItem(name: "body", value: composeBody(for: report))
        ]
        return components?.url
    }

    /// Opens the composer. `completion` reports whether iOS could open the URL —
    /// it does not mean the neighbor actually posted, which only they can decide.
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
