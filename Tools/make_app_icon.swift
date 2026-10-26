// renders Assets.xcassets/AppIcon.appiconset/AppIcon.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
              ? CommandLine.arguments[1]
              : "AppIcon.png")

let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    exit(1)
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// storm sky: deep navy falling to a teal horizon
let sky = CGGradient(colorsSpace: space,
                     colors: [rgb(8, 22, 45), rgb(12, 45, 78), rgb(14, 92, 107)] as CFArray,
                     locations: [0, 0.55, 1])!
ctx.drawLinearGradient(sky,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: 0, y: 0),
                       options: [])

// rain, angled across the upper two thirds
ctx.saveGState()
ctx.setLineWidth(5)
ctx.setStrokeColor(rgb(150, 205, 225, 0.22))
for _ in 0..<70 {
    let x = CGFloat.random(in: -100...size)
    let y = CGFloat.random(in: size * 0.30...size)
    let length = CGFloat.random(in: 40...110)
    ctx.move(to: CGPoint(x: x, y: y))
    ctx.addLine(to: CGPoint(x: x + length * 0.35, y: y - length))
}
ctx.strokePath()
ctx.restoreGState()

// lightning bolt, centred and slightly above the waves
let bolt: [CGPoint] = [
    CGPoint(x: 566, y: 880), CGPoint(x: 372, y: 556), CGPoint(x: 486, y: 556),
    CGPoint(x: 430, y: 330), CGPoint(x: 648, y: 620), CGPoint(x: 524, y: 620),
]
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 60, color: rgb(255, 214, 120, 0.85))
let boltPath = CGMutablePath()
boltPath.addLines(between: bolt)
boltPath.closeSubpath()
ctx.addPath(boltPath)
ctx.setFillColor(rgb(255, 209, 102))
ctx.fillPath()
ctx.restoreGState()

// flood water: three stacked wave bands across the lower third
func wave(yBase: CGFloat, amplitude: CGFloat, phase: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: 0, y: yBase))
    var x: CGFloat = 0
    while x <= size {
        let y = yBase + sin((x / size) * .pi * 4 + phase) * amplitude
        path.addLine(to: CGPoint(x: x, y: y))
        x += 4
    }
    path.addLine(to: CGPoint(x: size, y: 0))
    path.closeSubpath()
    return path
}

ctx.addPath(wave(yBase: 330, amplitude: 26, phase: 0.4))
ctx.setFillColor(rgb(16, 118, 138, 0.95))
ctx.fillPath()

ctx.addPath(wave(yBase: 250, amplitude: 22, phase: 2.1))
ctx.setFillColor(rgb(22, 158, 176, 0.95))
ctx.fillPath()

ctx.addPath(wave(yBase: 170, amplitude: 18, phase: 3.6))
ctx.setFillColor(rgb(45, 200, 210, 0.95))
ctx.fillPath()

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("Wrote \(out.path)")
