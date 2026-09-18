import Foundation

/// A saved dish tile: name, emoji stamp and remembered ingredients.
public struct Dish: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let userId: String?
    public var name: String
    public var emoji: String
    public var ingredients: [IngredientDetail]
    public var containsGluten: Bool?
    public var containsDairy: Bool?
    public var containsGrains: Bool?
    public var containsSugar: Bool?
    public var containsNuts: Bool?
    public var timesLogged: Int
    public var lastLoggedAt: Date?
    public let createdAt: Date?
    public var updatedAt: Date?

    public var ingredientNames: [String] { ingredients.map(\.name) }
}

public struct NewDish: Encodable, Sendable {
    public var name: String
    public var emoji: String
    public var ingredients: [IngredientDetail]
    public var containsGluten: Bool
    public var containsDairy: Bool
    public var containsGrains: Bool
    public var containsSugar: Bool
    public var containsNuts: Bool

    public init(name: String, emoji: String, ingredients: [IngredientDetail], containsGluten: Bool = false, containsDairy: Bool = false, containsGrains: Bool = false, containsSugar: Bool = false, containsNuts: Bool = false) {
        self.name = name; self.emoji = emoji; self.ingredients = ingredients
        self.containsGluten = containsGluten; self.containsDairy = containsDairy; self.containsGrains = containsGrains
        self.containsSugar = containsSugar; self.containsNuts = containsNuts
    }
}

public struct DishPatch: Encodable, Sendable {
    public var name: String?
    public var emoji: String?
    public var ingredients: [IngredientDetail]?
    public var containsGluten: Bool?
    public var containsDairy: Bool?
    public var containsGrains: Bool?
    public var containsSugar: Bool?
    public var containsNuts: Bool?
    public init(name: String? = nil, emoji: String? = nil, ingredients: [IngredientDetail]? = nil, containsGluten: Bool? = nil, containsDairy: Bool? = nil, containsGrains: Bool? = nil, containsSugar: Bool? = nil, containsNuts: Bool? = nil) {
        self.name = name; self.emoji = emoji; self.ingredients = ingredients
        self.containsGluten = containsGluten; self.containsDairy = containsDairy; self.containsGrains = containsGrains
        self.containsSugar = containsSugar; self.containsNuts = containsNuts
    }
}

/// Body of `POST /api/dishes/:id/log`.
public struct LogDishRequest: Encodable, Sendable {
    public struct Overrides: Encodable, Sendable {
        public var ingredientDetails: [IngredientDetail]?
        public init(ingredientDetails: [IngredientDetail]? = nil) { self.ingredientDetails = ingredientDetails }
    }
    public var mealType: MealType
    public var timestamp: Date
    public var tz: String
    public var notes: String?
    public var overrides: Overrides?
    public init(mealType: MealType, timestamp: Date, tz: String, notes: String? = nil, overrides: Overrides? = nil) {
        self.mealType = mealType; self.timestamp = timestamp; self.tz = tz; self.notes = notes; self.overrides = overrides
    }
}
