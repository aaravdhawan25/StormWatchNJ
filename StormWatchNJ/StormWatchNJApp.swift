import SwiftUI

@main
struct StormWatchNJApp: App {
    @StateObject private var store = HazardStore()
    @StateObject private var usgs = USGSService()
    @StateObject private var location = LocationManager()
    @StateObject private var settings: AppSettings
    @StateObject private var account: AccountStore

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _account = StateObject(wrappedValue: AccountStore(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(usgs)
                .environmentObject(location)
                .environmentObject(settings)
                .environmentObject(account)
                .tint(.teal)
        }
    }
}
