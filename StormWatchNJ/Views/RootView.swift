import SwiftUI

struct RootView: View {
    @EnvironmentObject private var usgs: USGSService
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var store: HazardStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var floodAlerts: FloodAlertService
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab = RootView.initialTab

    // debug: -startTab <n>
    static var initialTab: Int {
        #if DEBUG
        let requested = UserDefaults.standard.integer(forKey: "startTab")
        return (0...5).contains(requested) ? requested : 0
        #else
        return 0
        #endif
    }

    private var isTownship: Bool { account.account?.isTownship == true }

    // iPhone shows five tabs before collapsing the rest under "More"
    var body: some View {
        TabView(selection: $selectedTab) {
            MapScreen()
                .tag(0)
                .tabItem { Label("Map", systemImage: "map.fill") }

            if isTownship {
                AdminScreen()
                    .tag(5)
                    .tabItem { Label("DPW", systemImage: "building.2.fill") }
            } else {
                HazardListScreen()
                    .tag(1)
                    .tabItem { Label("Nearby", systemImage: "list.bullet") }
            }

            SnapTriageScreen()
                .tag(2)
                .tabItem { Label("Report", systemImage: "camera.fill") }

            RiverGaugeScreen()
                .tag(3)
                .tabItem { Label("Alerts", systemImage: "exclamationmark.shield.fill") }

            SettingsScreen()
                .tag(4)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        // the role can change while the app is open
        .onChange(of: isTownship) { _, township in
            if township, selectedTab == 1 { selectedTab = 5 }
            if !township, selectedTab == 5 { selectedTab = 1 }
        }
        .onAppear {
            if isTownship, selectedTab == 1 { selectedTab = 5 }
            if !isTownship, selectedTab == 5 { selectedTab = 0 }
        }
        .task {
            location.requestPermission()
            location.startUpdates()
            notifications.updateArea(location.coordinate, radiusMiles: settings.searchRadiusMiles)
            // ask for notifications once signed in
            if notifications.authorization == .notDetermined { await notifications.requestPermission() }
            await HazardSync.pull(into: store, account: account)
            await usgs.refresh()
            await floodAlerts.load(at: location.coordinate)
            notifications.process(alerts: floodAlerts.active)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // someone else may have removed or voted on a hazard while the app was away
                Task {
                    await notifications.refreshAuthorization()
                    await HazardSync.pull(into: store, account: account)
                }
            case .background:
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
        .onChange(of: location.coordinate.latitude) { _, _ in
            notifications.updateArea(location.coordinate, radiusMiles: settings.searchRadiusMiles)
        }
        .onChange(of: settings.searchRadiusMiles) { _, radius in
            notifications.updateArea(location.coordinate, radiusMiles: radius)
        }
        .onChange(of: notifications.pendingTab) { _, tab in
            guard let tab else { return }
            // hazard notifications point at the list; for staff that is the console
            selectedTab = (tab == 1 && isTownship) ? 5 : tab
            notifications.pendingTab = nil
        }
    }
}
