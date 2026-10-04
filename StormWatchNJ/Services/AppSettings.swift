import Foundation

/// User-facing configuration, persisted in `UserDefaults`.
@MainActor
final class AppSettings: ObservableObject {
    @Published var searchRadiusMiles: Double {
        didSet { defaults.set(searchRadiusMiles, forKey: Keys.radius) }
    }

    /// When on, the Snap & Triage screen calls the FastAPI backend instead of the
    /// on-device Vision engine.
    @Published var useRemoteTriage: Bool {
        didSet { defaults.set(useRemoteTriage, forKey: Keys.useRemote) }
    }

    @Published var backendURLString: String {
        didSet { defaults.set(backendURLString, forKey: Keys.backendURL) }
    }

    /// Whether to offer a Nextdoor cross-post after a report is submitted.
    /// Only ever *offers* — nothing leaves the app without an explicit tap, and
    /// the neighbor still confirms inside Nextdoor's own composer.
    @Published var offerNextdoorShare: Bool {
        didSet { defaults.set(offerNextdoorShare, forKey: Keys.nextdoor) }
    }

    /// Whether posted reports are also filed with the backend's Open311 endpoint,
    /// which publishes them in the GIS feed and forwards them to opted-in towns.
    /// Off by default: it needs a running backend, and sending a report off the
    /// device should be something the resident chose.
    @Published var forwardToPublicWorks: Bool {
        didSet { defaults.set(forwardToPublicWorks, forKey: Keys.forward) }
    }

    @Published var relayAPIKey: String {
        didSet { defaults.set(relayAPIKey, forKey: Keys.relayKey) }
    }

    @Published var simulateNoreaster: Bool = false

    private let defaults: UserDefaults

    private enum Keys {
        static let radius = "stormwatch.searchRadiusMiles"
        static let useRemote = "stormwatch.useRemoteTriage"
        static let backendURL = "stormwatch.backendURL"
        static let nextdoor = "stormwatch.offerNextdoorShare"
        static let forward = "stormwatch.forwardToPublicWorks"
        static let relayKey = "stormwatch.relayAPIKey"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedRadius = defaults.double(forKey: Keys.radius)
        self.searchRadiusMiles = storedRadius > 0 ? storedRadius : 5.0
        self.useRemoteTriage = defaults.bool(forKey: Keys.useRemote)
        self.backendURLString = defaults.string(forKey: Keys.backendURL) ?? "http://127.0.0.1:8000"
        self.offerNextdoorShare = defaults.object(forKey: Keys.nextdoor) as? Bool ?? true
        self.forwardToPublicWorks = defaults.bool(forKey: Keys.forward)
        self.relayAPIKey = defaults.string(forKey: Keys.relayKey) ?? ""
    }

    var backendURL: URL? {
        URL(string: backendURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The engine the Snap & Triage screen should use right now. Falls back to the
    /// on-device engine whenever the remote URL is unusable, so the flow never dead-ends.
    var triageEngine: any TriageEngine {
        guard useRemoteTriage, let url = backendURL, url.scheme != nil else {
            return OnDeviceTriageEngine()
        }
        return RemoteTriageEngine(baseURL: url)
    }
}
