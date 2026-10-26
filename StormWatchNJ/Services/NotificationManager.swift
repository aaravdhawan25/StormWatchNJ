import BackgroundTasks
import CoreLocation
import Foundation
import UserNotifications

// decides what is worth interrupting someone for, and tells them
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    // set when a notification is tapped; RootView switches to this tab
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

    // shows the system permission prompt, once
    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    // MARK: - Where "nearby" is

    // remembered so a background refresh, which has no map, knows the area
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

    // compares the shared hazard list with what was there last time
    func process(hazards: [ServerHazard], accountID: String?) {
        guard let accountID else { return }
        let currentIDs = Set(hazards.map(\.id))
        let currentMine = Dictionary(uniqueKeysWithValues: hazards.filter(\.is_mine).map { ($0.id, $0.status) })

        // first look for this account on this phone
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
                     // kept short: a long title is cut off in the banner
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

    // call when the person removes their own report
    func forgetMyReport(_ id: String) {
        var mine = (defaults.dictionary(forKey: Keys.myStatuses) as? [String: String]) ?? [:]
        mine.removeValue(forKey: id)
        defaults.set(mine, forKey: Keys.myStatuses)
    }

    // forget everything on sign-out; the next account starts fresh
    func reset() {
        [Keys.account, Keys.knownHazards, Keys.myStatuses].forEach(defaults.removeObject)
    }

    // MARK: - Flood alerts

    // announces alerts in effect at the person's own location
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
        // using a stable identifier means the same event can never stack up twice
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    // show the banner even while the app is open
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

// shared app objects, also used by background refresh
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

    // checks the server and raises any notifications that are due
    func refreshForNotifications() async {
        await HazardSync.pull(into: store, account: account)
        guard account.isSignedIn else { return }
        await floodAlerts.load(at: notifications.lastCoordinate)
        notifications.process(alerts: floodAlerts.active)
    }
}

// asks iOS to wake the app now and then to check for something worth a notification
enum BackgroundRefresh {
    static let identifier = "com.stormwatchnj.refresh"

    // must run before the app finishes launching
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
