import Foundation

// where the StormWatch NJ backend lives
enum SupabaseConfig {
    static let url = URL(string: "https://yvmmtuqwjvztvxwpmfwf.supabase.co")!
    static let publishableKey = "sb_publishable_J48JNj6IRTzpzwkBsgM_MQ_NmERLY1v"

    static func function(_ path: String) -> URL {
        url.appendingPathComponent("functions/v1/\(path)")
    }

    // public GeoJSON layer for ArcGIS Online / QGIS
    static var feedURL: URL { function("hazard-feed") }
}
