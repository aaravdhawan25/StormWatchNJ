import Foundation

/// Where the StormWatch NJ backend lives.
///
/// The publishable key is meant to ship inside the app: it only identifies the
/// project. What a caller may actually do is decided on the server, by row level
/// security and the database functions in `supabase/migrations`. The secret
/// service-role key is never in the app.
enum SupabaseConfig {
    static let url = URL(string: "https://yvmmtuqwjvztvxwpmfwf.supabase.co")!
    static let publishableKey = "sb_publishable_J48JNj6IRTzpzwkBsgM_MQ_NmERLY1v"

    static func function(_ path: String) -> URL {
        url.appendingPathComponent("functions/v1/\(path)")
    }

    /// Public GeoJSON layer for ArcGIS Online / QGIS.
    static var feedURL: URL { function("hazard-feed") }
}
