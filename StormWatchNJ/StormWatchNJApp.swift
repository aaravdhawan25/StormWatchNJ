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
            Group {
                if account.isSignedIn {
                    RootView()
                        .transition(.opacity)
                } else {
                    WelcomeScreen()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: account.isSignedIn)
            .task { await account.restore() }
                .environmentObject(store)
                .environmentObject(usgs)
                .environmentObject(location)
                .environmentObject(settings)
                .environmentObject(account)
                .tint(.teal)
        }
    }
}
