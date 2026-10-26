import CoreLocation
import Foundation

// New Jersey's bounding box, used to decide whether a real GPS fix is usable
enum NJServiceArea {
    static let minLatitude = 38.86
    static let maxLatitude = 41.40
    static let minLongitude = -75.61
    static let maxLongitude = -73.88

    // Plainsboro, the center of the demo reports
    static let demoCenter = CLLocationCoordinate2D(latitude: 40.3318, longitude: -74.5893)

    static func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= minLatitude && coordinate.latitude <= maxLatitude
            && coordinate.longitude >= minLongitude && coordinate.longitude <= maxLongitude
    }
}

// how the app arrived at the coordinate it is currently using
enum LocationMode: Equatable {
    // a real fix, inside New Jersey
    case live
    // permission not answered yet
    case awaitingPermission
    // permission granted, no fix yet
    case awaitingFix
    // permission refused
    case denied
    // a real fix, but outside the service area, showing the NJ demo area instead
    case outsideServiceArea

    var usesDemoCenter: Bool { self != .live }
}

// wraps `CLLocationManager` so views can read a single published coordinate
@MainActor
final class LocationManager: NSObject, ObservableObject {
    static let defaultCoordinate = NJServiceArea.demoCenter

    // the coordinate the rest of the app should use
    @Published private(set) var coordinate: CLLocationCoordinate2D = NJServiceArea.demoCenter
    // the device's actual position, whatever it is
    @Published private(set) var rawCoordinate: CLLocationCoordinate2D?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var mode: LocationMode = .awaitingPermission

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
        mode = Self.mode(for: manager.authorizationStatus, fix: nil)
    }

    func requestPermission() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func startUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        manager.startUpdatingLocation()
    }

    var currentLocation: CLLocation {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    // short line shown under the map / list explaining which coordinate is in use
    var statusDescription: String {
        switch mode {
        case .live:
            return "Using your current location."
        case .awaitingPermission:
            return "Allow location access to see hazards around you."
        case .awaitingFix:
            return "Waiting for a GPS fix — showing the Plainsboro demo area."
        case .denied:
            return "Location is off — showing the Plainsboro demo area."
        case .outsideServiceArea:
            return "You're outside New Jersey — showing the Plainsboro demo area."
        }
    }

    var needsAttention: Bool { mode != .live }

    private static func mode(for status: CLAuthorizationStatus,
                             fix: CLLocationCoordinate2D?) -> LocationMode {
        switch status {
        case .notDetermined:
            return .awaitingPermission
        case .restricted, .denied:
            return .denied
        case .authorizedAlways, .authorizedWhenInUse:
            guard let fix else { return .awaitingFix }
            return NJServiceArea.contains(fix) ? .live : .outsideServiceArea
        @unknown default:
            return .awaitingPermission
        }
    }

    fileprivate func apply(status: CLAuthorizationStatus) {
        authorizationStatus = status
        mode = Self.mode(for: status, fix: rawCoordinate)
        if mode.usesDemoCenter { coordinate = NJServiceArea.demoCenter }
        startUpdates()
    }

    fileprivate func apply(fix: CLLocationCoordinate2D) {
        rawCoordinate = fix
        mode = Self.mode(for: authorizationStatus, fix: fix)
        coordinate = mode == .live ? fix : NJServiceArea.demoCenter
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.apply(status: status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let fix = latest.coordinate
        Task { @MainActor in self.apply(fix: fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // keep the last good coordinate
    }
}
