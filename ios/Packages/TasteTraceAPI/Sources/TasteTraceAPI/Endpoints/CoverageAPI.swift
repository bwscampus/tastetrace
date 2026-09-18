import Foundation

public extension APIClient {
    /// `GET /api/coverage?date=YYYY-MM-DD&tz=…`
    func coverage(on date: String, tz: String) async throws -> Coverage {
        try await request(.get, "/api/coverage", query: ["date": date, "tz": tz])
    }
}
