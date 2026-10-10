import CoreLocation
import Foundation
import SwiftUI

struct HazardListScreen: View {
    @EnvironmentObject private var store: HazardStore
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var account: AccountStore

    @State private var typeFilter: HazardType?

    private var reports: [HazardReport] {
        let nearby = store.nearby(location.coordinate, radiusMiles: settings.searchRadiusMiles)
        guard let typeFilter else { return nearby }
        return nearby.filter { $0.reportType == typeFilter }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StormHeader(title: "Nearby Hazards",
                            subtitle: "\(reports.count) active within \(Int(settings.searchRadiusMiles)) miles") {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.85))
                }

                filterRow
                    .padding(.vertical, 10)
                    .background(Color(.systemGroupedBackground))

                if reports.isEmpty {
                    ScrollView {
                        EmptyStateView(
                            symbol: "checkmark.shield.fill",
                            title: typeFilter == nil ? "No active hazards nearby" : "Nothing of that type nearby",
                            message: typeFilter == nil
                                ? "Nothing reported within \(Int(settings.searchRadiusMiles)) miles. Widen the radius in the DPW tab, or be the first to report one."
                                : "Try another filter or widen the search radius."
                        )
                        .padding(.top, 30)
                    }
                    .background(Color(.systemGroupedBackground))
                } else {
                    List {
                        ForEach(reports) { report in
                            ZStack {
                                HazardCard(report: report,
                                           distanceMiles: store.distanceMiles(to: report, from: location.coordinate),
                                           thumbnail: store.photo(for: report))
                                // Invisible link keeps the card's own styling while
                                // still giving push navigation and accessibility.
                                NavigationLink {
                                    HazardDetailView(report: report)
                                } label: { EmptyView() }
                                .opacity(0)
                            }
                            .plainCardRow()
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await HazardSync.pull(into: store, account: account) }
                    .background(Color(.systemGroupedBackground))
                }

                statusFooter
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", symbol: "square.grid.2x2.fill", isOn: typeFilter == nil) {
                    typeFilter = nil
                }
                ForEach(HazardType.allCases) { type in
                    chip(title: type.shortLabel, symbol: type.symbolName, isOn: typeFilter == type) {
                        typeFilter = typeFilter == type ? nil : type
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(title: String, symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                Text(title).font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isOn ? AnyShapeStyle(Theme.teal) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                        in: Capsule())
            .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var statusFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: location.needsAttention ? "location.slash" : "location.fill")
            Text(location.statusDescription)
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
}
