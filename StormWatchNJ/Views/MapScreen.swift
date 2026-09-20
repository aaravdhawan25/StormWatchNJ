import CoreLocation
import MapKit
import SwiftUI

struct MapScreen: View {
    @EnvironmentObject private var store: HazardStore
    @EnvironmentObject private var usgs: USGSService
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var settings: AppSettings

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: LocationManager.defaultCoordinate,
                           span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35))
    )
    /// One sheet state for both pin kinds — stacking two `.sheet` modifiers on the
    /// same view does not reliably present both.
    @State private var sheet: MapSheet?
    @State private var showGauges = true

    private var visibleReports: [HazardReport] {
        store.nearby(location.coordinate, radiusMiles: settings.searchRadiusMiles)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                map
                overlayBar
            }
            .navigationTitle("StormWatch NJ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        recenter()
                    } label: {
                        Image(systemName: "location.circle")
                    }
                    .accessibilityLabel("Recenter map")
                }
            }
            .sheet(item: $sheet) { destination in
                NavigationStack {
                    switch destination {
                    case .report(let report):
                        HazardDetailView(report: report)
                    case .station(let station):
                        StationDetailView(station: station)
                    }
                }
                .presentationDetents([.medium, .large])
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

    private var overlayBar: some View {
        VStack(spacing: 8) {
            if settings.simulateNoreaster {
                Label("Simulated nor'easter active — this data is not real.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 10) {
                summaryChip(count: visibleReports.filter { $0.severity == .impassable }.count,
                            label: "impassable", tint: .red)
                summaryChip(count: visibleReports.filter { $0.utilityLinesInvolved }.count,
                            label: "wires down", tint: .orange)
                summaryChip(count: usgs.stationsNeedingAttention.count,
                            label: "rivers rising", tint: .blue)

                Spacer(minLength: 0)

                Toggle(isOn: $showGauges) {
                    Image(systemName: "water.waves")
                }
                .toggleStyle(.button)
                .accessibilityLabel("Show river gauges")
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private func summaryChip(count: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 0) {
            Text("\(count)").font(.headline).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 56)
    }

    private func recenter() {
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
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
