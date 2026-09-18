import Foundation
import Observation
import TasteTraceAPI
import TasteTraceCore

/// Dietary flags shown as the "quick sensitivity filter" chips.
enum SensitivityFlag: String, CaseIterable, Identifiable {
    case gluten = "Gluten", sugar = "Sugar", dairy = "Dairy", grain = "Grain", nuts = "Nuts"
    var id: String { rawValue }
    var emoji: String {
        switch self {
        case .gluten: return "🌾"
        case .sugar: return "🍬"
        case .dairy: return "🥛"
        case .grain: return "🌾"
        case .nuts: return "🥜"
        }
    }
}

/// State for the two-step Log a Meal flow and the save-dish sheet.
@Observable
@MainActor
final class LogMealViewModel {
    enum Step: Hashable { case verify }

    // Step 1
    var day: Date
    var time: Date
    var mealType: MealType
    var flags: Set<SensitivityFlag> = []
    var dishes: [Dish] = []
    var recipeName = ""
    var path: [Step] = []

    // Step 2
    var dishName = ""
    var ingredientInput = ""
    var ingredients: [IngredientDetail] = []
    var notes = ""
    /// Ingredients on the user's watchlist found in this meal (M5 wires the list).
    var watchlist: [String] = []

    // Save sheet
    var showSaveSheet = false
    var stampEmoji = "🥗"
    static let stampOptions = ["🥗", "🍣", "🥣", "🥑", "⭐", "🍛", "🍕", "🥪", "🍜", "🥩", "🍳", "🍎"]

    var isBusy = false
    var error: String?
    var completed = false

    private let env: AppEnvironment

    init(env: AppEnvironment, date: Date) {
        self.env = env
        let now = Date()
        let math = env.dateMath
        let isToday = math.isSameDay(date, now)
        let initialTime = isToday ? now : math.combine(day: date, time: math.calendar.date(bySettingHour: 12, minute: 30, second: 0, of: now)!)
        day = math.startOfDay(date)
        time = initialTime
        mealType = Self.defaultMealType(hour: math.calendar.component(.hour, from: initialTime))
    }

    static func defaultMealType(hour: Int) -> MealType {
        switch hour {
        case ..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }

    var math: DateMath { env.dateMath }
    var timestamp: Date { math.combine(day: day, time: time) }
    var canConfigure: Bool { !recipeName.trimmingCharacters(in: .whitespaces).isEmpty }
    var watchlistHits: [String] { watchlistMatches(watchlist: watchlist, ingredients: ingredients.map(\.name)) }

    func loadDishes() async {
        watchlist = await env.watchlist.ingredients()
        dishes = await env.dishes.cached()
        if let fresh = try? await env.run({ try await env.dishes.refresh() }) { dishes = fresh }
    }

    /// "Write new recipe" → step 2 with the typed name.
    func configureRecipe() {
        dishName = recipeName.trimmingCharacters(in: .whitespaces)
        path = [.verify]
    }

    func addIngredients() {
        for name in parseIngredientInput(ingredientInput, existing: ingredients.map(\.name)) {
            ingredients.append(IngredientDetail(name: name))
        }
        ingredientInput = ""
    }

    func remove(_ ingredient: IngredientDetail) {
        ingredients.removeAll { $0 == ingredient }
    }

    func setCookMethod(_ method: CookMethod?, for ingredient: IngredientDetail) {
        guard let index = ingredients.firstIndex(of: ingredient) else { return }
        ingredients[index].cookMethod = method?.rawValue
    }

    /// Tapping a tile logs it immediately with the chosen category and time.
    func logTile(_ dish: Dish) async {
        await perform {
            _ = try await env.run {
                try await env.dishes.log(id: dish.id, LogDishRequest(mealType: mealType, timestamp: timestamp, tz: math.tzIdentifier))
            }
        }
    }

    func deleteTile(_ dish: Dish) async {
        do {
            try await env.run { try await env.dishes.delete(id: dish.id) }
            dishes.removeAll { $0.id == dish.id }
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }

    /// Finishes the flow, optionally saving the recipe as a tile first.
    func complete(saveAsDish: Bool) async {
        let name = dishName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { error = "Give the dish a name."; return }
        await perform {
            var dishId: Int?
            if saveAsDish {
                let dish = try await env.run {
                    try await env.dishes.create(NewDish(name: name, emoji: stampEmoji, ingredients: ingredients,
                                                        containsGluten: flags.contains(.gluten), containsDairy: flags.contains(.dairy),
                                                        containsGrains: flags.contains(.grain), containsSugar: flags.contains(.sugar),
                                                        containsNuts: flags.contains(.nuts)))
                }
                dishId = dish.id
            }
            _ = try await env.run {
                try await env.api.createMeal(NewMeal(name: name, mealType: mealType, timestamp: timestamp, tz: math.tzIdentifier,
                                                     notes: notes.isEmpty ? nil : notes, ingredientDetails: ingredients, dishId: dishId,
                                                     containsGluten: flags.contains(.gluten), containsDairy: flags.contains(.dairy),
                                                     containsGrains: flags.contains(.grain), containsSugar: flags.contains(.sugar),
                                                     containsNuts: flags.contains(.nuts)))
            }
            await env.entries.invalidate(math.dayString(timestamp))
        }
    }

    func updateDish(id: Int, _ patch: DishPatch) async throws -> Dish {
        try await env.run { try await env.dishes.update(id: id, patch) }
    }

    private func perform(_ work: () async throws -> Void) async {
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await work()
            await env.entries.invalidate(math.dayString(timestamp))
            completed = true
        } catch let apiError as APIError {
            error = apiError.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
