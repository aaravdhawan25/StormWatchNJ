import BackgroundTasks
import CoreLocation
import Foundation
import UserNotifications

/// Decides what is worth interrupting someone for, and tells them.
///
/// These are **local** notifications: the app raises them itself after checking
/// the server, either while it is open or when iOS wakes it for a background
/// refresh. They are not server push. iOS decides when background refresh runs —
/// often within the hour for an app used daily, never if the app was force-quit —
/// so this is a useful heads-up, not a guaranteed emergency alert. Instant push
/// would need the Apple Developer Program and an APNs sender on the server.
///
/// Three things qualify:
///   * a flood alert coming into effect where you are,
///   * a new impassable hazard or downed wire inside your search radius, and
///   * a change to a report you filed: a crew assigned, resolved, or removed.
///
/// River gauges do not notify. Their flood thresholds in this build are demo
/// values, and an alarming notification should not rest on a placeholder.
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// Set when a notification is tapped; RootView switches to this tab.
    @Published var pendingTab: Int?

    @Published var floodAlertsEnabled: Bool { didSet { defaults.set(floodAlertsEnabled, forKey: Keys.flood) } }
    @Published var nearbyHazardsEnabled: Bool { didSet { defaults.set(nearbyHazardsEnabled, forKey: Keys.nearby) } }
    @Published var myReportsEnabled: Bool { didSet { defaults.set(myReportsEnabled, forKey: Keys.mine) } }

    private let defaults = UserDefaults.standard
    private let center = UNUserNotificationCenter.current()

    private enum Keys {
        static let flood = "notify.floodAlerts"
        static let nearby = "notify.nearbyHazards"
        static let mine = "notify.myReports"
        static let account = "notify.accountID"
        static let knownHazards = "notify.knownHazardIDs"
        static let myStatuses = "notify.myReportStatuses"
        static let notifiedAlerts = "notify.notifiedAlertIDs"
        static let latitude = "notify.latitude"
        static let longitude = "notify.longitude"
        static let radius = "notify.radiusMiles"
    }

    override init() {
        floodAlertsEnabled = defaults.object(forKey: Keys.flood) as? Bool ?? true
        nearbyHazardsEnabled = defaults.object(forKey: Keys.nearby) as? Bool ?? true
        myReportsEnabled = defaults.object(forKey: Keys.mine) as? Bool ?? true
        super.init()
        center.delegate = self
        Task { await refreshAuthorization() }
    }

    var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
    }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Shows the system permission prompt, once. After a refusal only the
    /// Settings app can turn notifications back on.
    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    // MARK: - Where "nearby" is

    /// Remembered so a background refresh, which has no map, knows the area.
    func updateArea(_ coordinate: CLLocationCoordinate2D, radiusMiles: Double) {
        defaults.set(coordinate.latitude, forKey: Keys.latitude)
        defaults.set(coordinate.longitude, forKey: Keys.longitude)
        defaults.set(radiusMiles, forKey: Keys.radius)
    }

    var lastCoordinate: CLLocationCoordinate2D {
        let latitude = defaults.double(forKey: Keys.latitude), longitude = defaults.double(forKey: Keys.longitude)
        guard latitude != 0, longitude != 0 else { return NJServiceArea.demoCenter }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var radiusMiles: Double {
        let stored = defaults.double(forKey: Keys.radius)
        return stored > 0 ? stored : 5
    }

    // MARK: - Hazards

    /// Compares the shared hazard list with what was there last time.
    func process(hazards: [ServerHazard], accountID: String?) {
        guard let accountID else { return }
        let currentIDs = Set(hazards.map(\.id))
        let currentMine = Dictionary(uniqueKeysWithValues: hazards.filter(\.is_mine).map { ($0.id, $0.status) })

        // First look for this account on this phone: remember what exists and say
        // nothing. Otherwise signing in would announce every hazard already on the map.
        guard defaults.string(forKey: Keys.account) == accountID else {
            defaults.set(accountID, forKey: Keys.account)
            defaults.set(Array(currentIDs), forKey: Keys.knownHazards)
            defaults.set(currentMine, forKey: Keys.myStatuses)
            return
        }

        let known = Set(defaults.stringArray(forKey: Keys.knownHazards) ?? [])
        let previousMine = (defaults.dictionary(forKey: Keys.myStatuses) as? [String: String]) ?? [:]
        let here = CLLocation(latitude: lastCoordinate.latitude, longitude: lastCoordinate.longitude)

        if nearbyHazardsEnabled {
            for hazard in hazards where !known.contains(hazard.id) && !hazard.is_mine && hazard.status != "RESOLVED" {
                guard hazard.severity == "IMPASSABLE" || hazard.utility_lines_involved else { continue }
                let miles = here.distance(from: CLLocation(latitude: hazard.latitude, longitude: hazard.longitude)) / 1609.34
                guard miles <= radiusMiles else { continue }
                let type = HazardType(rawValue: hazard.report_type)?.label ?? "Hazard"
                let place = hazard.municipality.map { " in \($0)" } ?? ""
                send(id: "hazard-\(hazard.id)",
                     // Kept short: a long title is cut off in the banner.
                     title: hazard.utility_lines_involved ? "⚡️ \(type) with wires nearby" : "\(type) nearby",
                     body: String(format: "%.1f mi away%@. %@", miles, place, hazard.description),
                     tab: 1)
            }
        }

        if myReportsEnabled {
            for (id, status) in currentMine {
                guard let before = previousMine[id], before != status else { continue }
                if status == "IN_PROGRESS" {
                    send(id: "mine-\(id)-crew", title: "A crew is on the way",
                         body: "Public works marked your report as in progress.", tab: 1)
                } else if status == "RESOLVED" {
                    send(id: "mine-\(id)-resolved", title: "Your report was resolved",
                         body: "Public works marked the hazard you reported as cleared.", tab: 1)
                }
            }
            for id in previousMine.keys where !currentIDs.contains(id) {
                send(id: "mine-\(id)-removed", title: "Your report came off the map",
                     body: "Neighbors or your township marked it as gone, or it expired after 3 days without an update.", tab: 1)
            }
        }

        defaults.set(Array(currentIDs), forKey: Keys.knownHazards)
        defaults.set(currentMine, forKey: Keys.myStatuses)
    }

    /// Call when the person removes their own report, so it is not then announced
    /// to them as having "come off the map".
    func forgetMyReport(_ id: String) {
        var mine = (defaults.dictionary(forKey: Keys.myStatuses) as? [String: String]) ?? [:]
        mine.removeValue(forKey: id)
        defaults.set(mine, forKey: Keys.myStatuses)
    }

    /// Forget everything on sign-out; the next account starts fresh.
    func reset() {
        [Keys.account, Keys.knownHazards, Keys.myStatuses].forEach(defaults.removeObject)
    }

    // MARK: - Flood alerts

    /// Announces alerts in effect at the person's own location. Callers pass only
    /// the home-area result — not a lookup of some other ZIP code.
    func process(alerts: [FloodAlert]) {
        guard floodAlertsEnabled else { return }
        var notified = defaults.stringArray(forKey: Keys.notifiedAlerts) ?? []
        for alert in alerts where alert.source == .live && !notified.contains(alert.id) {
            var body = alert.area
            if let expires = alert.expires {
                body += " · until \(expires.formatted(date: .omitted, time: .shortened))"
            }
            send(id: "flood-\(alert.id)", title: "\(alert.event) in effect", body: body, tab: 3)
            notified.append(alert.id)
        }
        defaults.set(Array(notified.suffix(200)), forKey: Keys.notifiedAlerts)
    }

    // MARK: - Delivery

    private func send(id: String, title: String, body: String, tab: Int) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["tab": tab]
        // Using a stable identifier means the same event can never stack up twice.
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Show the banner even while the app is open; the event is just as important.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let tab = response.notification.request.content.userInfo["tab"] as? Int
        await MainActor.run { self.pendingTab = tab }
    }
}

/// The long-lived objects, shared so a background refresh updates the same
/// stores the screens are showing instead of a second copy.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let store = HazardStore()
    let usgs = USGSService()
    let location = LocationManager()
    let settings = AppSettings()
    let account = AccountStore()
    let floodAlerts = FloodAlertService()
    let notifications = NotificationManager()

    /// Checks the server and raises any notifications that are due.
    func refreshForNotifications() async {
        await HazardSync.pull(into: store, account: account)
        guard account.isSignedIn else { return }
        await floodAlerts.load(at: notifications.lastCoordinate)
        notifications.process(alerts: floodAlerts.active)
    }
}

/// Asks iOS to wake the app now and then to check for something worth a
/// notification. iOS chooses the moment; this only says "no sooner than".
enum BackgroundRefresh {
    static let identifier = "com.stormwatchnj.refresh"

    /// Must run before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let work = Task { @MainActor in
                await AppServices.shared.refreshForNotifications()
                task.setTaskCompleted(success: !Task.isCancelled)
            }
            task.expirationHandler = { work.cancel() }
            schedule()
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
