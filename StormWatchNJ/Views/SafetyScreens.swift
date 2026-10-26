import CoreLocation
import MapKit
import SwiftUI

// which place a safety lookup is about
@MainActor
final class LookupArea: ObservableObject {
    @Published var zip = ""
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var message: String?
    @Published private(set) var isResolving = false

    // starts from the map location and works out its ZIP code
    func useLocation(_ location: CLLocationCoordinate2D) async {
        coordinate = location
        message = nil
        if let found = await AddressResolver.resolve(latitude: location.latitude, longitude: location.longitude)?.postalCode {
            zip = found
        }
    }

    // moves the lookup to the ZIP in the field
    func useTypedZIP() async -> Bool {
        isResolving = true
        defer { isResolving = false }
        guard let found = await AddressResolver.coordinate(forZIP: zip) else {
            message = "That isn't a New Jersey ZIP code we can find."
            return false
        }
        coordinate = found
        message = nil
        return true
    }
}

// ZIP entry shared by the alert and shelter screens
struct AreaBar: View {
    @ObservedObject var area: LookupArea
    var onChange: () -> Void
    var onUseLocation: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.teal)
                TextField("ZIP code", text: $area.zip)
                    .keyboardType(.numberPad)
                    .textContentType(.postalCode)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .focused($focused)
                    .onChange(of: area.zip) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(5))
                        if digits != value { area.zip = digits }
                    }
                Button {
                    focused = false
                    Task { if await area.useTypedZIP() { onChange() } }
                } label: {
                    if area.isResolving { ProgressView() } else { Text("Check").fontWeight(.semibold) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.teal)
                .disabled(!ShelterService.isValidZIP(area.zip) || area.isResolving)

                Button {
                    focused = false
                    onUseLocation()
                } label: {
                    Image(systemName: "location.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Use my location")
            }
            if let message = area.message {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .stormCard()
    }
}

// MARK: - Flood alerts

struct FloodAlertsScreen: View {
    @EnvironmentObject private var alerts: FloodAlertService
    @EnvironmentObject private var location: LocationManager
    @StateObject private var area = LookupArea()
    @State private var selected: FloodAlert?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                AreaBar(area: area, onChange: reload) {
                    Task { await area.useLocation(location.coordinate); reload() }
                }

                sectionTitle("In effect now", symbol: "dot.radiowaves.left.and.right")
                if let error = alerts.liveError {
                    notice(error, symbol: "wifi.exclamationmark", tint: .orange)
                } else if alerts.active.isEmpty {
                    notice(alerts.isLoading ? "Checking the National Weather Service…"
                                            : "No flood alerts are in effect here right now.",
                           symbol: alerts.isLoading ? "hourglass" : "checkmark.shield.fill",
                           tint: alerts.isLoading ? .secondary : .green)
                } else {
                    ForEach(alerts.active) { alertCard($0) }
                }
                caption("Live from the National Weather Service, which issues flood watches and warnings.")

                sectionTitle("Past \(FloodAlertService.historyDays) days", symbol: "clock.arrow.circlepath")
                if let error = alerts.archiveError {
                    notice(error, symbol: "wifi.exclamationmark", tint: .orange)
                } else if alerts.recent.isEmpty {
                    notice(alerts.isLoading ? "Checking FEMA's archive…" : "No flood warnings were issued for this spot.",
                           symbol: alerts.isLoading ? "hourglass" : "tray", tint: .secondary)
                } else {
                    ForEach(alerts.recent) { alertCard($0) }
                }
                caption("From FEMA's IPAWS alert archive, which FEMA publishes a day late on purpose — these are history, not current warnings. It lists warnings drawn around this spot; county-wide watches appear only in the live list.")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Flood Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task {
            if area.coordinate == nil { await area.useLocation(location.coordinate) }
            await load()
        }
        .sheet(item: $selected) { alert in
            NavigationStack { FloodAlertDetail(alert: alert) }
                .presentationDetents([.medium, .large])
        }
    }

    private func reload() { Task { await load() } }

    private func load() async {
        await alerts.load(at: area.coordinate ?? location.coordinate)
    }

    private func sectionTitle(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 4)
    }

    private func notice(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.footnote)
            Spacer(minLength: 0)
        }
        .stormCard()
    }

    private func alertCard(_ alert: FloodAlert) -> some View {
        Button { selected = alert } label: {
            HStack(alignment: .top, spacing: 0) {
                Rectangle().fill(alert.tint).frame(width: 4)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(alert.event)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        Text(alert.severity.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(alert.tint.opacity(0.18), in: Capsule())
                            .foregroundStyle(alert.tint)
                    }
                    Text(alert.area).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(timing(alert)).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(12)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func timing(_ alert: FloodAlert) -> String {
        let format = Date.FormatStyle(date: .abbreviated, time: .shortened)
        switch alert.source {
        case .live:
            if let expires = alert.expires { return "Until \(expires.formatted(format))" }
            return "In effect"
        case .archive:
            return alert.sent.map { "Issued \($0.formatted(format))" } ?? "Issued earlier"
        }
    }
}

struct FloodAlertDetail: View {
    let alert: FloodAlert
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(alert.event).font(.system(.title3, design: .rounded).weight(.bold))
                    Chip(text: alert.source == .live ? "In effect now" : "Past alert — not current",
                         symbol: alert.source == .live ? "dot.radiowaves.left.and.right" : "clock.arrow.circlepath",
                         tint: alert.source == .live ? alert.tint : .secondary)
                    Text(alert.headline).font(.subheadline)
                }
                .padding(.vertical, 4)
            }
            Section("Area") { Text(alert.area).font(.footnote) }
            if !alert.instruction.isEmpty {
                Section("What to do") { Text(alert.instruction).font(.footnote) }
            }
            if !alert.details.isEmpty {
                Section("Details") { Text(alert.details).font(.footnote) }
            }
            Section {
                LabeledContent("Issued by", value: alert.sender.isEmpty ? "—" : alert.sender)
                LabeledContent("Source", value: alert.source == .live ? "National Weather Service" : "FEMA IPAWS archive")
            }
        }
        .navigationTitle("Alert")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

