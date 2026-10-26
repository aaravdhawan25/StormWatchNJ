import Foundation

// user-facing configuration, persisted in `UserDefaults`
@MainActor
final class AppSettings: ObservableObject {
    @Published var searchRadiusMiles: Double {
        didSet { defaults.set(searchRadiusMiles, forKey: Keys.radius) }
    }

    // whether to offer a Nextdoor cross-post after a report is submitted
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

    // photo triage always goes to OpenAI through the server
    func triageEngine(token: String?) -> any TriageEngine {
        guard let token else { return OnDeviceTriageEngine() }
        return RemoteTriageEngine(token: token)
    }
}
