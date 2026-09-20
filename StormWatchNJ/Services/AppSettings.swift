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

    @Published var simulateNoreaster: Bool = false

    private let defaults: UserDefaults

    private enum Keys {
        static let radius = "stormwatch.searchRadiusMiles"
        static let useRemote = "stormwatch.useRemoteTriage"
        static let backendURL = "stormwatch.backendURL"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedRadius = defaults.double(forKey: Keys.radius)
        self.searchRadiusMiles = storedRadius > 0 ? storedRadius : 5.0
        self.useRemoteTriage = defaults.bool(forKey: Keys.useRemote)
        self.backendURLString = defaults.string(forKey: Keys.backendURL) ?? "http://127.0.0.1:8000"
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
