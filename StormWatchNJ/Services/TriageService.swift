import CoreGraphics
import Foundation
import UIKit
import Vision

/// The structured result a triage engine returns — the client-side equivalent of
/// the `HazardAnalysisResult` Pydantic model in `backend/main.py`.
struct HazardAnalysis: Equatable {
    var hazardType: HazardType
    var severity: Severity
    var utilityLinesInvolved: Bool
    var roadStatus: RoadStatus
    var suggestedDescription: String
    /// Human-readable name of whatever produced this result, shown in the UI so a
    /// resident always knows the fields were machine-filled.
    var engine: String
    var confidence: Double
    /// Short plain-English lines explaining what the engine actually saw.
    var evidence: [String]
}

protocol TriageEngine {
    var name: String { get }
    func analyze(image: UIImage, imageData: Data, context: TriageContext) async throws -> HazardAnalysis
}

/// Where the report is being filed, used only to phrase the description.
struct TriageContext {
    var municipality: String
}

// MARK: - On-device engine

/// Two independent lines of evidence, combined:
///
/// 1. Apple's Vision scene classifier (`VNClassifyImageRequest`), matched against
///    **exact** identifiers from its 1,303-label taxonomy. Substring matching was
///    tried first and is actively wrong here — "tree" matches `street`, "line"
///    matches `feline`, "car" matches `carrot`.
/// 2. Colour statistics from `ImageSignalExtractor`, because that taxonomy has no
///    label for flooding, a blocked drain or a downed wire.
///
/// This is deliberately a transparent heuristic, not a trained hazard model. It
/// proposes; the resident disposes. For a real multimodal model, point the app at
/// OpenAI through the `analyze-image` server function.
struct OnDeviceTriageEngine: TriageEngine {
    var name: String { "On-device analysis" }

    // Every term below is a verbatim identifier from the Vision taxonomy.
    private static let waterLabels: Set<String> = [
        "water", "water_body", "waterways", "waterfall", "river", "lake", "creek",
        "wetland", "dam", "underwater", "submarine_water", "storm", "thunderstorm"
    ]
    private static let treeLabels: Set<String> = [
        "tree", "oak_tree", "maple_tree", "eucalyptus_tree", "palm_tree", "branch",
        "forest", "foliage", "wood_natural", "shrub", "plant", "decorative_plant", "leaf"
    ]
    private static let wireLabels: Set<String> = [
        "pole", "flagpole", "pylon", "tower", "cableway", "clothesline", "cord", "rope"
    ]
    private static let drainLabels: Set<String> = [
        "manhole", "trash_can", "pipe"
    ]
    /// Not a hazard class — evidence that we are looking at a roadway at all.
    private static let roadLabels: Set<String> = [
        "road", "dirt_road", "road_other", "street", "street_sign", "traffic_light",
        "car", "sidewalk", "bridge", "tunnel", "license_plate", "outdoor"
    ]

