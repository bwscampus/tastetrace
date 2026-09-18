import Foundation
import TasteTraceAPI

/// Cached watchlist used for on-device matching while logging a meal.
public actor WatchlistStore {
    private let cache: JSONFileStore<[WatchlistItem]>
    private var items: [WatchlistItem]

    public init(cacheDirectory: URL = JSONFileStore<[WatchlistItem]>.defaultDirectory) {
        cache = JSONFileStore(name: "watchlist", directory: cacheDirectory)
        items = cache.load() ?? []
    }

    public func ingredients() -> [String] { items.map(\.ingredient) }

    public func replace(_ fresh: [WatchlistItem]) {
        items = fresh
        try? cache.save(fresh)
    }
}

/// Watchlist entries that appear in the given ingredient names (substring, case-insensitive).
public func watchlistMatches(watchlist: [String], ingredients: [String]) -> [String] {
    let names = ingredients.map { $0.lowercased() }
    return watchlist.filter { item in names.contains { $0.contains(item.lowercased()) } }
}
