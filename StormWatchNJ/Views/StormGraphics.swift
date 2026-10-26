import SwiftUI

// a filled wave: a sine curve along the top edge, solid below it
struct WaveShape: Shape {
    var phase: CGFloat
    var amplitude: CGFloat = 10
    var cycles: CGFloat = 1.5

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        var x: CGFloat = 0
        while x <= rect.width {
            let progress = x / max(rect.width, 1)
            let y = amplitude + sin(progress * .pi * 2 * cycles + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 3
        }
        path.addLine(to: CGPoint(x: rect.width, y: amplitude + sin(.pi * 2 * cycles + phase) * amplitude))
        path.addLine(to: CGPoint(x: rect.width, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// the storm scene behind the welcome and sign-in screens
struct StormBackdrop: View {
    var animated = true
    // how far up the screen the water reaches, 0...1
    var waterLevel: CGFloat = 0.24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.06, blue: 0.14),
                                    Theme.navy, Theme.deep,
                                    Color(red: 0.05, green: 0.32, blue: 0.40)],
                           startPoint: .top, endPoint: .bottom)

            // soft glow where the storm light comes through
            RadialGradient(colors: [Theme.brightTeal.opacity(0.22), .clear],
                           center: UnitPoint(x: 0.5, y: 0.28), startRadius: 10, endRadius: 320)

            if animated && !reduceMotion {
                TimelineView(.animation) { timeline in
                    scene(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                scene(time: 0)
            }
        }
        .ignoresSafeArea()
    }

    private func scene(time: TimeInterval) -> some View {
        Canvas { context, size in
            drawRain(in: &context, size: size, time: time)
            drawWater(in: &context, size: size, time: time)
        }
    }

    private func drawRain(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        var streaks = Path()
        for index in 0..<90 {
            // cheap deterministic pseudo-random values, stable per drop
            let seed = Double(index)
            let column = (sin(seed * 12.9898) * 43_758.5453).truncatingRemainder(dividingBy: 1).magnitude
            let offset = (sin(seed * 78.233) * 12_345.678).truncatingRemainder(dividingBy: 1).magnitude
            let speed = 380 + column * 260
            let length = 14 + offset * 22

            let travel = size.height + 80
            let y = ((time * speed + offset * travel).truncatingRemainder(dividingBy: travel)) - 40
            let x = column * (size.width + 120) - 60 + y * 0.22
            streaks.move(to: CGPoint(x: x, y: y))
            streaks.addLine(to: CGPoint(x: x + length * 0.22, y: y + length))
        }
        context.stroke(streaks, with: .color(Color(red: 0.62, green: 0.82, blue: 0.90).opacity(0.28)),
                       lineWidth: 1.4)
    }

    private func drawWater(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let top = size.height * (1 - waterLevel)
        let bands: [(offset: CGFloat, amplitude: CGFloat, speed: Double, color: Color)] = [
            (0, 12, 0.7, Color(red: 0.06, green: 0.46, blue: 0.54)),
            (34, 10, -1.0, Color(red: 0.09, green: 0.62, blue: 0.69)),
            (70, 8, 1.3, Color(red: 0.18, green: 0.78, blue: 0.82))
        ]
        for band in bands {
            let rect = CGRect(x: 0, y: top + band.offset, width: size.width,
                              height: size.height - top - band.offset)
            let wave = WaveShape(phase: CGFloat(time * band.speed), amplitude: band.amplitude, cycles: 1.4)
            context.translateBy(x: 0, y: rect.minY)
            context.fill(wave.path(in: CGRect(origin: .zero, size: rect.size)), with: .color(band.color.opacity(0.92)))
            context.translateBy(x: 0, y: -rect.minY)
        }
    }
}

// the app's mark: a lightning bolt over water, matching the home-screen icon
struct AppLogoMark: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Theme.navy, Theme.deep, Color(red: 0.06, green: 0.36, blue: 0.42)],
                           startPoint: .top, endPoint: .bottom)
            WaveShape(phase: 0.4, amplitude: size * 0.035)
                .fill(Color(red: 0.06, green: 0.46, blue: 0.54))
                .frame(height: size * 0.36)
            WaveShape(phase: 2.1, amplitude: size * 0.03)
                .fill(Theme.teal)
                .frame(height: size * 0.27)
            WaveShape(phase: 3.6, amplitude: size * 0.025)
                .fill(Theme.brightTeal)
                .frame(height: size * 0.18)
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(Theme.amber)
                .shadow(color: Theme.amber.opacity(0.7), radius: size * 0.09)
                .frame(maxHeight: .infinity)
                .offset(y: -size * 0.07)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .stroke(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: size * 0.16, y: size * 0.07)
        .accessibilityHidden(true)
    }
}

extension HazardType {
    // each hazard gets its own colour family
    var gradient: [Color] {
        switch self {
        case .streetFlooding:
            return [Color(red: 0.12, green: 0.45, blue: 0.86), Color(red: 0.14, green: 0.72, blue: 0.84)]
        case .cloggedDrain:
            return [Color(red: 0.30, green: 0.32, blue: 0.78), Color(red: 0.24, green: 0.58, blue: 0.86)]
        case .downedTree:
            return [Color(red: 0.10, green: 0.50, blue: 0.32), Color(red: 0.42, green: 0.72, blue: 0.30)]
        case .downedWire:
            return [Color(red: 0.86, green: 0.24, blue: 0.16), Color(red: 0.98, green: 0.66, blue: 0.16)]
        case .other:
            return [Color(red: 0.36, green: 0.38, blue: 0.48), Color(red: 0.56, green: 0.52, blue: 0.70)]
        }
    }
}

// illustrated tile for a hazard type
struct HazardGlyph: View {
    let type: HazardType
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: type.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            // glossy top-left highlight
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.32), .clear],
                                     startPoint: .topLeading, endPoint: .center))
            Image(systemName: type.symbolName)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: type.gradient[0].opacity(0.35), radius: size * 0.12, y: size * 0.06)
        .accessibilityHidden(true)
    }
}

// a small tank that fills with water to show how close a river is to flooding
struct LiquidGauge: View {
    // 0 = empty, 1 = at flood stage
    let level: Double
    let tint: Color
    var size = CGSize(width: 44, height: 58)

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
            GeometryReader { geometry in
                let fill = max(0.08, min(level, 1)) * geometry.size.height
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    WaveShape(phase: 1.2, amplitude: 3, cycles: 1)
                        .fill(LinearGradient(colors: [tint.opacity(0.75), tint],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: fill + 6)
                }
            }
            // flood-stage line near the top
            VStack {
                Rectangle().fill(Color.primary.opacity(0.35)).frame(height: 1.5).padding(.horizontal, 5)
                Spacer()
            }
            .padding(.top, 6)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(tint.opacity(0.45), lineWidth: 1.5))
        .accessibilityHidden(true)
    }
}
