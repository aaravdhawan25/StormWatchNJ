import Foundation

// an electric utility's 24-hour emergency line
struct ElectricUtility: Identifiable, Hashable {
    let id: String
    let name: String
    // as printed for a person to read
    let phoneDisplay: String
    // digits only, for the `tel:` link
    let phoneDigits: String
}

// one-tap hand-offs to the grid operator and to 911 for downed-wire reports
enum UtilityHandoff {
    static let pseg = ElectricUtility(id: "pseg", name: "PSE&G",
                                      phoneDisplay: "1-800-436-7734", phoneDigits: "18004367734")

    // New Jersey's other electric utilities
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

    // PSE&G's public outage, gas leak and downed-wire page
    static let psegOutagePageURL = URL(string: "https://nj.pseg.com/outageandgasleaks")!

    // opens Messages addressed to PSE&G's text line
    static let psegOutageTextURL = URL(string: "sms:47734&body=OUT")!

    // whether a report warrants the life-safety alert
    static func isLifeSafetyRisk(type: HazardType, utilityLines: Bool) -> Bool {
        utilityLines || type == .downedWire
    }
}
