import Foundation

public extension APIClient {
    /// `GET /api/entries/date?date=YYYY-MM-DD&tz=…`
    func entries(on date: String, tz: String) async throws -> DayEntries {
        try await request(.get, "/api/entries/date", query: ["date": date, "tz": tz])
    }

    /// `GET /api/entries/markers?start&end&tz` — `start`/`end` are instants.
    func markers(from start: Date, to end: Date, tz: String) async throws -> Markers {
        try await request(.get, "/api/entries/markers", query: [
            "start": ISO8601Formatters.plain.string(from: start),
            "end": ISO8601Formatters.plain.string(from: end),
            "tz": tz,
        ])
    }
}
