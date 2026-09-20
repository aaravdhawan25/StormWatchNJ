import CoreLocation
import Foundation

/// Wraps `CLLocationManager` so views can read a single published coordinate.
///
/// The app never uploads a raw trace — a coordinate is attached only to a report
/// the resident explicitly submits, matching the privacy claim in the demo script.
@MainActor
final class LocationManager: NSObject, ObservableObject {
    /// Plainsboro, NJ. Used until Core Location produces a fix, which keeps the
    /// map useful in a fresh simulator with no location simulated.
    static let defaultCoordinate = CLLocationCoordinate2D(latitude: 40.3318, longitude: -74.5893)

    @Published private(set) var coordinate: CLLocationCoordinate2D = LocationManager.defaultCoordinate
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var hasRealFix = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        manager.startUpdatingLocation()
    }

    var currentLocation: CLLocation {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var statusDescription: String {
        switch authorizationStatus {
        case .notDetermined: return "Location permission not requested yet."
        case .restricted, .denied: return "Location denied — showing the Plainsboro demo area."
        case .authorizedAlways, .authorizedWhenInUse:
            return hasRealFix ? "Using your current location." : "Waiting for a GPS fix…"
        @unknown default: return "Location status unknown."
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.startUpdates()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.coordinate = latest.coordinate
            self.hasRealFix = true
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the last good coordinate; the banner already explains the fallback.
    }
}
