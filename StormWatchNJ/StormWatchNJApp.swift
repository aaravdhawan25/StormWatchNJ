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
    @Environment(\.scenePhase) private var scenePhase

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
            // the confirmation email, or the website's "Open the app" button
            .onOpenURL { url in Task { await account.handle(url: url) } }
            // back from tapping the link in Mail: sign straight in if it's confirmed
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await account.checkPendingConfirmation() } }
            }
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
