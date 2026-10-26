import SwiftUI
import UIKit

// everything a person can configure about their own app, in one place
struct SettingsScreen: View {
    @EnvironmentObject private var store: HazardStore
    @EnvironmentObject private var usgs: USGSService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var location: LocationManager

    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                notificationSection
                areaSection
                sharingSection
                privacySection
                demoSection
                dataSection
                aboutSection
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                StormHeader(title: "Settings", subtitle: accountSubtitle) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .navigationBarHidden(true)
            .confirmationDialog("Reset all reports to the seeded demo set?",
                                isPresented: $showResetConfirm,
                                titleVisibility: .visible) {
                Button("Reset reports", role: .destructive) { resetEverything() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            NavigationLink {
                AccountScreen()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: account.account?.isTownship == true
                          ? "building.columns.fill" : "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.account?.email ?? "Account")
                            .font(.subheadline.weight(.semibold))
                        Text(accountSubtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var accountSubtitle: String {
        guard let current = account.account else { return "Signed out" }
        return current.isTownship ? "\(current.township ?? "Township") · verified staff" : "Resident"
    }

    private var notificationSection: some View {
        Section {
            switch notifications.authorization {
            case .notDetermined:
                Button {
                    Task { await notifications.requestPermission() }
                } label: {
                    Label("Turn on notifications", systemImage: "bell.badge.fill")
                }
            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label("Notifications are off — open Settings", systemImage: "bell.slash.fill")
                }
            default:
                Toggle("Flood alerts where I am", isOn: $notifications.floodAlertsEnabled)
                Toggle("Impassable roads and downed wires nearby", isOn: $notifications.nearbyHazardsEnabled)
                Toggle("Updates on my reports", isOn: $notifications.myReportsEnabled)
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("StormWatch checks for these when it's open and when iOS lets it refresh in the background, so they can arrive late and won't arrive at all if you force-quit the app. For life-safety warnings, keep Emergency Alerts on in the iPhone's Settings.")
        }
    }

    private var areaSection: some View {
        Section {
            VStack(alignment: .leading) {
                HStack {
                    Text("Search radius")
                    Spacer()
                    Text("\(Int(settings.searchRadiusMiles)) mi").foregroundStyle(.secondary)
                }
                Slider(value: $settings.searchRadiusMiles, in: 1...25, step: 1)
            }
            LabeledContent("Location") {
                Text(location.statusDescription)
                    .font(.caption)
                    .multilineTextAlignment(.trailing)
            }
            if location.mode == .denied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label("Turn on location in Settings", systemImage: "location.fill")
                }
            }
        } header: {
            Text("Your area")
        } footer: {
            Text("The map, the Nearby list and hazard notifications all use this radius around where you are.")
        }
    }

    private var sharingSection: some View {
        Section {
            Toggle("Offer Nextdoor share after posting", isOn: $settings.offerNextdoorShare)
        } header: {
            Text("Neighborhood sharing")
        } footer: {
            Text("After you post a report, StormWatch NJ offers to open Nextdoor's composer with the details written for you. You review and post it there — nothing is ever sent to Nextdoor automatically, and the photo is not included.")
        }
    }

    private var privacySection: some View {
        Section {
            Label("Photos are analyzed by OpenAI", systemImage: "sparkles")
            Label("Photos are never published", systemImage: "eye.slash.fill")
            Label("Your location is shared only with a report", systemImage: "mappin.and.ellipse")
        } header: {
            Text("Photos and privacy")
        } footer: {
            Text("Each photo you take is sent to OpenAI once to read the scene and fill in the report. It is not stored by StormWatch or shown to anyone. If OpenAI can't be reached, a simpler on-device analysis is used so you can still file. Who filed a report is never shown to other people.")
        }
    }

    private var demoSection: some View {
        Section {
            Toggle("Simulate nor'easter", isOn: Binding(
                get: { settings.simulateNoreaster },
                set: { toggleStorm($0) }
            ))
        } header: {
            Text("Demo")
        } footer: {
            Text("Adds clearly-labelled simulated hazards and pushes every river gauge past flood stage, so the map and alerts can be filmed on a clear day. Turn it off to return to live USGS data.")
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Reset to seeded demo reports", systemImage: "arrow.counterclockwise")
            }
        } footer: {
            Text("Seeded reports are fictional sample data for testing, not records of real incidents.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            Link(destination: URL(string: "https://www.weather.gov/safety/flood")!) {
                Label("Flood safety from the National Weather Service", systemImage: "safari")
            }
        } header: {
            Text("About")
        } footer: {
            Text("StormWatch NJ is a community tool. In an emergency, call 911.")
        }
    }

    // MARK: - Actions

    // turn off the simulation before resetting
    private func resetEverything() {
        if settings.simulateNoreaster { toggleStorm(false) }
        store.resetToSeedData()
    }

    private func toggleStorm(_ isOn: Bool) {
        settings.simulateNoreaster = isOn
        if isOn {
            store.applySimulatedStorm()
            usgs.applySimulatedStorm()
        } else {
            store.clearSimulatedStorm()
            Task { await usgs.clearSimulation() }
        }
    }
}
