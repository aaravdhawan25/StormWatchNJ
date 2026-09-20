import CoreLocation
import Foundation
import PhotosUI
import SwiftUI
import UIKit

/// The "Snap & Triage" flow: photo in, machine-filled draft out, resident confirms.
///
/// The human-in-the-loop step is deliberate — every field the engine fills stays
/// editable, and nothing is published until the resident taps submit.
struct SnapTriageScreen: View {
    @EnvironmentObject private var store: HazardStore
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var settings: AppSettings

    @State private var image: UIImage?
    @State private var analysis: HazardAnalysis?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?

    // Editable draft fields.
    @State private var reportType: HazardType = .streetFlooding
    @State private var severity: Severity = .moderate
    @State private var roadStatus: RoadStatus = .oneLaneOpen
    @State private var utilityLines = false
    @State private var details = ""

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showSubmitted = false

    private var municipality: String {
        NJMunicipalities.nearest(to: location.coordinate).name
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                if image != nil {
                    triageSection
                    draftSection
                    submitSection
                }
            }
            .navigationTitle("Snap & Triage")
            .alert("Report submitted", isPresented: $showSubmitted) {
                Button("Done", role: .cancel) {}
            } message: {
                Text("Your report is on the map and in the DPW export queue.")
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { captured in
                    showCamera = false
                    if let captured { setImage(captured) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let loaded = UIImage(data: data) {
                        setImage(loaded)
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var photoSection: some View {
        Section {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .listRowInsets(EdgeInsets())
            }

            if CameraPicker.isAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label("Take photo", systemImage: "camera.fill")
                }
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
            }

            Button {
                setImage(DemoPhoto.floodedStreet())
            } label: {
                Label("Use synthetic demo photo", systemImage: "wand.and.stars")
            }

            if image != nil {
                Button(role: .destructive) {
                    reset()
                } label: {
                    Label("Start over", systemImage: "arrow.counterclockwise")
                }
            }
        } header: {
            Text("Incident photo")
        } footer: {
            Text(CameraPicker.isAvailable
                 ? "The photo stays on this device; only the fields below are published."
                 : "No camera in the simulator — use the library or the synthetic demo photo.")
        }
    }

    private var triageSection: some View {
        Section("AI triage") {
            if isAnalyzing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Analyzing scene…").foregroundStyle(.secondary)
                }
            } else if let analysis {
                VStack(alignment: .leading, spacing: 8) {
                    Label(analysis.engine, systemImage: "cpu")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)

                    Text("Confidence \(Int(analysis.confidence * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !analysis.topLabels.isEmpty {
                        Text("Detected: " + analysis.topLabels.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text("These fields were machine-filled. Check them before you post.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                Task { await runTriage() }
            } label: {
                Label(analysis == nil ? "Run triage" : "Re-run triage", systemImage: "sparkles")
            }
            .disabled(isAnalyzing || image == nil)
        }
    }

    private var draftSection: some View {
        Section("Confirm the report") {
            Picker("Hazard", selection: $reportType) {
                ForEach(HazardType.allCases) { Text($0.label).tag($0) }
            }

            Picker("Severity", selection: $severity) {
                ForEach(Severity.allCases) { Text($0.label).tag($0) }
            }

            Picker("Road", selection: $roadStatus) {
                ForEach(RoadStatus.allCases) { Text($0.label).tag($0) }
            }

            Toggle("Utility lines involved", isOn: $utilityLines)

            VStack(alignment: .leading, spacing: 6) {
                Text("Description").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $details)
                    .frame(minHeight: 96)
            }

            LabeledContent("Location") {
                Text(String(format: "%@ · %.4f, %.4f", municipality,
                            location.coordinate.latitude, location.coordinate.longitude))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var submitSection: some View {
        Section {
            Button {
                submit()
            } label: {
                Label("Post report", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } footer: {
            if utilityLines {
                Text("Downed wires are treated as energized. Stay back and call 911 and your utility — this report does not replace that call.")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Actions

    private func setImage(_ newImage: UIImage) {
        image = newImage
        analysis = nil
        errorMessage = nil
        Task { await runTriage() }
    }

    private func runTriage() async {
        guard let image, let data = image.jpegData(compressionQuality: 0.85) else { return }
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }

        let engine = settings.triageEngine
        let box = CLLocationCoordinate2DBox(latitude: location.coordinate.latitude,
                                            longitude: location.coordinate.longitude,
                                            municipality: municipality)
        do {
            let result = try await engine.analyze(imageData: data, near: box)
            apply(result)
        } catch {
            // A backend that is unreachable should not dead-end the resident, so
            // fall back to the on-device engine and say so.
            errorMessage = "\(engine.name) failed: \(error.localizedDescription) Falling back to on-device triage."
            if let fallback = try? await OnDeviceTriageEngine().analyze(imageData: data, near: box) {
                apply(fallback)
            }
        }
    }

    private func apply(_ result: HazardAnalysis) {
        analysis = result
        reportType = result.hazardType
        severity = result.severity
        roadStatus = result.roadStatus
        utilityLines = result.utilityLinesInvolved
        details = result.suggestedDescription
    }

    private func submit() {
        let report = HazardReport(reportType: reportType,
                                  severity: severity,
                                  roadStatus: roadStatus,
                                  utilityLinesInvolved: utilityLines,
                                  details: details.trimmingCharacters(in: .whitespacesAndNewlines),
                                  photoFilename: nil,
                                  latitude: location.coordinate.latitude,
                                  longitude: location.coordinate.longitude,
                                  municipality: municipality)
        store.add(report, photo: image)
        reset()
        showSubmitted = true
    }

    private func reset() {
        image = nil
        analysis = nil
        photoItem = nil
        errorMessage = nil
        details = ""
        utilityLines = false
        severity = .moderate
        roadStatus = .oneLaneOpen
        reportType = .streetFlooding
    }
}
