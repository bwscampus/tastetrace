import Foundation

public extension APIClient {
    /// `GET /api/digest/weekly?weekStart=YYYY-MM-DD&tz=…`
    func weeklyDigest(weekStart: String, tz: String) async throws -> WeeklyDigest {
        try await request(.get, "/api/digest/weekly", query: ["weekStart": weekStart, "tz": tz])
    }

    /// `GET /api/digest/suspects?weekStart&symptom&tz`
    func suspects(weekStart: String, symptom: String?, tz: String) async throws -> SuspectsDigest {
        try await request(.get, "/api/digest/suspects", query: ["weekStart": weekStart, "symptom": symptom, "tz": tz])
    }

    /// `GET /api/insights/triggers?dimension&symptom&minConfidence`
    func triggerInsights(dimension: String, symptom: String?, minConfidence: Int?) async throws -> TriggerInsights {
        try await request(.get, "/api/insights/triggers", query: [
            "dimension": dimension, "symptom": symptom, "minConfidence": minConfidence.map(String.init),
        ])
    }

    func watchlist() async throws -> [WatchlistItem] {
        try await request(.get, "/api/watchlist")
    }

    func addToWatchlist(_ ingredient: String, source: String = "manual") async throws -> WatchlistItem {
        struct Body: Encodable { let ingredient: String; let source: String }
        return try await request(.post, "/api/watchlist", body: Body(ingredient: ingredient, source: source))
    }

    func removeFromWatchlist(id: Int) async throws {
        try await requestVoid(.delete, "/api/watchlist/\(id)")
    }
}
