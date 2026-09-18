import Foundation

public extension APIClient {
    func dishes() async throws -> [Dish] {
        try await request(.get, "/api/dishes")
    }

    func createDish(_ dish: NewDish) async throws -> Dish {
        try await request(.post, "/api/dishes", body: dish)
    }

    func updateDish(id: Int, _ patch: DishPatch) async throws -> Dish {
        try await request(.put, "/api/dishes/\(id)", body: patch)
    }

    func deleteDish(id: Int) async throws {
        try await requestVoid(.delete, "/api/dishes/\(id)")
    }

    /// Logs a meal from a saved tile and returns the created meal.
    func logDish(id: Int, _ body: LogDishRequest) async throws -> Meal {
        try await request(.post, "/api/dishes/\(id)/log", body: body)
    }
}
