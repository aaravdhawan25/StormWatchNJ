import SwiftUI

@main
struct StormWatchNJApp: App {
    @StateObject private var store = AppServices.shared.store
    @StateObject private var usgs = AppServices.shared.usgs
    @StateObject private var location = AppServices.shared.location
    @StateObject private var settings = AppServices.shared.settings
    @StateObject private var account = AppServices.shared.account
    @StateObject private var floodAlerts = AppServices.shared.floodAlerts
    @StateObject private var notifications = AppServices.shared.notifications

    init() {
        BackgroundRefresh.register()
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
                .environmentObject(floodAlerts)
                .environmentObject(notifications)
                .tint(.teal)
        }
    }
}
