import Foundation
import MapKit
import SwiftUI

struct HazardDetailView: View {
    let report: HazardReport

    @EnvironmentObject private var store: HazardStore
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var account: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var nextdoorFailed = false
    @State private var relayMessage: String?
    @State private var isForwarding = false
    @State private var isActing = false
    @State private var actionError: String?

    private var isTownship: Bool { account.account?.isTownship == true }
    private var canRemoveShared: Bool { current.isMine == true || isTownship }

    private var showsLifeSafetyAlert: Bool {
        current.status != .resolved
            && UtilityHandoff.isLifeSafetyRisk(type: current.reportType, utilityLines: current.utilityLinesInvolved)
    }

    /// Read back from the store so upvotes and status changes show immediately.
    private var current: HazardReport {
        store.reports.first(where: { $0.id == report.id }) ?? report
    }

    var body: some View {
        List {
            if showsLifeSafetyAlert {
                Section {
                    LifeSafetyBanner(locationText: current.address ?? "\(current.municipality), NJ")
                        .listRowInsets(EdgeInsets())
                }
            }

            if let photo = store.photo(for: current) {
                Section {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .clipped()
                        .listRowInsets(EdgeInsets())
                }
            } else {
                Section {
                    ZStack {
                        LinearGradient(colors: current.reportType.gradient,
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        WaveShape(phase: 1.0, amplitude: 10, cycles: 1.2)
                            .fill(.white.opacity(0.12))
                            .frame(height: 60)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        Image(systemName: current.reportType.symbolName)
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    }
                    .frame(height: 140)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        HazardGlyph(type: current.reportType, size: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.reportType.label).font(.headline)
                            Text(current.municipality).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        SeverityBadge(severity: current.severity)
                    }

                    Text(current.details).font(.subheadline)

                }
                .padding(.vertical, 4)
            }

            Section("Details") {
                LabeledContent("Road", value: current.roadStatus.label)
                LabeledContent("Status", value: current.status.label)
                LabeledContent("Municipality", value: current.municipality)
                if let address = current.address {
                    LabeledContent("Address", value: address)
                }
                LabeledContent("Distance",
                               value: String(format: "%.1f mi away",
                                             store.distanceMiles(to: current, from: location.coordinate)))
                LabeledContent("Reported", value: current.createdAt.shortRelative)
                LabeledContent("Confirmations", value: "\(current.upvotes)")
            }

            Section {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: current.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))) {
                    Annotation(current.reportType.label, coordinate: current.coordinate) {
                        HazardPin(report: current)
                    }
                }
                .frame(height: 180)
                .listRowInsets(EdgeInsets())
                .allowsHitTesting(false)
            }

            Section {
                Button {
                    NextdoorShare.open(current) { opened in
                        nextdoorFailed = !opened
                    }
                } label: {
                    Label("Share to Nextdoor", systemImage: "person.2.fill")
                }
            } footer: {
                Text("Opens Nextdoor's post composer with the details filled in. You review it and post there — nothing is sent automatically, and the photo stays on this device.")
            }

            publicWorksSection

            if showsLifeSafetyAlert {
                Section {
                    Link(destination: UtilityHandoff.psegOutagePageURL) {
                        Label("PSE&G outage & downed wire page", systemImage: "safari")
                    }
                    Link(destination: UtilityHandoff.psegOutageTextURL) {
                        Label("My own power is out — text OUT to PSE&G", systemImage: "message.fill")
                    }
                } header: {
                    Text("Also")
                } footer: {
                    Text("Texting OUT reports an outage at the address on your own PSE&G account, and only from a phone enrolled by texting REG to 47734. It does not report this wire — call for that.")
                }
            }

            Section("Still there?") {
                Button {
                    store.upvote(current)
                } label: {
                    Label("Confirm this hazard", systemImage: "hand.thumbsup.fill")
                }

                // Crew status is a township's call once a report is shared; a
                // report that only exists on this device is this device's to edit.
                if !current.isShared {
                    Picker("Crew status", selection: Binding(
                        get: { current.status },
                        set: { store.setStatus($0, for: current) }
                    )) {
                        ForEach(ReportStatus.allCases) { Text($0.label).tag($0) }
                    }
                } else if isTownship {
                    Picker("Crew status", selection: Binding(
                        get: { current.status },
                        set: { status in act { try await HazardSync.setStatus(status, for: current, store: store, account: account) } }
                    )) {
                        ForEach(ReportStatus.allCases) { Text($0.label).tag($0) }
                    }
                    .disabled(isActing)
                }
            }

            removalSection
        }
        .navigationTitle("Hazard")
        .navigationBarTitleDisplayMode(.inline)
        .alert("That didn't work", isPresented: Binding(
            get: { actionError != nil }, set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .alert("Couldn't reach the relay", isPresented: Binding(
            get: { relayMessage != nil }, set: { if !$0 { relayMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text((relayMessage ?? "") + " The report is still saved on this device.")
        }
        .alert("Couldn't open Nextdoor", isPresented: $nextdoorFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check that you have the Nextdoor app or a browser available.")
        }
    }

    /// Whether this report has reached the municipal relay, and a way to send it.
    @ViewBuilder
    private var publicWorksSection: some View {
        Section {
            if let ticket = current.relayTicketID {
                Label("Filed with the public works relay", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.teal)
                LabeledContent("Ticket", value: String(ticket.prefix(8)))
            } else {
                Button {
                    isForwarding = true
                    Task {
                        relayMessage = await ReportFollowUp.forward(current, store: store, settings: settings, account: account)
                        isForwarding = false
                    }
                } label: {
                    Label(isForwarding ? "Sending…" : "Send to public works relay", systemImage: "building.2.fill")
                }
                .disabled(isForwarding)
            }
        } footer: {
            Text("Files this report with the StormWatch backend over Open311. Towns that have opted in receive it at their public works desk; every report joins the open GIS feed. The photo is not sent.")
        }
    }

    /// How this hazard comes off the map, which depends on who is looking at it.
    @ViewBuilder
    private var removalSection: some View {
        let votes = current.notThereVotes ?? 0
        Section {
            if !current.isShared {
                Button(role: .destructive) {
                    store.delete(current)
                    dismiss()
                } label: {
                    Label("Remove report", systemImage: "trash")
                }
            } else if canRemoveShared {
                Button(role: .destructive) {
                    act(thenDismiss: true) { try await HazardSync.remove(current, store: store, account: account) }
                } label: {
                    Label("Remove for everyone", systemImage: "trash")
                }
                .disabled(isActing)
            } else {
                Button {
                    act {
                        if try await HazardSync.voteNotThere(current, store: store, account: account) { dismiss() }
                    }
                } label: {
                    Label(current.iVotedNotThere == true ? "You said it's gone" : "It's not there anymore",
                          systemImage: current.iVotedNotThere == true ? "checkmark.circle.fill" : "eye.slash.fill")
                }
                .disabled(isActing || current.iVotedNotThere == true)

                LabeledContent("Said gone") {
                    Text("\(votes) of \(Self.votesToRemove)")
                        .monospacedDigit()
                        .foregroundStyle(votes > 0 ? .orange : .secondary)
                }
            }
        } header: {
            Text("Gone?")
        } footer: {
            if !current.isShared {
                Text("This report only exists on this device.")
            } else if current.isMine == true {
                Text("You reported this, so you can take it down. It comes off the map for everyone.")
            } else if isTownship {
                Text("As township staff you can take this down once it is cleared. It comes off the map for everyone.")
            } else {
                Text("When \(Self.votesToRemove) different people say a hazard is gone, it comes off the map for everyone.")
            }
        }
    }

    /// Mirrors the server's threshold, which is what actually decides removal.
    private static let votesToRemove = 3

    private func act(thenDismiss: Bool = false, _ action: @escaping () async throws -> Void) {
        isActing = true
        Task {
            do {
                try await action()
                if thenDismiss { dismiss() }
            } catch {
                actionError = error.localizedDescription
            }
            isActing = false
        }
    }
}
