import Foundation
import SwiftUI

struct SeverityBadge: View {
    let severity: Severity
    var compact = false

    var body: some View {
        Text(severity.label.uppercased())
            .font(compact ? .system(size: 9, weight: .bold) : .caption2.weight(.bold))
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 3 : 4)
            .background(severity.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(severity.tint)
    }
}

/// Map pin for a hazard report. Impassable hazards get a soft halo so the
/// worst problems read first at a glance.
struct HazardPin: View {
    let report: HazardReport
    var isSelected: Bool = false

    private var diameter: CGFloat { isSelected ? 42 : 32 }

    var body: some View {
        ZStack {
            if report.severity == .impassable {
                Circle()
                    .fill(report.severity.tint.opacity(0.22))
                    .frame(width: diameter * 1.75, height: diameter * 1.75)
            }
            Circle()
                .fill(report.severity.tint)
                .frame(width: diameter, height: diameter)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            Circle()
                .stroke(.white, lineWidth: 2.5)
                .frame(width: diameter, height: diameter)
            Image(systemName: report.reportType.symbolName)
                .font(.system(size: isSelected ? 18 : 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .animation(.spring(duration: 0.25), value: isSelected)
    }
}

struct GaugePin: View {
    let station: USGSStation

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(station.alert.tint)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white, lineWidth: 2)
                .frame(width: 28, height: 28)
            Image(systemName: "water.waves")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

/// Level bar showing how close a river is to flood stage, with a marked threshold.
struct FloodStageBar: View {
    let station: USGSStation

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(LinearGradient(colors: [station.alert.tint.opacity(0.7), station.alert.tint],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, width * station.floodProgress))
                // Action-stage tick.
                if station.floodStageFt > 0 {
                    let ratio = min(max(station.actionStageFt / station.floodStageFt, 0), 1)
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 2, height: 14)
                        .offset(x: width * ratio - 1)
                }
            }
        }
        .frame(height: 10)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(Theme.teal.opacity(0.7))
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
    }
}

/// Rich card row used by the nearby list and the DPW queue.
struct HazardCard: View {
    let report: HazardReport
    var distanceMiles: Double?
    var thumbnail: UIImage?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Severity stripe.
            Rectangle()
                .fill(report.severity.tint)
                .frame(width: 4)

            HStack(alignment: .top, spacing: 12) {
                thumbnailView

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(report.reportType.label)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        SeverityBadge(severity: report.severity, compact: true)
                    }

                    Text(report.details)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        if let distanceMiles {
                            Label(String(format: "%.1f mi", distanceMiles), systemImage: "location.fill")
                        }
                        Label(report.createdAt.shortRelative, systemImage: "clock")
                        if report.utilityLinesInvolved {
                            Label("Wires", systemImage: "bolt.trianglebadge.exclamationmark.fill")
                                .foregroundStyle(.red)
                        }
                        if report.status == .inProgress {
                            Label("Crew", systemImage: "figure.walk")
                                .foregroundStyle(Theme.teal)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(report.severity.tint.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: report.reportType.symbolName)
                    .font(.title3)
                    .foregroundStyle(report.severity.tint)
            }
        }
    }
}

extension Date {
    /// Relative time that reads naturally for very recent instants —
    /// `RelativeDateTimeFormatter` alone renders "in 0 seconds" for now.
    var shortRelative: String {
        let elapsed = Date().timeIntervalSince(self)
        if elapsed < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
