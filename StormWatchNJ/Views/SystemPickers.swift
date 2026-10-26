import CoreGraphics
import Foundation
import SwiftUI
import UIKit

// `UIImagePickerController` wrapper for live camera capture
struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    // called with the captured image, or `nil` if the user cancelled
    var onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let picked = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            // fix orientation once here
            onFinish(picked?.normalizedUp())
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

// `UIActivityViewController` wrapper used to hand DPW exports to Files, Mail, AirDrop
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Demo photos

// procedurally drawn storm scenes
enum DemoPhoto {
    enum Scene: String, CaseIterable, Identifiable {
        case floodedRoad
        case downedTree

        var id: String { rawValue }

        var title: String {
            switch self {
            case .floodedRoad: return "Flooded road"
            case .downedTree: return "Tree across road"
            }
        }

        var symbol: String {
            switch self {
            case .floodedRoad: return "water.waves"
            case .downedTree: return "leaf.fill"
            }
        }
    }

    static func image(_ scene: Scene, size: CGSize = CGSize(width: 1024, height: 768)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            // UIGraphicsImageRenderer hands us a flipped (top-left origin) context
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            switch scene {
            case .floodedRoad: drawFloodedRoad(cg, size.width, size.height)
            case .downedTree: drawDownedTree(cg, size.width, size.height)
            }
        }
    }

    // MARK: Scene pieces

    private static let space = CGColorSpaceCreateDeviceRGB()

    private static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func drawSky(_ cg: CGContext, _ w: CGFloat, _ h: CGFloat, _ horizon: CGFloat) {
        let gradient = CGGradient(colorsSpace: space,
                                  colors: [rgb(96, 104, 116), rgb(139, 147, 158), rgb(178, 184, 191)] as CFArray,
                                  locations: [0, 0.55, 1])!
        cg.saveGState()
        cg.clip(to: CGRect(x: 0, y: horizon, width: w, height: h - horizon))
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: horizon), options: [])
        for _ in 0..<16 {
            let center = CGPoint(x: CGFloat.random(in: 0...w), y: CGFloat.random(in: horizon...h))
            let cloud = CGGradient(colorsSpace: space,
                                   colors: [rgb(210, 214, 220, 0.5), rgb(210, 214, 220, 0)] as CFArray,
                                   locations: [0, 1])!
            cg.drawRadialGradient(cloud, startCenter: center, startRadius: 0,
                                  endCenter: center, endRadius: CGFloat.random(in: 90...260), options: [])
        }
        cg.restoreGState()
    }

    private static func drawTreeline(_ cg: CGContext, _ w: CGFloat, _ h: CGFloat, _ horizon: CGFloat) {
        for index in 0..<40 {
            let x = CGFloat(index) * w / 38 + CGFloat.random(in: -14...14)
            let treeHeight = CGFloat.random(in: h * 0.05...h * 0.13)
            let treeWidth = CGFloat.random(in: 60...130)
            let shade = Double.random(in: 0...1)
            cg.setFillColor(rgb(28 + shade * 26, 48 + shade * 34, 30 + shade * 22))
            cg.fillEllipse(in: CGRect(x: x - treeWidth / 2, y: horizon - treeHeight * 0.25,
                                      width: treeWidth, height: treeHeight * 1.7))
        }
    }

    private static func drawGrain(_ cg: CGContext, _ w: CGFloat, _ h: CGFloat) {
        for _ in 0..<26_000 {
            cg.setFillColor(CGColor(gray: Double.random(in: 0...1), alpha: Double.random(in: 0.02...0.09)))
            cg.fill(CGRect(x: CGFloat.random(in: 0...w), y: CGFloat.random(in: 0...h), width: 2, height: 2))
        }
    }

    private static func drawFloodedRoad(_ cg: CGContext, _ w: CGFloat, _ h: CGFloat) {
        let horizon = h * 0.52
        drawSky(cg, w, h, horizon)
        drawTreeline(cg, w, h, horizon)

        let water = CGGradient(colorsSpace: space,
                               colors: [rgb(58, 64, 70), rgb(78, 90, 99), rgb(116, 128, 136)] as CFArray,
                               locations: [0, 0.6, 1])!
        cg.saveGState()
        cg.clip(to: CGRect(x: 0, y: 0, width: w, height: horizon))
        cg.drawLinearGradient(water, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: horizon), options: [])

        // reflection streaks, longer and softer closer to the camera
        for _ in 0..<220 {
            let y = CGFloat.random(in: 0...horizon)
            let depth = 1 - (y / horizon)
            cg.setFillColor(rgb(198, 208, 216, Double.random(in: 0.04...0.20)))
            cg.fill(CGRect(x: CGFloat.random(in: -100...w), y: y,
                           width: CGFloat.random(in: 40...420) * (0.35 + depth),
                           height: CGFloat.random(in: 2...7)))
        }

        // centre line disappearing under the water
        var y = horizon * 0.06
        while y < horizon * 0.92 {
            let depth = 1 - (y / horizon)
            let segment = 26 * (0.25 + depth)
            cg.setFillColor(rgb(206, 178, 74, 0.30 * Double(depth) + 0.05))
            cg.fill(CGRect(x: w * 0.5 - 9 * depth, y: y, width: 18 * depth, height: segment))
            y += segment * 2.3
        }
        cg.restoreGState()

        // utility pole with a drooping span
        cg.setFillColor(rgb(74, 62, 52))
        cg.fill(CGRect(x: w * 0.76, y: horizon - h * 0.02, width: 13, height: h * 0.36))
        cg.fill(CGRect(x: w * 0.72, y: horizon + h * 0.26, width: 90, height: 9))
        cg.setStrokeColor(rgb(26, 26, 28, 0.85))
        cg.setLineWidth(4)
        cg.move(to: CGPoint(x: w * 0.765, y: horizon + h * 0.28))
        cg.addCurve(to: CGPoint(x: w * 0.12, y: horizon - h * 0.06),
                    control1: CGPoint(x: w * 0.6, y: horizon + h * 0.02),
                    control2: CGPoint(x: w * 0.33, y: horizon - h * 0.10))
        cg.strokePath()

        drawGrain(cg, w, h)
    }

    private static func drawDownedTree(_ cg: CGContext, _ w: CGFloat, _ h: CGFloat) {
        let horizon = h * 0.55
        drawSky(cg, w, h, horizon)
        drawTreeline(cg, w, h, horizon)

        let road = CGGradient(colorsSpace: space,
                              colors: [rgb(64, 64, 68), rgb(92, 92, 96), rgb(120, 120, 124)] as CFArray,
                              locations: [0, 0.6, 1])!
        cg.saveGState()
        cg.clip(to: CGRect(x: 0, y: 0, width: w, height: horizon))
        cg.drawLinearGradient(road, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: horizon), options: [])
        cg.restoreGState()

        // trunk lying across both lanes
        cg.saveGState()
        cg.translateBy(x: w * 0.5, y: horizon * 0.55)
        cg.rotate(by: -0.16)
        cg.setFillColor(rgb(84, 64, 46))
        cg.fill(CGRect(x: -w * 0.55, y: -26, width: w * 1.1, height: 52))
        cg.restoreGState()

        // canopy scattered around the trunk
        for _ in 0..<130 {
            let shade = Double.random(in: 0...1)
            cg.setFillColor(rgb(30 + shade * 40, 62 + shade * 48, 34 + shade * 30, 0.95))
            cg.fillEllipse(in: CGRect(x: CGFloat.random(in: w * 0.05...w * 0.95),
                                      y: horizon * 0.55 + CGFloat.random(in: -130...130),
                                      width: CGFloat.random(in: 40...120),
                                      height: CGFloat.random(in: 30...90)))
        }

        drawGrain(cg, w, h)
    }
}