// MARK: - Shelters

struct ShelterScreen: View {
    @EnvironmentObject private var location: LocationManager
    @StateObject private var area = LookupArea()
    @State private var shelters: [Shelter] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var textUnavailable = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                AreaBar(area: area, onChange: reload) {
                    Task { await area.useLocation(location.coordinate); reload() }
                }

                if isLoading {
                    row { ProgressView(); Text("Checking FEMA's open shelter list…").font(.footnote) }
                } else if let errorMessage {
                    row { Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange); Text(errorMessage).font(.footnote) }
                } else if shelters.isEmpty, hasLoaded {
                    VStack(spacing: 8) {
                        Image(systemName: "house.lodge.fill").font(.system(size: 34)).foregroundStyle(Theme.teal.opacity(0.7))
                        Text("No open shelters nearby").font(.headline)
                        Text("FEMA lists no shelters open within \(Int(ShelterService.searchRadiusMiles)) miles right now. Shelters open when a storm displaces people, so this is normal on a calm day.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .stormCard()
                } else {
                    ForEach(shelters) { shelterCard($0) }
                }

                textCard

                Text("In immediate danger, call 911. Follow evacuation orders from local officials — they are the final word on which shelters are open.")
                    .font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Find a Shelter")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task {
            if area.coordinate == nil { await area.useLocation(location.coordinate) }
            await load()
        }
        .alert("Can't send texts from this device", isPresented: $textUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("From a phone, text SHELTER \(area.zip) to \(ShelterService.textNumber).")
        }
    }

    private func reload() { Task { await load() } }

    // debug: -shelterTestPoint "lat,lon"
    private static var debugPoint: CLLocationCoordinate2D? {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "shelterTestPoint") else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return parts.count == 2 ? CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1]) : nil
        #else
        return nil
        #endif
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            shelters = try await ShelterService.openShelters(near: Self.debugPoint ?? area.coordinate ?? location.coordinate)
        } catch {
            shelters = []
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
        isLoading = false
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content(); Spacer(minLength: 0) }.stormCard()
    }

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ask FEMA by text", systemImage: "message.fill")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
            Text("FEMA replies with the nearest open shelters. It works without a data connection.")
                .font(.footnote).foregroundStyle(.secondary)

            Button {
                guard let url = ShelterService.textURL(zip: area.zip) else { return }
                UIApplication.shared.open(url, options: [:]) { opened in
                    if !opened { textUnavailable = true }
                }
            } label: {
                Text(ShelterService.isValidZIP(area.zip)
                     ? "Text “SHELTER \(area.zip)” to \(ShelterService.textNumber)"
                     : "Enter a ZIP code above")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.teal)
            .disabled(!ShelterService.isValidZIP(area.zip))

            Text("Opens Messages with the text written; you tap send. Message and data rates may apply.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .stormCard()
    }

    private func shelterCard(_ shelter: Shelter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shelter.name).font(.system(.subheadline, design: .rounded).weight(.bold))
                    Text(shelter.address).font(.caption).foregroundStyle(.secondary)
                    if let organization = shelter.organization, !organization.isEmpty {
                        Text("Run by \(organization)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let miles = shelter.distanceMiles {
                    Text(String(format: "%.1f mi", miles))
                        .font(.caption.weight(.bold)).foregroundStyle(Theme.teal)
                }
            }
            HStack(spacing: 6) {
                Chip(text: "Open", symbol: "checkmark.circle.fill", tint: .green)
                if let pets = shelter.acceptsPets {
                    Chip(text: pets ? "Pets OK" : "No pets", symbol: "pawprint.fill", tint: pets ? Theme.teal : .secondary)
                }
                if shelter.wheelchairAccessible == true {
                    Chip(text: "Accessible", symbol: "figure.roll", tint: Theme.teal)
                }
            }
            if let coordinate = shelter.coordinate {
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                    item.name = shelter.name
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .stormCard()
    }
}
