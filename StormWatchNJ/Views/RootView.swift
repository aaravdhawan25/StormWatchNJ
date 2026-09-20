import SwiftUI

struct RootView: View {
    @EnvironmentObject private var usgs: USGSService
    @EnvironmentObject private var location: LocationManager

    var body: some View {
        TabView {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map.fill") }

            HazardListScreen()
                .tabItem { Label("Nearby", systemImage: "list.bullet") }

            SnapTriageScreen()
                .tabItem { Label("Report", systemImage: "camera.fill") }

            RiverGaugeScreen()
                .tabItem { Label("Rivers", systemImage: "water.waves") }

            AdminScreen()
                .tabItem { Label("DPW", systemImage: "building.2.fill") }
        }
        .task {
            location.requestPermission()
            location.startUpdates()
            await usgs.refresh()
        }
    }
}
