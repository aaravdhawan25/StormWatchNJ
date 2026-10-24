import CoreLocation
import Foundation

/// A hazard as the shared database describes it.
struct ServerHazard: Decodable {
    let id: String
    let report_type: String
    let severity: String
    let road_status: String
    let utility_lines_involved: Bool
    let description: String
    let municipality: String?
    let address: String?
    let zipcode: String?
    let latitude: Double
    let longitude: Double
    let status: String
    let upvotes: Int
    let created_at: String
    let updated_at: String
    let not_there_votes: Int
    let i_voted_not_there: Bool
    let is_mine: Bool

    /// Copies the server's view onto a report this device already has, keeping
    /// what only the device knows — its local id and its photo.
    func apply(to report: inout HazardReport) {
        report.status = ReportStatus(rawValue: status) ?? report.status
        report.upvotes = max(report.upvotes, upvotes)
        report.address = address ?? report.address
        report.postalCode = zipcode ?? report.postalCode
        report.isMine = is_mine
        report.notThereVotes = not_there_votes
        report.iVotedNotThere = i_voted_not_there
    }

    /// Postgres timestamps carry fractional seconds, which the plain ISO 8601
    /// parser rejects, so try that form first.
    private static func date(_ text: String) -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) ?? Date()
    }

    /// A report first seen from the server, i.e. posted from someone else's phone.
    func makeReport() -> HazardReport? {
        guard let type = HazardType(rawValue: report_type) else { return nil }
        var report = HazardReport(id: UUID(uuidString: id) ?? UUID(),
                                  reportType: type,
                                  severity: Severity(rawValue: severity) ?? .moderate,
                                  roadStatus: RoadStatus(rawValue: road_status) ?? .oneLaneOpen,
                                  utilityLinesInvolved: utility_lines_involved,
                                  details: description,
                                  photoFilename: nil,
                                  latitude: latitude,
                                  longitude: longitude,
                                  municipality: municipality ?? "New Jersey",
                                  status: ReportStatus(rawValue: status) ?? .active,
                                  upvotes: upvotes,
                                  createdAt: Self.date(created_at),
                                  updatedAt: Self.date(updated_at))
        report.relayTicketID = id
        apply(to: &report)
        return report
    }
}

/// Pulls the shared hazard list and applies removal decisions made on the server.
@MainActor
enum HazardSync {
    /// Quietly does nothing when signed out or offline — the app is meant to
    /// keep working from its local store.
    static func pull(into store: HazardStore, account: AccountStore) async {
        guard let api = await account.authorizedAPI(),
              let hazards: [ServerHazard] = try? await api.send("POST", "rest/v1/rpc/list_hazards", body: [:]) else { return }
        store.merge(serverHazards: hazards)
        AppServices.shared.notifications.process(hazards: hazards, accountID: account.account?.id)
    }

    struct VoteResult: Decodable {
        let removed: Bool
        let not_there_votes: Int
        let not_there_threshold: Int
    }

    private static let signedOut = APIError.server(status: 401, detail: "Sign in to do that.", code: nil)

    /// Records "it's not there". Returns true if that vote removed the hazard.
    /// `from` is the device's real position; the server only counts votes made
    /// within 1 mile of the hazard.
    static func voteNotThere(_ report: HazardReport, from position: CLLocationCoordinate2D?,
                             store: HazardStore, account: AccountStore) async throws -> Bool {
        guard let api = await account.authorizedAPI(), let ticket = report.relayTicketID else { throw signedOut }
        guard let position else {
            throw APIError.server(status: 400, detail: "Turn on location to vote. You need to be within 1 mile of the hazard.", code: "P0001")
        }
        let result: VoteResult = try await api.send("POST", "rest/v1/rpc/vote_not_there", body: [
            "p_hazard": ticket, "p_latitude": position.latitude, "p_longitude": position.longitude
        ])
        await pull(into: store, account: account)
        return result.removed
    }

    static func remove(_ report: HazardReport, store: HazardStore, account: AccountStore) async throws {
        guard let api = await account.authorizedAPI(), let ticket = report.relayTicketID else { throw signedOut }
        do {
            let _: BackendAPI.Empty = try await api.send("POST", "rest/v1/rpc/remove_hazard", body: ["p_hazard": ticket])
        } catch let error as APIError where error.code == "P0002" {
            // Already gone on the server; fall through and drop the local copy.
        }
        AppServices.shared.notifications.forgetMyReport(ticket)
        store.delete(report)
    }

    static func setStatus(_ status: ReportStatus, for report: HazardReport,
                          store: HazardStore, account: AccountStore) async throws {
        guard let api = await account.authorizedAPI(), let ticket = report.relayTicketID else { throw signedOut }
        let _: BackendAPI.Empty = try await api.send("POST", "rest/v1/rpc/set_hazard_status",
                                                     body: ["p_hazard": ticket, "p_status": status.rawValue])
        await pull(into: store, account: account)
    }
}
