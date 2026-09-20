import Foundation
import MapKit
import SwiftUI

struct HazardDetailView: View {
    let report: HazardReport

    @EnvironmentObject private var store: HazardStore
    @EnvironmentObject private var location: LocationManager
    @Environment(\.dismiss) private var dismiss

    /// Read back from the store so upvotes and status changes show immediately.
    private var current: HazardReport {
        store.reports.first(where: { $0.id == report.id }) ?? report
    }

    var body: some View {
        List {
            if let photo = store.photo(for: current) {
                Section {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .clipped()
                        .listRowInsets(EdgeInsets())
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(current.severity.tint.opacity(0.18)).frame(width: 42, height: 42)
                            Image(systemName: current.reportType.symbolName)
                                .font(.title3)
                                .foregroundStyle(current.severity.tint)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.reportType.label).font(.headline)
                            Text(current.municipality).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        SeverityBadge(severity: current.severity)
                    }

                    Text(current.details).font(.subheadline)

                    if current.utilityLinesInvolved {
                        WireWarningBanner()
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Details") {
                LabeledContent("Road", value: current.roadStatus.label)
                LabeledContent("Status", value: current.status.label)
                LabeledContent("Municipality", value: current.municipality)
                LabeledContent("Distance",
                               value: String(format: "%.1f mi away",
                                             store.distanceMiles(to: current, from: location.coordinate)))
                LabeledContent("Reported", value: current.createdAt.shortRelative)
                LabeledContent("Confirmations", value: "\(current.upvotes)")
            }

            Section {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: current.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))) {
                    Annotation(current.reportType.label, coordinate: current.coordinate) {
                        HazardPin(report: current)
                    }
                }
                .frame(height: 180)
                .listRowInsets(EdgeInsets())
                .allowsHitTesting(false)
            }

            Section("Still there?") {
                Button {
                    store.upvote(current)
                } label: {
                    Label("Confirm this hazard", systemImage: "hand.thumbsup.fill")
                }

                Picker("Crew status", selection: Binding(
                    get: { current.status },
                    set: { store.setStatus($0, for: current) }
                )) {
                    ForEach(ReportStatus.allCases) { Text($0.label).tag($0) }
                }

                Button(role: .destructive) {
                    store.delete(current)
                    dismiss()
                } label: {
                    Label("Remove report", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Hazard")
        .navigationBarTitleDisplayMode(.inline)
    }
}
