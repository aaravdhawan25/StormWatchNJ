import CoreLocation
import Foundation

/// A street-level description of where a hazard is.
struct ResolvedAddress: Equatable {
    var street: String?
    var city: String?
    var postalCode: String?

    /// "12 Dey Rd, Plainsboro, NJ 08536" — what a caller reads to a dispatcher,
    /// and the Open311 `address_string`.
    var singleLine: String? {
        var parts: [String] = []
        if let street { parts.append(street) }
        if let city { parts.append(city) }
        var line = parts.joined(separator: ", ")
        guard !line.isEmpty else { return nil }
        line += ", NJ"
        if let postalCode { line += " \(postalCode)" }
        return line
    }
}

/// Turns a coordinate into a street address with Apple's reverse geocoder.
///
/// A dispatcher needs "near 12 Dey Road", not a latitude, and the municipal relay
/// routes by ZIP code. Returns nil when offline or when nothing is found, and
/// every caller falls back to the town name.
enum AddressResolver {
    /// The centre of a New Jersey ZIP code, for looking up alerts or shelters
    /// somewhere other than where the phone is.
    static func coordinate(forZIP zip: String) async -> CLLocationCoordinate2D? {
        guard zip.count == 5, zip.allSatisfy(\.isNumber),
              let placemark = try? await CLGeocoder().geocodeAddressString("\(zip), NJ, USA").first,
              let location = placemark.location,
              placemark.postalCode == zip,
              NJServiceArea.contains(location.coordinate) else { return nil }
        return location.coordinate
    }

    static func resolve(latitude: Double, longitude: Double) async -> ResolvedAddress? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return nil
        }
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let resolved = ResolvedAddress(street: street.isEmpty ? nil : street,
                                       city: placemark.locality,
                                       postalCode: placemark.postalCode)
        return resolved.singleLine == nil && resolved.postalCode == nil ? nil : resolved
    }
}
