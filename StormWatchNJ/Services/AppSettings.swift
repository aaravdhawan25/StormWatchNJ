import Foundation

/// User-facing configuration, persisted in `UserDefaults`.
@MainActor
final class AppSettings: ObservableObject {
    @Published var searchRadiusMiles: Double {
        didSet { defaults.set(searchRadiusMiles, forKey: Keys.radius) }
    }

    /// When on (the default), Snap & Triage sends the photo to OpenAI through the
    /// server; off, it is analyzed on the device and never leaves it.
    @Published var useRemoteTriage: Bool {
        didSet { defaults.set(useRemoteTriage, forKey: Keys.useRemote) }
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
        static let useRemote = "stormwatch.useRemoteTriage"
        static let nextdoor = "stormwatch.offerNextdoorShare"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedRadius = defaults.double(forKey: Keys.radius)
        self.searchRadiusMiles = storedRadius > 0 ? storedRadius : 5.0
        self.useRemoteTriage = defaults.object(forKey: Keys.useRemote) as? Bool ?? true
        self.offerNextdoorShare = defaults.object(forKey: Keys.nextdoor) as? Bool ?? true
    }

    /// The engine Snap & Triage should use right now. Falls back to on-device
    /// analysis when OpenAI is off or nobody is signed in, so the flow never dead-ends.
    func triageEngine(token: String?) -> any TriageEngine {
        guard useRemoteTriage, let token else { return OnDeviceTriageEngine() }
        return RemoteTriageEngine(token: token)
    }
}
