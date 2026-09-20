import CoreGraphics
import Foundation
import UIKit

/// Cheap colour/texture measurements taken from a downsampled copy of the photo.
///
/// Apple's scene classifier has no "flood", "puddle" or "downed wire" label, so on
/// its own it cannot tell standing water from a normal street. These signals give
/// the triage engine a second, independent line of evidence, and they are shown to
/// the resident so the reasoning is inspectable rather than a black box.
struct ImageSignals: Equatable {
    /// Weighted fraction of the lower frame that reads as water. Blue-tinted and
    /// silty-brown pixels count fully; flat neutral grey counts only partially,
    /// because dry asphalt is grey too and would otherwise read as a flood.
    var waterCoverage: Double
    /// Fraction of the frame that reads as vegetation.
    var foliageCoverage: Double
    /// 0 = bright clear sky, 1 = dark overcast. Storm photos sit high.
    var skyDarkness: Double
    /// Mean saturation over the whole frame; wet, overcast scenes are washed out.
    var meanSaturation: Double

    static let neutral = ImageSignals(waterCoverage: 0, foliageCoverage: 0,
                                      skyDarkness: 0, meanSaturation: 0)
}

enum ImageSignalExtractor {
    /// Side length of the working copy. 64x64 is enough for colour statistics and
    /// keeps the whole pass well under a millisecond.
    private static let grid = 64

    static func signals(from image: UIImage) -> ImageSignals {
        guard let pixels = downsample(image) else { return .neutral }

        var waterWeightTotal = 0.0
        var lowerCount = 0
        var foliageHits = 0
        var saturationTotal = 0.0
        var skyLuminanceTotal = 0.0
        var skyCount = 0

        for y in 0..<grid {
            for x in 0..<grid {
                let index = (y * grid + x) * 4
                let r = Double(pixels[index]) / 255
                let g = Double(pixels[index + 1]) / 255
                let b = Double(pixels[index + 2]) / 255
                let (hue, saturation, brightness) = hsb(r: r, g: g, b: b)

                saturationTotal += saturation

                // Top quarter of the frame is treated as sky.
                if y < grid / 4 {
                    skyLuminanceTotal += 0.299 * r + 0.587 * g + 0.114 * b
                    skyCount += 1
                }

                if isFoliage(hue: hue, saturation: saturation, brightness: brightness) {
                    foliageHits += 1
                }

                // Water is only meaningful below the horizon.
                if y >= grid * 2 / 5 {
                    lowerCount += 1
                    waterWeightTotal += waterWeight(hue: hue, saturation: saturation, brightness: brightness)
                }
            }
        }

        let total = Double(grid * grid)
        return ImageSignals(
            waterCoverage: lowerCount > 0 ? waterWeightTotal / Double(lowerCount) : 0,
            foliageCoverage: Double(foliageHits) / total,
            skyDarkness: skyCount > 0 ? 1 - (skyLuminanceTotal / Double(skyCount)) : 0,
            meanSaturation: saturationTotal / total
        )
    }

    /// How strongly one pixel reads as standing water.
    ///
    /// Measured on rendered test scenes: a flooded roadway scores ~0.85 and a dry
    /// asphalt road ~0.14, which is the separation the hazard scoring relies on.
    private static func waterWeight(hue: Double, saturation: Double, brightness: Double) -> Double {
        guard brightness > 0.08, brightness < 0.82 else { return 0 }
        // Blue-tinted standing water.
        if saturation >= 0.06, saturation < 0.42, hue >= 170, hue <= 260 { return 1 }
        // Silty brown floodwater.
        if saturation >= 0.12, saturation < 0.55, hue >= 15, hue <= 50, brightness < 0.62 { return 1 }
        // Flat neutral grey: could be water, could be dry asphalt. Count it, but weakly.
        if saturation < 0.06 { return 0.35 }
        return 0
    }

    private static func isFoliage(hue: Double, saturation: Double, brightness: Double) -> Bool {
        hue >= 60 && hue <= 165 && saturation > 0.18 && brightness > 0.06 && brightness < 0.85
    }

    private static func hsb(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let maxValue = max(r, g, b)
        let minValue = min(r, g, b)
        let delta = maxValue - minValue

        var hue = 0.0
        if delta > 0.0001 {
            if maxValue == r {
                hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxValue == g {
                hue = 60 * (((b - r) / delta) + 2)
            } else {
                hue = 60 * (((r - g) / delta) + 4)
            }
        }
        if hue < 0 { hue += 360 }
        let saturation = maxValue <= 0.0001 ? 0 : delta / maxValue
        return (hue, saturation, maxValue)
    }

    private static func downsample(_ image: UIImage) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }
        var buffer = [UInt8](repeating: 0, count: grid * grid * 4)
        let space = CGColorSpaceCreateDeviceRGB()

        let drawn: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: grid, height: grid,
                                          bitsPerComponent: 8,
                                          bytesPerRow: grid * 4,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: grid, height: grid))
            return true
        }
        return drawn ? buffer : nil
    }
}
