import SwiftUI

/// One place for colour, elevation and shape so every screen reads as one app.
enum Theme {
    static let navy = Color(red: 0.04, green: 0.10, blue: 0.20)
    static let deep = Color(red: 0.05, green: 0.18, blue: 0.31)
    static let teal = Color(red: 0.09, green: 0.62, blue: 0.69)
    static let brightTeal = Color(red: 0.18, green: 0.78, blue: 0.82)
    static let amber = Color(red: 1.0, green: 0.82, blue: 0.40)

    static let headerGradient = LinearGradient(
        colors: [navy, deep, teal.opacity(0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardCorner: CGFloat = 16
}

/// Standard raised card used by the list, river and report screens.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

extension View {
    func stormCard(padding: CGFloat = 14) -> some View {
        modifier(CardBackground(padding: padding))
    }

    /// Hides the default list chrome so cards can sit directly on the background.
    func plainCardRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
}

/// Gradient screen header with a title, subtitle and optional trailing content.
struct StormHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            // Storm sky that ends in water: the lowest wave is the page colour,
            // so the header's edge is a wave rather than a hard line.
            ZStack(alignment: .bottom) {
                Theme.headerGradient
                RadialGradient(colors: [Theme.brightTeal.opacity(0.35), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 260)
                WaveShape(phase: 0.6, amplitude: 9, cycles: 1.2)
                    .fill(.white.opacity(0.08))
                    .frame(height: 40)
                WaveShape(phase: 2.6, amplitude: 7, cycles: 1.6)
                    .fill(Theme.brightTeal.opacity(0.30))
                    .frame(height: 27)
                WaveShape(phase: 4.3, amplitude: 6, cycles: 1.3)
                    .fill(Color(.systemGroupedBackground))
                    .frame(height: 15)
            }
            .ignoresSafeArea(edges: .top)
        }
    }
}

extension StormHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Small stat readout used in the map overlay and the DPW console.
struct StatTile: View {
    let value: String
    let label: String
    let tint: Color
    var symbol: String?

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.caption2.weight(.bold))
                }
                Text(value).font(.title3.weight(.bold))
            }
            .foregroundStyle(tint)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Circular confidence readout for the triage result.
struct ConfidenceRing: View {
    let value: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.02, min(value, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("%").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 58, height: 58)
        .animation(.easeOut(duration: 0.5), value: value)
    }
}

/// Small rounded label used for evidence and filters.
struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            }
            Text(text).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14), in: Capsule())
        .foregroundStyle(tint)
    }
}
