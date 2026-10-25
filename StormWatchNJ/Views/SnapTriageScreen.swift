import AVFoundation
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
    @EnvironmentObject private var account: AccountStore

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
    @State private var showCameraDenied = false
    /// Kept after `reset()` so the Nextdoor offer can compose from it.
    @State private var lastSubmitted: HazardReport?
    /// Street address and town for where the photo was taken, looked up once a
    /// photo is in (for the life-safety banner and the report's town).
    @State private var hazardAddress: String?
    @State private var placeCity: String?
    @State private var nextdoorFailed = false

    private var showsLifeSafetyAlert: Bool {
        image != nil && UtilityHandoff.isLifeSafetyRisk(type: reportType, utilityLines: utilityLines)
    }

    private var municipality: String {
        placeCity ?? NJMunicipalities.nearby(location.coordinate) ?? "New Jersey"
    }

    /// Debug builds accept `-demoScene floodedRoad|downedTree` so a screenshot
    /// pass can exercise the triage flow without tapping. Never set in Release.
    private static var debugScene: DemoPhoto.Scene? {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "demoScene") else { return nil }
        return DemoPhoto.Scene(rawValue: raw)
        #else
        return nil
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let image {
                        photoPreview(image)
                        triageCard
                        draftCard
                        submitButton
                    } else {
                        sourceChooser
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .top, spacing: 0) {
              VStack(spacing: 0) {
                StormHeader(title: "Snap & Triage",
                            subtitle: image == nil ? "Photograph a hazard to begin" : "Check the details, then post") {
                    if image != nil {
                        Button {
                            reset()
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .accessibilityLabel("Start over")
                    }
                }
                // Pinned under the header so it stays in view while the form scrolls.
                if showsLifeSafetyAlert {
                    LifeSafetyBanner(locationText: hazardAddress ?? "\(municipality), NJ")
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
              }
              .animation(.easeOut(duration: 0.25), value: showsLifeSafetyAlert)
            }
            .task(id: image != nil) {
                guard image != nil, hazardAddress == nil else { return }
                let place = await AddressResolver.resolve(latitude: location.coordinate.latitude,
                                                          longitude: location.coordinate.longitude)
                hazardAddress = place?.singleLine
                placeCity = place?.city
            }
            .navigationBarHidden(true)
            .task {
                if image == nil, let scene = Self.debugScene {
                    setImage(DemoPhoto.image(scene))
                }
            }
            .alert("Report submitted", isPresented: $showSubmitted) {
                if settings.offerNextdoorShare, let report = lastSubmitted {
                    Button("Share to Nextdoor") {
                        NextdoorShare.open(report) { opened in
                            nextdoorFailed = !opened
                        }
                    }
                }
                Button("Done", role: .cancel) {}
            } message: {
                Text(settings.offerNextdoorShare
                     ? "Your report is on the map and in the public works queue. Want to tell your neighborhood too? Nextdoor will open with the post written for you — you review it and tap Post there."
                     : "Your report is on the map and in the public works queue.")
            }
            .alert("Couldn't open Nextdoor", isPresented: $nextdoorFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your report is still saved in StormWatch NJ. You can share it later from the report's detail screen.")
            }
            .alert("Camera access is off", isPresented: $showCameraDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("StormWatch NJ needs the camera to photograph a hazard. You can still choose an existing photo from your library.")
            }
            .fullScreenCover(isPresented: $showCamera) {
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
                        setImage(loaded.normalizedUp())
                    }
                }
            }
        }
    }

    // MARK: - Photo sources

    private var sourceChooser: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    StormBackdrop(animated: false, waterLevel: 0.34)
                    VStack(spacing: 10) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 46, weight: .medium))
                            .foregroundStyle(.white)
                            .shadow(color: Theme.brightTeal.opacity(0.8), radius: 12)
                        Text("Report a storm hazard")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.bottom, 26)
                }
                .frame(height: 170)
                .clipped()

                HStack(spacing: 0) {
                    step("camera.fill", "Snap")
                    stepArrow
                    step("sparkles", "AI fills it in")
                    stepArrow
                    step("checkmark.seal.fill", "You confirm")
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 8)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 5)

            if CameraPicker.isAvailable {
                Button {
                    requestCameraThenPresent()
                } label: {
                    Label("Take photo", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.teal)
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 10) {
                Label(CameraPicker.isAvailable ? "Try it with a sample scene" : "No camera in the simulator",
                      systemImage: "wand.and.stars")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(DemoPhoto.Scene.allCases) { scene in
                        Button {
                            setImage(DemoPhoto.image(scene))
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: scene.symbol).font(.title3)
                                Text(scene.title)
                                    .font(.caption2.weight(.medium))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(LinearGradient(colors: (scene == .floodedRoad
                                                                ? HazardType.streetFlooding : HazardType.downedTree).gradient,
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Illustrations, not photographs — they exist so the triage engine can be tested without a camera roll.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .stormCard()
        }
    }

    private func step(_ symbol: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.teal)
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var stepArrow: some View {
        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
    }

    private func photoPreview(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(height: 210)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Button {
                    reset()
                } label: {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(10)
            }
    }

    // MARK: - Triage result

    private var triageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if isAnalyzing {
                    ProgressView().frame(width: 58, height: 58)
                } else if let analysis {
                    if let confidence = analysis.confidence {
                        ConfidenceRing(value: confidence, tint: analysis.severity.tint)
                    } else {
                        HazardGlyph(type: analysis.hazardType, size: 58)
                    }
                } else {
                    Image(systemName: "sparkles")
                        .font(.title)
                        .foregroundStyle(Theme.teal)
                        .frame(width: 58, height: 58)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(isAnalyzing ? "Analyzing scene…" : (analysis?.hazardType.label ?? "Not analyzed yet"))
                        .font(.headline)
                    Text(analysis?.engine ?? "OpenAI vision")
                        .font(.caption)
                        .foregroundStyle(Theme.teal)
                }
                Spacer(minLength: 0)
            }

            if let analysis, !analysis.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What the engine saw")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(analysis.evidence, id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill").font(.system(size: 4)).padding(.top, 6)
                            Text(line).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Text("These fields were machine-filled. Check them before you post.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button {
                Task { await runTriage() }
            } label: {
                Label(analysis == nil ? "Run triage" : "Re-run triage", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .disabled(isAnalyzing || image == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .stormCard()
    }

    // MARK: - Editable draft

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Confirm the report")
                .font(.headline)

            labelled("Hazard") {
                Picker("Hazard", selection: $reportType) {
                    ForEach(HazardType.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }

            labelled("Severity") {
                Picker("Severity", selection: $severity) {
                    ForEach(Severity.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            labelled("Road") {
                Picker("Road", selection: $roadStatus) {
                    ForEach(RoadStatus.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }

            Toggle(isOn: $utilityLines) {
                Label("Utility lines involved", systemImage: "bolt.trianglebadge.exclamationmark.fill")
                    .font(.subheadline)
            }
            .tint(.red)

            VStack(alignment: .leading, spacing: 6) {
                Text("Description").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextEditor(text: $details)
                    .frame(minHeight: 92)
                    .padding(6)
                    .background(Color(.tertiarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse").font(.caption2)
                Text(String(format: "%@ · %.4f, %.4f", municipality,
                            location.coordinate.latitude, location.coordinate.longitude))
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .stormCard()
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private var submitButton: some View {
        VStack(spacing: 8) {
            Button {
                submit()
            } label: {
                Label("Post report", systemImage: "paperplane.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.teal)
            .disabled(details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Text("The photo is sent to OpenAI for analysis and is never published. Only the fields above go on the map.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    /// Checks camera permission before presenting the picker. Without this a
    /// denied camera shows the resident an opaque black sheet instead of a reason.
    private func requestCameraThenPresent() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { showCamera = true } else { showCameraDenied = true }
                }
            }
        case .denied, .restricted:
            showCameraDenied = true
        @unknown default:
            showCameraDenied = true
        }
    }

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

        let engine = settings.triageEngine(token: await account.validToken())
        let context = TriageContext(municipality: municipality)
        do {
            apply(try await engine.analyze(image: image, imageData: data, context: context))
        } catch {
            // A backend that is unreachable should not dead-end the resident, so
            // fall back to the on-device engine and say so.
            errorMessage = "\(error.localizedDescription) Used on-device analysis instead."
            if let fallback = try? await OnDeviceTriageEngine().analyze(image: image, imageData: data, context: context) {
                apply(fallback)
            }
        }
    }

    private func apply(_ result: HazardAnalysis) {
        withAnimation(.easeOut(duration: 0.3)) {
            analysis = result
            reportType = result.hazardType
            severity = result.severity
            roadStatus = result.roadStatus
            utilityLines = result.utilityLinesInvolved
            details = result.suggestedDescription
        }
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
        lastSubmitted = report
        // Address lookup and the municipal relay run after the report is saved,
        // so posting is instant and still works with no signal.
        Task { await ReportFollowUp.run(for: report, store: store, settings: settings, account: account) }
        reset()
        showSubmitted = true
    }

    private func reset() {
        image = nil
        analysis = nil
        photoItem = nil
        errorMessage = nil
        hazardAddress = nil
        placeCity = nil
        details = ""
        utilityLines = false
        severity = .moderate
        roadStatus = .oneLaneOpen
        reportType = .streetFlooding
    }
}
