import Foundation
import SwiftUI

struct SeverityBadge: View {
    let severity: Severity

    var body: some View {
        Text(severity.label.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(severity.tint.opacity(0.2), in: Capsule())
            .foregroundStyle(severity.tint)
    }
}

struct WireWarningBadge: View {
    var body: some View {
        Label("Utility lines involved", systemImage: "bolt.trianglebadge.exclamationmark.fill")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.15), in: Capsule())
            .foregroundStyle(.red)
    }
}

/// The pin drawn on the map for a hazard report.
struct HazardPin: View {
    let report: HazardReport
    var isSelected: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(report.severity.tint)
                .frame(width: isSelected ? 40 : 30, height: isSelected ? 40 : 30)
                .shadow(radius: 3)
            Image(systemName: report.reportType.symbolName)
                .font(.system(size: isSelected ? 18 : 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(
            Circle()
                .stroke(.white, lineWidth: 2)
                .frame(width: isSelected ? 40 : 30, height: isSelected ? 40 : 30)
        )
        .animation(.spring(duration: 0.25), value: isSelected)
    }
}

struct GaugePin: View {
    let station: USGSStation

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(station.alert.tint)
                .frame(width: 28, height: 28)
                .shadow(radius: 2)
            Image(systemName: "water.waves")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 2).frame(width: 28, height: 28))
    }
}

/// Horizontal bar showing how close a river is to its flood stage.
struct FloodStageBar: View {
    let station: USGSStation

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(station.alert.tint)
                    .frame(width: max(6, geometry.size.width * station.floodProgress))
            }
        }
        .frame(height: 8)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

/// Row used in both the nearby list and the DPW queue.
struct HazardRow: View {
    let report: HazardReport
    var distanceMiles: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(report.severity.tint.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: report.reportType.symbolName)
                    .foregroundStyle(report.severity.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(report.reportType.label).font(.subheadline.weight(.semibold))
                Text(report.details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    SeverityBadge(severity: report.severity)
                    if let distanceMiles {
                        Label(String(format: "%.1f mi", distanceMiles), systemImage: "location.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if report.utilityLinesInvolved {
                        Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

extension Date {
    var shortRelative: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
