import Foundation

public extension APIClient {
    func meals() async throws -> [Meal] {
        try await request(.get, "/api/meals")
    }

    func createMeal(_ meal: NewMeal) async throws -> Meal {
        try await request(.post, "/api/meals", body: meal)
    }

    func meal(id: Int) async throws -> Meal {
        try await request(.get, "/api/meals/\(id)")
    }

    func updateMeal(id: Int, _ patch: MealPatch) async throws -> Meal {
        try await request(.put, "/api/meals/\(id)", body: patch)
    }

    func deleteMeal(id: Int) async throws {
        try await requestVoid(.delete, "/api/meals/\(id)")
    }
}
