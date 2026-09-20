import SwiftUI

struct RootView: View {
    @EnvironmentObject private var usgs: USGSService
    @EnvironmentObject private var location: LocationManager

    @State private var selectedTab = RootView.initialTab

    /// Debug builds accept `-startTab <n>` so a screenshot pass can open a given
    /// tab directly. Release builds always start on the map.
    static var initialTab: Int {
        #if DEBUG
        let requested = UserDefaults.standard.integer(forKey: "startTab")
        return (0...4).contains(requested) ? requested : 0
        #else
        return 0
        #endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            MapScreen()
                .tag(0)
                .tabItem { Label("Map", systemImage: "map.fill") }

            HazardListScreen()
                .tag(1)
                .tabItem { Label("Nearby", systemImage: "list.bullet") }

            SnapTriageScreen()
                .tag(2)
                .tabItem { Label("Report", systemImage: "camera.fill") }

            RiverGaugeScreen()
                .tag(3)
                .tabItem { Label("Rivers", systemImage: "water.waves") }

            AdminScreen()
                .tag(4)
                .tabItem { Label("DPW", systemImage: "building.2.fill") }
        }
        .task {
            location.requestPermission()
            location.startUpdates()
            await usgs.refresh()
        }
    }
}
