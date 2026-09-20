import Foundation

/// Seed and simulation content.
///
/// Every report here is fictional demo data for testing and for the submission
/// video — it is not a record of a real incident.
enum DemoData {
    static func seedReports() -> [HazardReport] {
        let now = Date()
        return [
            HazardReport(reportType: .streetFlooding,
                         severity: .impassable,
                         roadStatus: .impassable,
                         utilityLinesInvolved: false,
                         details: "Scudders Mill Road underpass is holding roughly two feet of water. Two vehicles already turned around.",
                         photoFilename: nil,
                         latitude: 40.3395, longitude: -74.5751,
                         municipality: "Plainsboro",
                         status: .active,
                         upvotes: 14,
                         createdAt: now.addingTimeInterval(-3_100),
                         updatedAt: now.addingTimeInterval(-900)),
            HazardReport(reportType: .downedTree,
                         severity: .impassable,
                         roadStatus: .oneLaneOpen,
                         utilityLinesInvolved: true,
                         details: "Large oak down across Canal Road with the primary line caught in the crown. Treat wires as energized.",
                         photoFilename: nil,
                         latitude: 40.4512, longitude: -74.5808,
                         municipality: "Franklin Township",
                         status: .inProgress,
                         upvotes: 9,
                         createdAt: now.addingTimeInterval(-7_400),
                         updatedAt: now.addingTimeInterval(-1_800)),
            HazardReport(reportType: .cloggedDrain,
                         severity: .moderate,
                         roadStatus: .oneLaneOpen,
                         utilityLinesInvolved: false,
                         details: "Catch basin at Dey Road and Plainsboro Road packed with leaf litter; curb lane is ponding.",
                         photoFilename: nil,
                         latitude: 40.3216, longitude: -74.5612,
                         municipality: "Plainsboro",
                         status: .active,
                         upvotes: 5,
                         createdAt: now.addingTimeInterval(-11_000),
                         updatedAt: now.addingTimeInterval(-4_200)),
            HazardReport(reportType: .streetFlooding,
                         severity: .moderate,
                         roadStatus: .oneLaneOpen,
                         utilityLinesInvolved: false,
                         details: "Millstone River backing over the shoulder near the towpath lot. Passable slowly in the left lane.",
                         photoFilename: nil,
                         latitude: 40.4290, longitude: -74.6015,
                         municipality: "Princeton",
                         status: .active,
                         upvotes: 7,
                         createdAt: now.addingTimeInterval(-15_600),
                         updatedAt: now.addingTimeInterval(-6_000)),
            HazardReport(reportType: .downedWire,
                         severity: .impassable,
                         roadStatus: .impassable,
                         utilityLinesInvolved: true,
                         details: "Service drop down across the sidewalk on Harrison Street. Utility notified, road closed at both ends.",
                         photoFilename: nil,
                         latitude: 40.3521, longitude: -74.6402,
                         municipality: "Princeton",
                         status: .active,
                         upvotes: 21,
                         createdAt: now.addingTimeInterval(-2_400),
                         updatedAt: now.addingTimeInterval(-600)),
            HazardReport(reportType: .downedTree,
                         severity: .low,
                         roadStatus: .clearToPass,
                         utilityLinesInvolved: false,
                         details: "Limbs down in the bike lane on Route 27 near the canal bridge. Cars unaffected.",
                         photoFilename: nil,
                         latitude: 40.3982, longitude: -74.5395,
                         municipality: "South Brunswick",
                         status: .resolved,
                         upvotes: 3,
                         createdAt: now.addingTimeInterval(-86_400),
                         updatedAt: now.addingTimeInterval(-40_000))
        ]
    }

    /// Extra reports layered on by the "Simulate Nor'easter" toggle so the map,
    /// alert banner and DPW export all have something to show on a clear day.
    static func stormSurgeReports() -> [HazardReport] {
        let now = Date()
        let surge: [(HazardType, Severity, RoadStatus, Bool, String, Double, Double, String)] = [
            (.streetFlooding, .impassable, .impassable, false,
             "SIMULATED: Raritan overtopping Talmage Avenue. Full closure, water over the centerline.",
             40.5652, -74.5389, "Bound Brook"),
            (.downedTree, .impassable, .impassable, true,
             "SIMULATED: Two trees down with wires across Main Street. Utility crew required before clearing.",
             40.5388, -74.5901, "Manville"),
            (.cloggedDrain, .moderate, .oneLaneOpen, false,
             "SIMULATED: Basin surcharging at Washington Ave, water backing into the intersection.",
             40.4894, -74.4467, "New Brunswick"),
            (.streetFlooding, .impassable, .impassable, false,
             "SIMULATED: Nine-foot crest on the Millstone. River Road closed between the locks.",
             40.4580, -74.5960, "Franklin Township"),
            (.downedWire, .impassable, .impassable, true,
             "SIMULATED: Primary conductor down and arcing near the substation approach road.",
             40.3701, -74.6205, "West Windsor")
        ]

        return surge.enumerated().map { index, item in
            HazardReport(reportType: item.0,
                         severity: item.1,
                         roadStatus: item.2,
                         utilityLinesInvolved: item.3,
                         details: item.4,
                         photoFilename: nil,
                         latitude: item.5,
                         longitude: item.6,
                         municipality: item.7,
                         status: .active,
                         upvotes: Int.random(in: 4...30),
                         createdAt: now.addingTimeInterval(Double(-index) * 420),
                         updatedAt: now.addingTimeInterval(Double(-index) * 120))
        }
    }
}
