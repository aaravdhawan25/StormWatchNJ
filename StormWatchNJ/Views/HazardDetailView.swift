import Foundation
import MapKit
import SwiftUI

struct HazardDetailView: View {
    let report: HazardReport

    @EnvironmentObject private var store: HazardStore
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var nextdoorFailed = false
    @State private var relayMessage: String?
    @State private var isForwarding = false

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
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(current.severity.tint.opacity(0.18)).frame(width: 42, height: 42)
                            Image(systemName: current.reportType.symbolName)
                                .font(.title3)
                                .foregroundStyle(current.severity.tint)
                        }
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

                Picker("Crew status", selection: Binding(
                    get: { current.status },
                    set: { store.setStatus($0, for: current) }
                )) {
                    ForEach(ReportStatus.allCases) { Text($0.label).tag($0) }
                }

                Button(role: .destructive) {
                    store.delete(current)
                    dismiss()
                } label: {
                    Label("Remove report", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Hazard")
        .navigationBarTitleDisplayMode(.inline)
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
                        relayMessage = await ReportFollowUp.forward(current, store: store, settings: settings)
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
}
