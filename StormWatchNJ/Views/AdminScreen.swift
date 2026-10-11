import Foundation
import SwiftUI

/// The municipal side of the app: the open dispatch queue, the GeoJSON/CSV export
/// a town DPW can ingest, and the demo + backend controls.
struct AdminScreen: View {
    @EnvironmentObject private var store: HazardStore
    @EnvironmentObject private var usgs: USGSService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var notifications: NotificationManager

    /// One sheet state for share and preview — stacking two `.sheet` modifiers on
    /// the same view does not reliably present both.
    @State private var sheet: AdminSheet?
    @State private var showResetConfirm = false

    private var openReports: [HazardReport] {
        store.reports
            .filter { $0.status != .resolved }
            .sorted { lhs, rhs in
                if lhs.severity.weight != rhs.severity.weight {
                    return lhs.severity.weight > rhs.severity.weight
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                queueSection
                exportSection
                publicWorksSection
                notificationSection
                sharingSection
                demoSection
                backendSection
                dataSection
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                StormHeader(title: "DPW Console",
                            subtitle: "\(openReports.count) open work orders") {
                    Image(systemName: "building.2.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $sheet) { destination in
                switch destination {
                case .share(let url):
                    ShareSheet(items: [url])
                case .preview(let text):
                    NavigationStack {
                        ScrollView {
                            Text(text)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .navigationTitle("Export preview")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            .confirmationDialog("Reset all reports to the seeded demo set?",
                                isPresented: $showResetConfirm,
                                titleVisibility: .visible) {
                Button("Reset reports", role: .destructive) { resetEverything() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Sections

    private var queueSection: some View {
        Section {
            if openReports.isEmpty {
                Text("No open work orders.").foregroundStyle(.secondary)
            } else {
                ForEach(openReports.prefix(6)) { report in
                    NavigationLink {
                        HazardDetailView(report: report)
                    } label: {
                        HStack(spacing: 10) {
                            HazardGlyph(type: report.reportType, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(report.reportType.label).font(.subheadline.weight(.medium))
                                Text("\(report.municipality) · \(report.createdAt.shortRelative)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            SeverityBadge(severity: report.severity, compact: true)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } header: {
            Text("Open dispatch queue")
        } footer: {
            Text("Sorted by severity, then most recently updated — the order a crew would work it.")
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                export(name: "stormwatch_nj_hazards.geojson",
                       contents: ExportService.geoJSON(from: openReports))
            } label: {
                Label("Export GeoJSON", systemImage: "square.and.arrow.up")
            }

            Button {
                export(name: "stormwatch_nj_hazards.csv",
                       contents: ExportService.csv(from: openReports))
            } label: {
                Label("Export CSV", systemImage: "tablecells")
            }

            Button {
                sheet = .preview(ExportService.geoJSON(from: openReports))
            } label: {
                Label("Preview GeoJSON", systemImage: "eye")
            }
        } header: {
            Text("Municipal export")
        } footer: {
            Text("RFC 7946 FeatureCollection with longitude-first coordinates, ready for ArcGIS, QGIS or a routing tool.")
        }
    }

    private var demoSection: some View {
        Section {
            Toggle("Simulate nor'easter", isOn: Binding(
                get: { settings.simulateNoreaster },
                set: { toggleStorm($0) }
            ))
        } header: {
            Text("Demo controls")
        } footer: {
            Text("Adds clearly-labelled simulated hazards and pushes every river gauge past flood stage, so the map and alerts can be filmed on a clear day. Turn it off to return to live USGS data.")
        }
    }

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
        guard let current = account.account else { return "" }
        return current.isTownship ? "\(current.township ?? "Township") · verified staff" : "Resident"
    }

    private var publicWorksSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live GIS feed").font(.caption).foregroundStyle(.secondary)
                Text(SupabaseConfig.feedURL.absoluteString)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            ShareLink(item: SupabaseConfig.feedURL) {
                Label("Share feed link", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Public works relay")
        } footer: {
            Text("Every report you post is filed over the Open311 civic standard, and towns that have opted in receive it at their public works desk. The feed link can be added to ArcGIS Online or QGIS as a live layer. Photos are never sent.")
        }
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

    private var sharingSection: some View {
        Section {
            Toggle("Offer Nextdoor share after posting", isOn: $settings.offerNextdoorShare)
        } header: {
            Text("Neighborhood sharing")
        } footer: {
            Text("After you post a report, StormWatch NJ offers to open Nextdoor's composer with the details written for you. You review and post it there — nothing is ever sent to Nextdoor automatically, and the photo is not included.")
        }
    }

    private var backendSection: some View {
        Section {
            VStack(alignment: .leading) {
                HStack {
                    Text("Search radius")
                    Spacer()
                    Text("\(Int(settings.searchRadiusMiles)) mi").foregroundStyle(.secondary)
                }
                Slider(value: $settings.searchRadiusMiles, in: 1...25, step: 1)
            }
        } header: {
            Text("Configuration")
        } footer: {
            Text("Photos you take are analyzed by OpenAI, which reads the scene and fills in the report. They are not stored by StormWatch or published. If OpenAI can't be reached, the app uses a simpler on-device analysis so you can still file.")
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

    // MARK: - Actions

    private func export(name: String, contents: String) {
        guard let url = ExportService.temporaryFile(named: name, contents: contents) else { return }
        sheet = .share(url)
    }

    /// Resetting while the simulation is on would wipe the simulated hazards but
    /// leave the toggle reading "on", so the switch would be lying about the state
    /// of the app. Clear the simulation first, then reseed.
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

/// What the DPW console's single sheet is currently showing.
enum AdminSheet: Identifiable {
    case share(URL)
    case preview(String)

    var id: String {
        switch self {
        case .share(let url): return "share:" + url.absoluteString
        case .preview: return "preview"
        }
    }
}
