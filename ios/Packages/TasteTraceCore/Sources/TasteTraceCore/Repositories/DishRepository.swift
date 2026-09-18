import Foundation
import TasteTraceAPI

/// Saved dish tiles, cached so the Log Meal screen opens instantly.
public actor DishRepository {
    private let client: APIClient
    private let cache: JSONFileStore<[Dish]>

    public init(client: APIClient, cacheDirectory: URL = JSONFileStore<[Dish]>.defaultDirectory) {
        self.client = client
        self.cache = JSONFileStore(name: "dishes", directory: cacheDirectory)
    }

    public func cached() -> [Dish] { cache.load() ?? [] }

    public func refresh() async throws -> [Dish] {
        do {
            let dishes = try await client.dishes()
            try? cache.save(dishes)
            return dishes
        } catch APIError.transport {
            if let cached = cache.load() { return cached }
            throw APIError.transport("Offline and no cached dishes")
        }
    }

    public func create(_ dish: NewDish) async throws -> Dish {
        let created = try await client.createDish(dish)
        try? cache.save([created] + cached())
        return created
    }

    public func update(id: Int, _ patch: DishPatch) async throws -> Dish {
        let updated = try await client.updateDish(id: id, patch)
        try? cache.save(cached().map { $0.id == id ? updated : $0 })
        return updated
    }

    public func delete(id: Int) async throws {
        try await client.deleteDish(id: id)
        try? cache.save(cached().filter { $0.id != id })
    }

    public func log(id: Int, _ request: LogDishRequest) async throws -> Meal {
        let meal = try await client.logDish(id: id, request)
        // Move the tile to the front, as the server sorts by last logged
        var dishes = cached()
        if let index = dishes.firstIndex(where: { $0.id == id }) {
            var dish = dishes.remove(at: index)
            dish.timesLogged += 1
            dish.lastLoggedAt = request.timestamp
            dishes.insert(dish, at: 0)
            try? cache.save(dishes)
        }
        return meal
    }
}
