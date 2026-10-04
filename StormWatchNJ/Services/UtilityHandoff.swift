import Foundation

/// An electric utility's 24-hour emergency line.
struct ElectricUtility: Identifiable, Hashable {
    let id: String
    let name: String
    /// As printed for a person to read.
    let phoneDisplay: String
    /// Digits only, for the `tel:` link.
    let phoneDigits: String
}

/// One-tap hand-offs to the grid operator and to 911 for downed-wire reports.
///
/// Utilities do not expose write APIs for outage tickets, and they should not: an
/// app that could file them unattended would be a spam cannon aimed at an
/// emergency desk. So nothing here sends anything. Each action opens the phone
/// dialer, Messages or the browser with the destination filled in, and the
/// resident completes it — which also means a real person, reachable on a real
/// phone, is the one talking to the dispatcher.
///
/// Phone numbers: NJ Office of Emergency Management utility list
/// (nj.gov/njoem/plan-prepare/public-utilities.shtml) and PSE&G's downed power
/// line page. The 30-foot distance is PSE&G's published guidance.
enum UtilityHandoff {
    static let pseg = ElectricUtility(id: "pseg", name: "PSE&G",
                                      phoneDisplay: "1-800-436-7734", phoneDigits: "18004367734")

    /// New Jersey's other electric utilities. Which one serves an address is not
    /// something the app can know reliably, so the resident picks.
    static let otherUtilities = [
        ElectricUtility(id: "jcpl", name: "JCP&L",
                        phoneDisplay: "1-888-544-4877", phoneDigits: "18885444877"),
        ElectricUtility(id: "ace", name: "Atlantic City Electric",
                        phoneDisplay: "1-800-833-7476", phoneDigits: "18008337476"),
        ElectricUtility(id: "oru", name: "Orange & Rockland",
                        phoneDisplay: "1-877-434-4100", phoneDigits: "18774344100")
    ]

    static let safeDistanceFeet = 30

    static let emergencyURL = URL(string: "tel://911")!

    static func callURL(for utility: ElectricUtility) -> URL {
        URL(string: "tel://\(utility.phoneDigits)")!
    }

    /// PSE&G's public outage, gas leak and downed-wire page. It takes no address
    /// parameters, so none are appended; the resident enters the location there.
    static let psegOutagePageURL = URL(string: "https://nj.pseg.com/outageandgasleaks")!

    /// Opens Messages addressed to PSE&G's text line (4PSEG) with `OUT` typed in.
    ///
    /// This is *not* a way to report a downed wire at the hazard's location.
    /// `OUT` reports a power outage at the address on the texter's own PSE&G
    /// account, and only works from a phone already enrolled by texting `REG`.
    /// The UI offers it only as "my own power is out".
    static let psegOutageTextURL = URL(string: "sms:47734&body=OUT")!

    /// Whether a report warrants the life-safety alert.
    static func isLifeSafetyRisk(type: HazardType, utilityLines: Bool) -> Bool {
        utilityLines || type == .downedWire
    }
}
