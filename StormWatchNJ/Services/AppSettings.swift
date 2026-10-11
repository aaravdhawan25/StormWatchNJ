import Foundation

/// User-facing configuration, persisted in `UserDefaults`.
@MainActor
final class AppSettings: ObservableObject {
    @Published var searchRadiusMiles: Double {
        didSet { defaults.set(searchRadiusMiles, forKey: Keys.radius) }
    }

    /// Whether to offer a Nextdoor cross-post after a report is submitted.
    /// Only ever *offers* — nothing leaves the app without an explicit tap, and
    /// the neighbor still confirms inside Nextdoor's own composer.
    @Published var offerNextdoorShare: Bool {
        didSet { defaults.set(offerNextdoorShare, forKey: Keys.nextdoor) }
    }

    @Published var simulateNoreaster: Bool = false

    private let defaults: UserDefaults

    private enum Keys {
        static let radius = "stormwatch.searchRadiusMiles"
        static let nextdoor = "stormwatch.offerNextdoorShare"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedRadius = defaults.double(forKey: Keys.radius)
        self.searchRadiusMiles = storedRadius > 0 ? storedRadius : 5.0
        self.offerNextdoorShare = defaults.object(forKey: Keys.nextdoor) as? Bool ?? true
    }

    /// Photo triage always goes to OpenAI through the server. On-device analysis
    /// is not a user choice; it is only the safety net `SnapTriageScreen` falls
    /// back to when that call fails, so a resident with no signal can still file.
    func triageEngine(token: String?) -> any TriageEngine {
        guard let token else { return OnDeviceTriageEngine() }
        return RemoteTriageEngine(token: token)
    }
}
