import SwiftUI

@main
struct StormWatchNJApp: App {
    @StateObject private var store = HazardStore()
    @StateObject private var usgs = USGSService()
    @StateObject private var location = LocationManager()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(usgs)
                .environmentObject(location)
                .environmentObject(settings)
                .tint(.teal)
        }
    }
}
