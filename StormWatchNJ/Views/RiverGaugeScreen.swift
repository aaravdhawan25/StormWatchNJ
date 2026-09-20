import Foundation
import MapKit
import SwiftUI

struct RiverGaugeScreen: View {
    @EnvironmentObject private var usgs: USGSService

    var body: some View {
        NavigationStack {
            List {
                statusSection

                Section("New Jersey river gauges") {
                    ForEach(usgs.stations) { station in
                        NavigationLink {
                            StationDetailView(station: station)
                        } label: {
                            stationRow(station)
                        }
                    }
                }
            }
            .navigationTitle("River Telemetry")
            .refreshable { await usgs.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await usgs.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(usgs.isLoading || usgs.isSimulating)
                }
            }
        }
    }

    private var statusSection: some View {
        Section {
            if usgs.isSimulating {
                Label("Showing simulated nor'easter levels, not live USGS data.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if usgs.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Polling USGS Water Services…").foregroundStyle(.secondary)
                }
                .font(.footnote)
            } else if let error = usgs.lastError {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if let refreshed = usgs.lastRefreshed {
                Label("Live gage heights, updated \(refreshed.shortRelative).", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Pull to load live gage heights.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stationRow(_ station: USGSStation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(station.stationName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(station.alert.label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(station.alert.tint.opacity(0.2), in: Capsule())
                    .foregroundStyle(station.alert.tint)
            }

            FloodStageBar(station: station)

            HStack {
                if let height = station.currentGaugeHeightFt {
                    Text(String(format: "%.2f ft now", height))
                } else {
                    Text("No reading")
                }
                Text("·")
                Text(String(format: "flood stage %.1f ft", station.floodStageFt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
