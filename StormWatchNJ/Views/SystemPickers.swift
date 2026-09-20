import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// `UIImagePickerController` wrapper for live camera capture.
/// The simulator has no camera, so callers gate this on `isAvailable`.
struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Called with the captured image, or `nil` if the user cancelled. The caller
    /// owns dismissal — reading `@Environment(\.dismiss)` from the coordinator's
    /// copy of this struct is not reliable.
    var onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
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
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

/// `UIActivityViewController` wrapper used to hand DPW exports to Files, Mail, AirDrop.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Draws a synthetic storm photo so the triage flow can be demonstrated in a
/// simulator with an empty photo library. Obviously synthetic — it exists to
/// exercise the pipeline, not to stand in for a real incident photo.
enum DemoPhoto {
    static func floodedStreet() -> UIImage {
        let size = CGSize(width: 1024, height: 768)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext

            // Overcast sky.
            cg.setFillColor(UIColor(red: 0.42, green: 0.45, blue: 0.5, alpha: 1).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.45))

            // Tree line along the horizon.
            cg.setFillColor(UIColor(red: 0.13, green: 0.22, blue: 0.15, alpha: 1).cgColor)
            for index in 0..<14 {
                let x = CGFloat(index) * size.width / 14
                let height = CGFloat.random(in: 70...150)
                cg.fillEllipse(in: CGRect(x: x - 20, y: size.height * 0.45 - height,
                                          width: 110, height: height + 40))
            }

            // Standing water covering the roadway.
            cg.setFillColor(UIColor(red: 0.29, green: 0.37, blue: 0.44, alpha: 1).cgColor)
            cg.fill(CGRect(x: 0, y: size.height * 0.45, width: size.width, height: size.height * 0.55))

            // Reflections on the water surface.
            cg.setFillColor(UIColor(white: 1, alpha: 0.12).cgColor)
            for _ in 0..<40 {
                let y = CGFloat.random(in: size.height * 0.5...size.height)
                let width = CGFloat.random(in: 60...260)
                cg.fill(CGRect(x: CGFloat.random(in: 0...size.width), y: y, width: width, height: 3))
            }

            // Partly submerged utility pole and wire.
            cg.setFillColor(UIColor(red: 0.28, green: 0.21, blue: 0.16, alpha: 1).cgColor)
            cg.fill(CGRect(x: size.width * 0.72, y: size.height * 0.12, width: 16, height: size.height * 0.6))
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.8).cgColor)
            cg.setLineWidth(4)
            cg.move(to: CGPoint(x: size.width * 0.73, y: size.height * 0.16))
            cg.addCurve(to: CGPoint(x: size.width * 0.2, y: size.height * 0.52),
                        control1: CGPoint(x: size.width * 0.6, y: size.height * 0.45),
                        control2: CGPoint(x: size.width * 0.4, y: size.height * 0.58))
            cg.strokePath()

            let label = "SYNTHETIC DEMO IMAGE"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 34),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            label.draw(at: CGPoint(x: 28, y: size.height - 64), withAttributes: attributes)
        }
    }
}
