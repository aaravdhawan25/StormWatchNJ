import Foundation
import MapKit
import SwiftUI

struct RiverGaugeScreen: View {
    @EnvironmentObject private var usgs: USGSService

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    statusBanner
                    ForEach(usgs.stations) { station in
                        NavigationLink {
                            StationDetailView(station: station)
                        } label: {
                            stationCard(station)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .top, spacing: 0) {
                StormHeader(title: "River Telemetry",
                            subtitle: "\(usgs.stations.count) NJ gauges · live from USGS") {
                    Button {
                        Task { await usgs.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .disabled(usgs.isLoading || usgs.isSimulating)
                    .accessibilityLabel("Refresh gauges")
                }
            }
            .navigationBarHidden(true)
            .refreshable { await usgs.refresh() }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        Group {
            if usgs.isSimulating {
                banner("Simulated nor'easter levels, not live USGS data.",
                       symbol: "exclamationmark.triangle.fill", tint: .orange)
            } else if usgs.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Polling USGS Water Services…").font(.caption)
                    Spacer(minLength: 0)
                }
                .stormCard(padding: 12)
            } else if let error = usgs.lastError {
                banner(error, symbol: "wifi.exclamationmark", tint: .orange)
            } else if let refreshed = usgs.lastRefreshed {
                banner("Live gage heights, updated \(refreshed.shortRelative).",
                       symbol: "antenna.radiowaves.left.and.right", tint: Theme.teal)
            } else {
                banner("Pull to load live gage heights.", symbol: "arrow.down", tint: .secondary)
            }
        }
    }

    private func banner(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.caption)
            Text(text).font(.caption)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .stormCard(padding: 12)
    }

    private func stationCard(_ station: USGSStation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.stationName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(station.county) County")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(station.alert.label)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(station.alert.tint.opacity(0.18), in: Capsule())
                    .foregroundStyle(station.alert.tint)
            }

            FloodStageBar(station: station)

            HStack(spacing: 4) {
                if let height = station.currentGaugeHeightFt {
                    Text(String(format: "%.2f ft", height))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(station.alert.tint)
                } else {
                    Text("No reading").font(.caption).foregroundStyle(.secondary)
                }
                Text(String(format: "· flood stage %.1f ft", station.floodStageFt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let margin = station.feetBelowFloodStage, margin > 0 {
                    Text(String(format: "%.1f ft to go", margin))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .stormCard()
    }
}

struct StationDetailView: View {
    let station: USGSStation

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(station.stationName).font(.headline)
                    Text("\(station.county) County · USGS \(station.siteID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FloodStageBar(station: station)
                }
                .padding(.vertical, 4)
            }

            Section("Readings") {
                LabeledContent("Current gage height",
                               value: station.currentGaugeHeightFt.map { String(format: "%.2f ft", $0) } ?? "—")
                LabeledContent("Action stage", value: String(format: "%.1f ft", station.actionStageFt))
                LabeledContent("Flood stage", value: String(format: "%.1f ft", station.floodStageFt))
                if let margin = station.feetBelowFloodStage {
                    LabeledContent(margin >= 0 ? "Below flood stage" : "Above flood stage",
                                   value: String(format: "%.2f ft", abs(margin)))
                }
                LabeledContent("Alert", value: station.alert.label)
                LabeledContent("Reading time", value: station.lastUpdated?.shortRelative ?? "—")
            }

            Section {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: station.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
                ))) {
                    Annotation(station.stationName, coordinate: station.coordinate) {
                        GaugePin(station: station)
                    }
                }
                .frame(height: 180)
                .listRowInsets(EdgeInsets())
                .allowsHitTesting(false)
            }

            Section {
                Text("Gage height comes from the USGS Water Services instantaneous-values API (parameter 00065). Action and flood thresholds in this build are demo values and must be replaced with official NWS AHPS stages before real use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Gauge")
        .navigationBarTitleDisplayMode(.inline)
    }
}
