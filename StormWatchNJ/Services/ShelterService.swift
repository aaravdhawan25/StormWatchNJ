import CoreLocation
import Foundation

// an emergency shelter that FEMA currently lists as open
struct Shelter: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let organization: String?
    let acceptsPets: Bool?
    let wheelchairAccessible: Bool?
    let latitude: Double?
    let longitude: Double?
    let distanceMiles: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// finds open emergency shelters, two ways
enum ShelterService {
    static let searchRadiusMiles = 50.0

    // FEMA's short code, 4FEMA
    static let textNumber = "43362"

    struct LookupError: LocalizedError {
        var errorDescription: String? { "Couldn't reach FEMA's shelter list. Use the text option below." }
    }

    static func openShelters(near point: CLLocationCoordinate2D) async throws -> [Shelter] {
        var components = URLComponents(string: "https://gis.fema.gov/arcgis/rest/services/NSS/OpenShelters/FeatureServer/0/query")!
        components.queryItems = [
            URLQueryItem(name: "where", value: "shelter_status='OPEN'"),
            URLQueryItem(name: "geometry", value: "\(point.longitude),\(point.latitude)"),
            URLQueryItem(name: "geometryType", value: "esriGeometryPoint"),
            URLQueryItem(name: "inSR", value: "4326"),
            URLQueryItem(name: "distance", value: String(searchRadiusMiles)),
            URLQueryItem(name: "units", value: "esriSRUnit_StatuteMile"),
            URLQueryItem(name: "outFields", value: "shelter_id,shelter_name,address,city,state,zip,org_name,pet_accommodations_code,wheelchair_accessible"),
            // the latitude/longitude attributes are often empty; the geometry is not
            URLQueryItem(name: "returnGeometry", value: "true"),
            URLQueryItem(name: "outSR", value: "4326"),
            URLQueryItem(name: "f", value: "json")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["error"] == nil,
              let features = root["features"] as? [[String: Any]] else {
            throw LookupError()
        }

        let origin = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let shelters = features.compactMap { feature -> Shelter? in
            guard let a = feature["attributes"] as? [String: Any],
                  let name = a["shelter_name"] as? String else { return nil }
            let geometry = feature["geometry"] as? [String: Any]
            let lon = geometry?["x"] as? Double
            let lat = geometry?["y"] as? Double

            // FEMA sometimes fills ZIP with "0"
            let zip = (a["zip"] as? String).flatMap { $0.count == 5 ? $0 : nil }
            let cityLine = [a["city"] as? String, a["state"] as? String].compactMap { $0 }.joined(separator: ", ")
            let address = [a["address"] as? String, cityLine.isEmpty ? nil : cityLine, zip]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")

            var distance: Double?
            if let lat, let lon {
                distance = origin.distance(from: CLLocation(latitude: lat, longitude: lon)) / 1609.34
            }
            return Shelter(id: (a["shelter_id"] as? Int).map(String.init) ?? UUID().uuidString,
                           name: name,
                           address: address,
                           organization: a["org_name"] as? String,
                           acceptsPets: flag(a["pet_accommodations_code"], noValues: ["NONE", "NO"]),
                           wheelchairAccessible: flag(a["wheelchair_accessible"], noValues: ["NO", "N"]),
                           latitude: lat,
                           longitude: lon,
                           distanceMiles: distance)
        }
        return shelters.sorted { ($0.distanceMiles ?? .infinity) < ($1.distanceMiles ?? .infinity) }
    }

    // FEMA uses "UNK" freely
    private static func flag(_ value: Any?, noValues: [String]) -> Bool? {
        guard let text = (value as? String)?.uppercased(), !text.isEmpty, text != "UNK" else { return nil }
        return !noValues.contains(text)
    }

    static func isValidZIP(_ zip: String) -> Bool {
        zip.count == 5 && zip.allSatisfy(\.isNumber)
    }

    // opens Messages addressed to 43362 with "SHELTER <zip>" typed in
    static func textURL(zip: String) -> URL? {
        guard isValidZIP(zip) else { return nil }
        return URL(string: "sms:\(textNumber)&body=SHELTER%20\(zip)")
    }
}