    func analyze(image: UIImage, imageData: Data, context: TriageContext) async throws -> HazardAnalysis {
        // Vision's scene classifier is unavailable in the iOS Simulator — its
        // Core ML backend fails with "could not create espresso context". Colour
        // analysis is plain Core Graphics and always works, so a classifier
        // failure degrades the result instead of killing the whole flow.
        let observations = (try? await classify(imageData: imageData)) ?? []
        let sceneClassifierAvailable = !observations.isEmpty
        let signals = ImageSignalExtractor.signals(from: image)

        func visionScore(_ vocabulary: Set<String>) -> Double {
            observations.reduce(0.0) { total, item in
                vocabulary.contains(item.label) ? total + Double(item.confidence) : total
            }
        }

        let roadContext = visionScore(Self.roadLabels)

        // Colour evidence is weighted heavily for flooding because that is exactly
        // where the scene classifier is blind.
        let floodScore = visionScore(Self.waterLabels) * 1.2 + signals.waterCoverage * 1.6
        let treeScore = visionScore(Self.treeLabels) * 1.1 + signals.foliageCoverage * 1.0
        let wireScore = visionScore(Self.wireLabels) * 1.4

        // A blocked drain looks like a *shallow* pool at the kerb, so a mid-range
        // water reading is weak supporting evidence. It is deliberately small and
        // suppressed when the frame is full of vegetation: as a flat constant it
        // outscored a fallen tree whenever the scene classifier was unavailable.
        let kerbPooling = signals.waterCoverage > 0.12
            && signals.waterCoverage < 0.34
            && signals.foliageCoverage < 0.25
        let drainScore = visionScore(Self.drainLabels) * 1.3 + (kerbPooling ? 0.22 : 0)

        let ranked: [(HazardType, Double)] = [
            (.downedWire, wireScore),
            (.downedTree, treeScore),
            (.streetFlooding, floodScore),
            (.cloggedDrain, drainScore)
        ].sorted { $0.1 > $1.1 }

        let best = ranked[0]
        let hazardType: HazardType = best.1 >= 0.30 ? best.0 : .other
        // Normalised so the percentage shown in the UI means something.
        // Without the scene classifier the scores are colour-only, so the same
        // raw number represents weaker evidence and is discounted accordingly.
        let ceiling = sceneClassifierAvailable ? 0.97 : 0.80
        let confidence = min(best.1 / 1.8, ceiling)

        // The safety check the blueprint calls out: wires near a fallen tree or in
        // standing water are flagged even when they are not the top classification.
        let utilityLines = wireScore > 0.25 && (hazardType == .downedWire || hazardType == .downedTree)

        let severity = Self.severity(for: hazardType, signals: signals, confidence: confidence)
        let roadStatus = Self.roadStatus(for: severity, utilityLines: utilityLines)

        var evidence: [String] = []
        if signals.waterCoverage > 0.08 {
            evidence.append("Water-toned surface across \(percent(signals.waterCoverage)) of the lower frame")
        }
        if signals.foliageCoverage > 0.10 {
            evidence.append("Vegetation across \(percent(signals.foliageCoverage)) of the frame")
        }
        if signals.skyDarkness > 0.55 {
            evidence.append("Dark, overcast sky")
        }
        if roadContext > 0.05 {
            evidence.append("Roadway scene detected")
        }
        if sceneClassifierAvailable {
            let sceneLabels = observations.prefix(4).map(\.label).joined(separator: ", ")
            if !sceneLabels.isEmpty {
                evidence.append("Scene labels: \(sceneLabels)")
            }
        } else {
            evidence.append("Scene classifier unavailable here — colour analysis only")
        }
        if evidence.isEmpty {
            evidence.append("No strong hazard signal; please set the fields yourself")
        }

        return HazardAnalysis(
            hazardType: hazardType,
            severity: severity,
            utilityLinesInvolved: utilityLines,
            roadStatus: roadStatus,
            suggestedDescription: Self.describe(hazardType: hazardType,
                                                roadStatus: roadStatus,
                                                utilityLines: utilityLines,
                                                municipality: context.municipality),
            engine: name,
            confidence: confidence,
            evidence: evidence
        )
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func severity(for hazardType: HazardType,
                                 signals: ImageSignals,
                                 confidence: Double) -> Severity {
        switch hazardType {
        case .streetFlooding:
            if signals.waterCoverage > 0.55 { return .impassable }
            return signals.waterCoverage > 0.28 ? .moderate : .low
        case .downedWire:
            return .impassable
        case .downedTree:
            // A canopy filling much of the frame means the trunk is across the road.
            return (confidence > 0.5 || signals.foliageCoverage > 0.35) ? .impassable : .moderate
        case .cloggedDrain:
            return .moderate
        case .other:
            return .low
        }
    }

    private static func roadStatus(for severity: Severity, utilityLines: Bool) -> RoadStatus {
        if utilityLines || severity == .impassable { return .impassable }
        return severity == .moderate ? .oneLaneOpen : .clearToPass
    }

    private func classify(imageData: Data) async throws -> [(label: String, confidence: Float)] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(data: imageData, options: [:])
                do {
                    try handler.perform([request])
                    let results = (request.results ?? [])
                        .sorted { $0.confidence > $1.confidence }
                        .prefix(40)
                        .map { (label: $0.identifier.lowercased(), confidence: $0.confidence) }
                    continuation.resume(returning: Array(results))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func describe(hazardType: HazardType,
                         roadStatus: RoadStatus,
                         utilityLines: Bool,
                         municipality: String) -> String {
        var sentence: String
        switch hazardType {
        case .streetFlooding:
            sentence = "Standing water across the roadway in \(municipality)."
        case .downedTree:
            sentence = "Fallen tree obstructing the roadway in \(municipality)."
        case .downedWire:
            sentence = "Downed utility line reported in \(municipality)."
        case .cloggedDrain:
            sentence = "Storm drain blocked by debris in \(municipality), water pooling at the curb."
        case .other:
            sentence = "Storm-related road obstruction reported in \(municipality)."
        }
        // Severity has its own field and badge, so naming it here just repeats
        // itself — "assessed as impassable; impassable."
        switch roadStatus {
        case .impassable:
            sentence += " The road is impassable."
        case .oneLaneOpen:
            sentence += " One lane is open; pass with care."
        case .clearToPass:
            sentence += " Passable with caution."
        }
        if utilityLines {
            sentence += " Possible energized wires — treat as a live electrical hazard and dispatch the utility."
        }
        return sentence
    }
}

// MARK: - Remote engine

/// Calls the `analyze-image` server function,
/// which runs the photo through an OpenAI vision model with a strict JSON schema.
/// The OpenAI key lives on the server; the app never holds it.
struct RemoteTriageEngine: TriageEngine {
    let name = "OpenAI vision"
    /// The signed-in user's access token; the endpoint refuses anyone else so the
    /// OpenAI key cannot be spent by strangers.
    let token: String

    func analyze(image: UIImage, imageData: Data, context: TriageContext) async throws -> HazardAnalysis {
        let boundary = "stormwatch.\(UUID().uuidString)"

        var request = URLRequest(url: SupabaseConfig.function("analyze-image"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"incident.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TriageError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["detail"] as? String
            throw TriageError.server(http.statusCode, detail ?? "The server returned an error.")
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return HazardAnalysis(
            hazardType: HazardType(rawValue: payload.hazard_type) ?? .other,
            severity: Severity(rawValue: payload.severity) ?? .moderate,
            utilityLinesInvolved: payload.utility_lines_involved,
            roadStatus: RoadStatus(rawValue: payload.road_status) ?? .oneLaneOpen,
            suggestedDescription: payload.suggested_description,
            engine: name,
            confidence: 1.0,
            evidence: ["Analyzed by an OpenAI vision model", "The photo was sent to OpenAI for this analysis"]
        )
    }

    private struct Payload: Decodable {
        let hazard_type: String
        let severity: String
        let utility_lines_involved: Bool
        let road_status: String
        let suggested_description: String
    }

    enum TriageError: LocalizedError {
        case badResponse
        case server(Int, String)

        var errorDescription: String? {
            switch self {
            case .badResponse:
                return "The backend returned an unexpected response."
            case .server(let code, let detail):
                return detail
            }
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}

extension UIImage {
    /// Redraws the image with `.up` orientation.
    ///
    /// `cgImage` ignores `imageOrientation`, so a photo straight from the camera
    /// (normally `.right`) would be analyzed sideways — the sky would land on the
    /// left edge and every colour signal would be measured in the wrong place.
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
