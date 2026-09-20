import CoreLocation
import MapKit
import SwiftUI

struct MapScreen: View {
    @EnvironmentObject private var store: HazardStore
    @EnvironmentObject private var usgs: USGSService
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var settings: AppSettings

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: NJServiceArea.demoCenter,
                           span: MKCoordinateSpan(latitudeDelta: 0.28, longitudeDelta: 0.28))
    )
    /// One sheet state for both pin kinds — stacking two `.sheet` modifiers on the
    /// same view does not reliably present both.
    @State private var sheet: MapSheet?
    @State private var showGauges = true
    /// Set once the camera has been moved to the first usable coordinate.
    @State private var hasCentred = false

    private var visibleReports: [HazardReport] {
        store.nearby(location.coordinate, radiusMiles: settings.searchRadiusMiles)
    }

    private var worstNearby: HazardReport? {
        visibleReports.max { $0.severity.weight < $1.severity.weight }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                map
                VStack(spacing: 8) {
                    statusStrip
                    if location.needsAttention { locationNotice }
                    if settings.simulateNoreaster { simulationNotice }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
            }
            .overlay(alignment: .bottom) { nearestCard }
            .navigationTitle("StormWatch NJ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { recenter() } label: {
                        Image(systemName: "location.circle.fill").font(.title3)
                    }
                    .accessibilityLabel("Recenter map")
                }
            }
            .sheet(item: $sheet) { destination in
                NavigationStack {
                    switch destination {
                    case .report(let report): HazardDetailView(report: report)
                    case .station(let station): StationDetailView(station: station)
                    }
                }
                .presentationDetents([.medium, .large])
            }
            // Move the camera to the first usable coordinate, then leave it alone
            // so the map does not fight the user's panning.
            .onChange(of: location.coordinate.latitude) { _, _ in
                guard !hasCentred else { return }
                hasCentred = true
                recenter()
            }
        }
    }

    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()

            ForEach(visibleReports) { report in
                Annotation(report.reportType.label, coordinate: report.coordinate) {
                    HazardPin(report: report, isSelected: sheet?.id == report.id.uuidString)
                        .onTapGesture { sheet = .report(report) }
                }
            }

            if showGauges {
                ForEach(usgs.stations) { station in
                    Annotation(station.stationName, coordinate: station.coordinate) {
                        GaugePin(station: station)
                            .onTapGesture { sheet = .station(station) }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .ignoresSafeArea(edges: .bottom)
    }

    private var statusStrip: some View {
        HStack(spacing: 4) {
            StatTile(value: "\(visibleReports.filter { $0.severity == .impassable }.count)",
                     label: "impassable", tint: .red, symbol: "xmark.octagon.fill")
            Divider().frame(height: 26)
            StatTile(value: "\(visibleReports.filter { $0.utilityLinesInvolved }.count)",
                     label: "wires down", tint: .orange, symbol: "bolt.fill")
            Divider().frame(height: 26)
            StatTile(value: "\(usgs.stationsNeedingAttention.count)",
                     label: "rivers rising", tint: Theme.teal, symbol: "water.waves")
            Divider().frame(height: 26)

            Button {
                withAnimation { showGauges.toggle() }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: showGauges ? "drop.fill" : "drop")
                        .font(.body.weight(.semibold))
                    Text("gauges").font(.caption2)
                }
                .foregroundStyle(showGauges ? Theme.teal : .secondary)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showGauges ? "Hide river gauges" : "Show river gauges")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private var locationNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.slash.fill").font(.caption)
            Text(location.statusDescription).font(.caption2.weight(.medium))
            Spacer(minLength: 0)
            if location.mode == .awaitingPermission {
                Button("Allow") { location.requestPermission() }
                    .font(.caption2.weight(.bold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }

    private var simulationNotice: some View {
        Label("Simulated nor'easter — this data is not real", systemImage: "exclamationmark.triangle.fill")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(.orange, in: Capsule())
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    /// Floating card for the most severe nearby hazard — the thing a commuter
    /// most needs to know without hunting for a pin.
    @ViewBuilder
    private var nearestCard: some View {
        if let report = worstNearby {
            Button {
                sheet = .report(report)
            } label: {
                HStack(spacing: 11) {
                    ZStack {
                        Circle().fill(report.severity.tint.opacity(0.18)).frame(width: 40, height: 40)
                        Image(systemName: report.reportType.symbolName)
                            .foregroundStyle(report.severity.tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.reportType.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(String(format: "%.1f mi away · %@",
                                    store.distanceMiles(to: report, from: location.coordinate),
                                    report.municipality))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private func recenter() {
        withAnimation(.easeInOut(duration: 0.5)) {
            camera = .region(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.22, longitudeDelta: 0.22)
            ))
        }
    }
}

/// What the map's single sheet is currently showing.
enum MapSheet: Identifiable {
    case report(HazardReport)
    case station(USGSStation)

    var id: String {
        switch self {
        case .report(let report): return report.id.uuidString
        case .station(let station): return station.siteID
        }
    }
}
