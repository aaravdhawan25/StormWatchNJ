import CoreLocation
import Foundation

// a small offline gazetteer of central/northern NJ towns
enum NJMunicipalities {
    static let towns: [(name: String, county: String, coordinate: CLLocationCoordinate2D)] = [
        ("Plainsboro", "Middlesex", .init(latitude: 40.3318, longitude: -74.5893)),
        ("Princeton", "Mercer", .init(latitude: 40.3573, longitude: -74.6672)),
        ("West Windsor", "Mercer", .init(latitude: 40.2965, longitude: -74.6221)),
        ("South Brunswick", "Middlesex", .init(latitude: 40.3868, longitude: -74.5232)),
        ("New Brunswick", "Middlesex", .init(latitude: 40.4862, longitude: -74.4518)),
        ("Franklin Township", "Somerset", .init(latitude: 40.4976, longitude: -74.5321)),
        ("Bound Brook", "Somerset", .init(latitude: 40.5679, longitude: -74.5385)),
        ("Manville", "Somerset", .init(latitude: 40.5401, longitude: -74.5885)),
        ("Hillsborough", "Somerset", .init(latitude: 40.4665, longitude: -74.6482)),
        ("Edison", "Middlesex", .init(latitude: 40.5187, longitude: -74.4121)),
        ("Morristown", "Morris", .init(latitude: 40.7968, longitude: -74.4815)),
        ("Chatham", "Morris", .init(latitude: 40.7407, longitude: -74.3838)),
        ("Little Falls", "Passaic", .init(latitude: 40.8690, longitude: -74.2082)),
        ("Lodi", "Bergen", .init(latitude: 40.8823, longitude: -74.0832)),
        ("High Bridge", "Hunterdon", .init(latitude: 40.6684, longitude: -74.8954)),
        ("Pemberton", "Burlington", .init(latitude: 39.9718, longitude: -74.6829)),
        ("Squankum", "Monmouth", .init(latitude: 40.1590, longitude: -74.1329))
    ]

    // the nearest listed town, but only if it is within about 8 miles
    static func nearby(_ coordinate: CLLocationCoordinate2D) -> String? {
        let match = nearest(to: coordinate)
        guard let town = towns.first(where: { $0.name == match.name }) else { return nil }
        let miles = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: town.coordinate.latitude, longitude: town.coordinate.longitude)) / 1609.34
        return miles <= 8 ? town.name : nil
    }

    // nearest town by great-circle distance
    static func nearest(to coordinate: CLLocationCoordinate2D) -> (name: String, county: String) {
        let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let closest = towns.min { lhs, rhs in
            let l = CLLocation(latitude: lhs.coordinate.latitude, longitude: lhs.coordinate.longitude)
            let r = CLLocation(latitude: rhs.coordinate.latitude, longitude: rhs.coordinate.longitude)
            return point.distance(from: l) < point.distance(from: r)
        }
        guard let closest else { return ("New Jersey", "NJ") }
        return (closest.name, closest.county)
    }
}
