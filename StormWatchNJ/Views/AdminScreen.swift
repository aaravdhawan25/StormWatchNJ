import Foundation
import SwiftUI

/// The municipal side of the app: the open dispatch queue, the GeoJSON/CSV export
/// a town DPW can ingest, and the demo + backend controls.
struct AdminScreen: View {
    @EnvironmentObject private var store: HazardStore
    @EnvironmentObject private var usgs: USGSService
    @EnvironmentObject private var settings: AppSettings

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
                queueSection
                exportSection
                demoSection
                backendSection
                dataSection
            }
            .navigationTitle("DPW Console")
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
                Button("Reset reports", role: .destructive) { store.resetToSeedData() }
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
                        HazardRow(report: report)
                    }
                }
            }
        } header: {
            Text("Open dispatch queue · \(openReports.count)")
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

    private var backendSection: some View {
        Section {
            Toggle("Use backend for AI triage", isOn: $settings.useRemoteTriage)

            TextField("http://127.0.0.1:8000", text: $settings.backendURLString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(!settings.useRemoteTriage)

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
            Text("Off, photos are triaged on-device with Apple's Vision framework — no network, no key. On, the app posts to the FastAPI /api/v1/analyze-image endpoint in backend/. If that call fails it falls back to on-device triage.")
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
