import CoreLocation
import Foundation
import SwiftUI

struct HazardListScreen: View {
    @EnvironmentObject private var store: HazardStore
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var settings: AppSettings

    @State private var typeFilter: HazardType?

    private var reports: [HazardReport] {
        let nearby = store.nearby(location.coordinate, radiusMiles: settings.searchRadiusMiles)
        guard let typeFilter else { return nearby }
        return nearby.filter { $0.reportType == typeFilter }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filterRow
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                if reports.isEmpty {
                    EmptyStateView(symbol: "checkmark.shield",
                                   title: "No active hazards nearby",
                                   message: "Nothing reported within \(Int(settings.searchRadiusMiles)) miles. Widen the radius in the DPW tab or pull to refresh.")
                        .listRowSeparator(.hidden)
                } else {
                    Section("Within \(Int(settings.searchRadiusMiles)) miles, nearest first") {
                        ForEach(reports) { report in
                            NavigationLink {
                                HazardDetailView(report: report)
                            } label: {
                                HazardRow(report: report,
                                          distanceMiles: store.distanceMiles(to: report, from: location.coordinate))
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Nearby Hazards")
            .overlay(alignment: .bottom) {
                Text(location.statusDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isOn: typeFilter == nil) { typeFilter = nil }
                ForEach(HazardType.allCases) { type in
                    chip(title: type.label, isOn: typeFilter == type) {
                        typeFilter = typeFilter == type ? nil : type
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isOn ? Color.teal : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
