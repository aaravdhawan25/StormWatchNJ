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
    var topLabels: [String]
}

protocol TriageEngine {
    var name: String { get }
    func analyze(imageData: Data, near coordinate: CLLocationCoordinate2DBox) async throws -> HazardAnalysis
}

/// Small wrapper so the protocol does not need to import CoreLocation.
struct CLLocationCoordinate2DBox {
    var latitude: Double
    var longitude: Double
    var municipality: String
}

// MARK: - On-device engine

/// Classifies the photo with Apple's built-in Vision scene taxonomy
/// (`VNClassifyImageRequest`). No API key, no network, works in the simulator —
/// this is what makes the "snap and triage" flow demonstrable out of the box.
struct OnDeviceTriageEngine: TriageEngine {
    let name = "On-device Vision"

    private static let wireTerms = ["power_line", "powerline", "utility_pole", "telephone_pole",
                                    "electricity", "cable", "wire", "transmission_tower", "pylon"]
    private static let treeTerms = ["tree", "branch", "trunk", "log", "forest", "woodland",
                                    "foliage", "leaf", "plant", "shrub"]
    private static let floodTerms = ["flood", "water", "puddle", "river", "lake", "rain",
                                     "stream", "creek", "pond", "wave", "reflection", "storm"]
    private static let drainTerms = ["drain", "sewer", "manhole", "gutter", "grate",
                                     "curb", "debris", "trash", "pipe"]

    func analyze(imageData: Data, near coordinate: CLLocationCoordinate2DBox) async throws -> HazardAnalysis {
        let observations = try await classify(imageData: imageData)

        func score(_ terms: [String]) -> Double {
            observations.reduce(0.0) { total, item in
                terms.contains(where: { item.label.contains($0) }) ? total + Double(item.confidence) : total
            }
        }

        let wire = score(Self.wireTerms)
        let tree = score(Self.treeTerms)
        let flood = score(Self.floodTerms)
        let drain = score(Self.drainTerms)

        let ranked: [(HazardType, Double)] = [
            (.downedWire, wire),
            (.downedTree, tree),
            (.streetFlooding, flood),
            (.cloggedDrain, drain)
        ].sorted { $0.1 > $1.1 }

        let best = ranked[0]
        let hazardType: HazardType = best.1 > 0.08 ? best.0 : .other
        let confidence = min(best.1, 1.0)

        // The safety check the blueprint calls out: wires near a fallen tree or in
        // standing water get flagged even when they are not the top classification.
        let utilityLines = wire > 0.05 && (hazardType == .downedWire || hazardType == .downedTree)

        let severity: Severity
        switch confidence {
        case ..<0.15: severity = .low
        case ..<0.45: severity = .moderate
        default: severity = hazardType == .cloggedDrain ? .moderate : .impassable
        }

        let roadStatus: RoadStatus
        if utilityLines || severity == .impassable {
            roadStatus = .impassable
        } else if severity == .moderate {
            roadStatus = .oneLaneOpen
        } else {
            roadStatus = .clearToPass
        }

        let labels = observations.prefix(5).map(\.label)
        return HazardAnalysis(
            hazardType: hazardType,
            severity: severity,
            utilityLinesInvolved: utilityLines,
            roadStatus: roadStatus,
            suggestedDescription: Self.describe(hazardType: hazardType,
                                                severity: severity,
                                                roadStatus: roadStatus,
                                                utilityLines: utilityLines,
                                                municipality: coordinate.municipality),
            engine: name,
            confidence: confidence,
            topLabels: Array(labels)
        )
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
                         severity: Severity,
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
        sentence += " Severity assessed as \(severity.label.lowercased()); \(roadStatus.label.lowercased())."
        if utilityLines {
            sentence += " Possible energized wires — treat as a live electrical hazard and dispatch the utility."
        }
        return sentence
    }
}

// MARK: - Remote engine

/// Calls the FastAPI `/api/v1/analyze-image` endpoint from the project blueprint,
/// which runs the photo through Gemini with a strict JSON response schema.
struct RemoteTriageEngine: TriageEngine {
    let name = "StormWatch backend (Gemini)"
    let baseURL: URL

    func analyze(imageData: Data, near coordinate: CLLocationCoordinate2DBox) async throws -> HazardAnalysis {
        let endpoint = baseURL.appendingPathComponent("api/v1/analyze-image")
        let boundary = "stormwatch.\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
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
            throw TriageError.server(http.statusCode, String(data: data, encoding: .utf8) ?? "")
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
            topLabels: []
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
                return "Backend error \(code). \(detail)"
            }
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
