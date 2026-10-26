import Foundation

// builds the municipal DPW feeds described in the blueprint
enum ExportService {
    static func geoJSON(from reports: [HazardReport]) -> String {
        let formatter = ISO8601DateFormatter()
        let features: [[String: Any]] = reports.map { report in
            [
                "type": "Feature",
                "geometry": [
                    "type": "Point",
                    // GeoJSON is longitude-first, matching PostGIS ST_MakePoint
                    "coordinates": [report.longitude, report.latitude]
                ],
                "properties": [
                    "id": report.id.uuidString,
                    "report_type": report.reportType.rawValue,
                    "severity": report.severity.rawValue,
                    "road_status": report.roadStatus.rawValue,
                    "utility_lines_involved": report.utilityLinesInvolved,
                    "description": report.details,
                    "municipality": report.municipality,
                    "status": report.status.rawValue,
                    "upvotes": report.upvotes,
                    "created_at": formatter.string(from: report.createdAt),
                    "updated_at": formatter.string(from: report.updatedAt)
                ]
            ]
        }

        let collection: [String: Any] = [
            "type": "FeatureCollection",
            "generated_at": formatter.string(from: Date()),
            "source": "StormWatch NJ",
            "features": features
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: collection,
                                                     options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"type\":\"FeatureCollection\",\"features\":[]}"
        }
        return text
    }

    static func csv(from reports: [HazardReport]) -> String {
        let formatter = ISO8601DateFormatter()
        let header = "id,report_type,severity,road_status,utility_lines_involved,municipality,status,upvotes,latitude,longitude,created_at,description"
        let rows = reports.map { report in
            [
                report.id.uuidString,
                report.reportType.rawValue,
                report.severity.rawValue,
                report.roadStatus.rawValue,
                String(report.utilityLinesInvolved),
                escape(report.municipality),
                report.status.rawValue,
                String(report.upvotes),
                String(format: "%.6f", report.latitude),
                String(format: "%.6f", report.longitude),
                formatter.string(from: report.createdAt),
                escape(report.details)
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    // writes `contents` into a temp file so it can go through the share sheet
    static func temporaryFile(named name: String, contents: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
