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

/// One food in the meal being logged ("Pasta", "Side salad"), with its own ingredients.
struct MealItem: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var emoji: String
    var ingredients: [IngredientDetail]
    /// Text typed into this food's ingredient box, not yet added.
    var ingredientInput = ""
    /// Set when the food came from a saved tile.
    var dishId: Int?
    /// The tile's name and ingredients as saved, to tell whether they were edited for this meal.
    var savedName: String?
    var savedIngredients: [IngredientDetail]?
    /// New foods only: also save as a one-tap tile.
    var saveAsTile = false
    /// Already sent to the server, so a retry after a partial failure skips it.
    var logged = false

    init(name: String, emoji: String = "🍽️", ingredients: [IngredientDetail] = []) {
        self.name = name
        self.emoji = emoji
        self.ingredients = ingredients
    }

    init(dish: Dish) {
        self.init(name: dish.name, emoji: dish.emoji, ingredients: dish.ingredients)
        dishId = dish.id
        savedName = dish.name
        savedIngredients = dish.ingredients
    }

    var isFromTile: Bool { dishId != nil }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
}

/// State for the two-step Log a Meal flow: pick the foods, then their ingredients.
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
    /// Name typed in "Add a food" before it is added to the meal.
    var newFoodName = ""
    var path: [Step] = []

    /// Every food in this meal, tiles and new foods alike.
    var items: [MealItem] = []
    var notes = ""
    /// Ingredients on the user's watchlist found in this meal.
    var watchlist: [String] = []

    // Save sheet, shown when the meal has new foods that could become tiles
    var showSaveSheet = false
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
    var canAddFood: Bool { !newFoodName.trimmingCharacters(in: .whitespaces).isEmpty }
    /// Step 1 can move on with foods picked, or a typed name that will be added.
    var canContinue: Bool { !items.isEmpty || canAddFood }
    var canComplete: Bool { !items.isEmpty && items.allSatisfy { !$0.trimmedName.isEmpty } && !isBusy }
    var newFoods: [MealItem] { items.filter { !$0.isFromTile } }
    var watchlistHits: [String] {
        watchlistMatches(watchlist: watchlist, ingredients: items.flatMap { $0.ingredients.map(\.name) })
    }

    func isSelected(_ dish: Dish) -> Bool { items.contains { $0.dishId == dish.id } }

    func loadDishes() async {
        watchlist = await env.watchlist.ingredients()
        dishes = await env.dishes.cached()
        if let fresh = try? await env.run({ try await env.dishes.refresh() }) { dishes = fresh }
    }

    /// Tapping a tile adds it to the meal; tapping again takes it out.
    func toggleTile(_ dish: Dish) {
        if let index = items.firstIndex(where: { $0.dishId == dish.id }) {
            items.remove(at: index)
        } else {
            items.append(MealItem(dish: dish))
        }
    }

    /// "Add a food" → a new food whose ingredients are entered on step 2.
    func addNewFood() {
        let name = newFoodName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var item = MealItem(name: name, emoji: Self.stampOptions[newFoods.count % Self.stampOptions.count])
        item.saveAsTile = true
        items.append(item)
        newFoodName = ""
    }

    func remove(_ item: MealItem) {
        items.removeAll { $0.id == item.id }
    }

    func goToIngredients() {
        if canAddFood { addNewFood() }
        guard !items.isEmpty else { return }
        path = [.verify]
    }

    /// Step 2's button: offer to save new foods as tiles, or log straight away.
    func reviewAndComplete() async {
        guard canComplete else { error = "Give every food a name."; return }
        if newFoods.isEmpty { await complete() } else { showSaveSheet = true }
    }

    func deleteTile(_ dish: Dish) async {
        do {
            try await env.run { try await env.dishes.delete(id: dish.id) }
            dishes.removeAll { $0.id == dish.id }
            items.removeAll { $0.dishId == dish.id }
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }

    /// Logs every food as its own entry at the same time and category, so each
    /// one's ingredients are tracked separately.
    func complete() async {
        guard canComplete else { error = "Give every food a name."; return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        let stamp = timestamp
        let note = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            for index in items.indices where !items[index].logged {
                try await log(itemAt: index, at: stamp, notes: note.isEmpty ? nil : note)
                items[index].logged = true
            }
            completed = true
        } catch let apiError as APIError {
            error = apiError.message
        } catch {
            self.error = error.localizedDescription
        }
        if items.contains(where: \.logged) { await env.entries.invalidate(math.dayString(stamp)) }
    }

    private func log(itemAt index: Int, at stamp: Date, notes: String?) async throws {
        let item = items[index]
        let name = item.trimmedName
        // The tile endpoint always uses the tile's name, so a renamed tile is logged as a regular meal below
        if let dishId = item.dishId, name == item.savedName {
            let overrides = item.ingredients != item.savedIngredients
                ? LogDishRequest.Overrides(ingredientDetails: item.ingredients) : nil
            _ = try await env.run {
                try await env.dishes.log(id: dishId, LogDishRequest(
                    mealType: mealType, timestamp: stamp, tz: math.tzIdentifier, notes: notes, overrides: overrides))
            }
            return
        }
        var dishId = item.dishId
        if dishId == nil && item.saveAsTile {
            let dish = try await env.run {
                try await env.dishes.create(NewDish(name: name, emoji: item.emoji, ingredients: item.ingredients,
                                                    containsGluten: flags.contains(.gluten), containsDairy: flags.contains(.dairy),
                                                    containsGrains: flags.contains(.grain), containsSugar: flags.contains(.sugar),
                                                    containsNuts: flags.contains(.nuts)))
            }
            dishId = dish.id
            dishes.append(dish)
            // If logging the meal below fails, a retry logs this new tile instead of creating it twice
            items[index].dishId = dish.id
            items[index].savedName = dish.name
            items[index].savedIngredients = dish.ingredients
        }
        _ = try await env.run {
            try await env.api.createMeal(NewMeal(name: name, mealType: mealType, timestamp: stamp, tz: math.tzIdentifier,
                                                 notes: notes, ingredientDetails: item.ingredients, dishId: dishId,
                                                 containsGluten: flags.contains(.gluten), containsDairy: flags.contains(.dairy),
                                                 containsGrains: flags.contains(.grain), containsSugar: flags.contains(.sugar),
                                                 containsNuts: flags.contains(.nuts)))
        }
    }

    func updateDish(id: Int, _ patch: DishPatch) async throws -> Dish {
        try await env.run { try await env.dishes.update(id: id, patch) }
    }
}
