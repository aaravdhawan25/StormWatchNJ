import Foundation
import SwiftUI

// the municipal side of the app, shown only to verified township accounts
struct AdminScreen: View {
    @EnvironmentObject private var store: HazardStore
    @EnvironmentObject private var account: AccountStore

    // one sheet for share and preview
    @State private var sheet: AdminSheet?

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
                publicWorksSection
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                StormHeader(title: "DPW Console",
                            subtitle: "\(account.account?.township ?? "Township") · \(openReports.count) open work orders") {
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
        }
    }

    // MARK: - Sections

    private var queueSection: some View {
        Section {
            if openReports.isEmpty {
                Text("No open work orders.").foregroundStyle(.secondary)
            } else {
                ForEach(openReports) { report in
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

    // MARK: - Actions

    private func export(name: String, contents: String) {
        guard let url = ExportService.temporaryFile(named: name, contents: contents) else { return }
        sheet = .share(url)
    }

}

// what the DPW console's single sheet is currently showing
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
