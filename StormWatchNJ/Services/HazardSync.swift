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

    /// A report first seen from the server, i.e. posted from someone else's phone.
    func makeReport() -> HazardReport? {
        guard let type = HazardType(rawValue: report_type) else { return nil }
        let formatter = ISO8601DateFormatter()
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
                                  createdAt: formatter.date(from: created_at) ?? Date(),
                                  updatedAt: formatter.date(from: updated_at) ?? Date())
        report.relayTicketID = id
        apply(to: &report)
        return report
    }
}

/// Pulls the shared hazard list and applies removal decisions made on the server.
@MainActor
enum HazardSync {
    /// Quietly does nothing when the backend is unset or unreachable — the app is
    /// meant to keep working from its local store.
    static func pull(into store: HazardStore, account: AccountStore) async {
        guard let api = account.api,
              let hazards: [ServerHazard] = try? await api.send("GET", "api/v1/hazards") else { return }
        store.merge(serverHazards: hazards)
    }

    struct VoteResult: Decodable {
        let removed: Bool
        let not_there_votes: Int
        let not_there_threshold: Int
    }

    /// Records "it's not there". Returns true if that vote removed the hazard.
    static func voteNotThere(_ report: HazardReport, store: HazardStore, account: AccountStore) async throws -> Bool {
        guard let api = account.api, let ticket = report.relayTicketID else { throw APIError.notConfigured }
        let result: VoteResult = try await api.send("POST", "api/v1/hazards/\(ticket)/not-there")
        await pull(into: store, account: account)
        return result.removed
    }

    static func remove(_ report: HazardReport, store: HazardStore, account: AccountStore) async throws {
        guard let api = account.api, let ticket = report.relayTicketID else { throw APIError.notConfigured }
        do {
            let _: BackendAPI.Empty = try await api.send("DELETE", "api/v1/hazards/\(ticket)")
        } catch let error as APIError where error.status == 404 {
            // Already gone on the server; fall through and drop the local copy.
        }
        store.delete(report)
    }

    static func setStatus(_ status: ReportStatus, for report: HazardReport,
                          store: HazardStore, account: AccountStore) async throws {
        guard let api = account.api, let ticket = report.relayTicketID else { throw APIError.notConfigured }
        let _: ServerHazard = try await api.send("PATCH", "api/v1/hazards/\(ticket)/status",
                                                 body: ["status": status.rawValue])
        await pull(into: store, account: account)
    }
}
