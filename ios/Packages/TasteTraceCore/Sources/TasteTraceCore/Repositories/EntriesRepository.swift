import Foundation
import TasteTraceAPI

/// Day entries and calendar markers, API-first with a per-day file cache so
/// History and Today still render offline.
public actor EntriesRepository {
    private let client: APIClient
    private let cacheDirectory: URL
    private var markerCache = JSONFileStore<Markers>(name: "markers")

    public init(client: APIClient, cacheDirectory: URL = JSONFileStore<DayEntries>.defaultDirectory) {
        self.client = client
        self.cacheDirectory = cacheDirectory
        self.markerCache = JSONFileStore<Markers>(name: "markers", directory: cacheDirectory)
    }

    private func dayStore(_ date: String) -> JSONFileStore<DayEntries> {
        JSONFileStore(name: "day-\(date)", directory: cacheDirectory)
    }

    public struct Loaded<T> {
        public let value: T
        public let fromCache: Bool
    }

    public func day(_ date: String, tz: String) async throws -> Loaded<DayEntries> {
        do {
            let entries = try await client.entries(on: date, tz: tz)
            try? dayStore(date).save(entries)
            return Loaded(value: entries, fromCache: false)
        } catch APIError.transport {
            if let cached = dayStore(date).load() { return Loaded(value: cached, fromCache: true) }
            throw APIError.transport("Offline and no cached entries for \(date)")
        }
    }

    public func markers(from start: Date, to end: Date, tz: String) async throws -> Loaded<Markers> {
        do {
            let fresh = try await client.markers(from: start, to: end, tz: tz)
            var merged = markerCache.load() ?? [:]
            merged.merge(fresh) { _, new in new }
            try? markerCache.save(merged)
            return Loaded(value: fresh, fromCache: false)
        } catch APIError.transport {
            if let cached = markerCache.load() { return Loaded(value: cached, fromCache: true) }
            throw APIError.transport("Offline and no cached markers")
        }
    }

    public func deleteMeal(id: Int, on date: String) async throws {
        try await client.deleteMeal(id: id)
        invalidate(date)
    }

    public func deleteSymptom(id: Int, on date: String) async throws {
        try await client.deleteSymptom(id: id)
        invalidate(date)
    }

    public func invalidate(_ date: String) {
        dayStore(date).clear()
    }
}
