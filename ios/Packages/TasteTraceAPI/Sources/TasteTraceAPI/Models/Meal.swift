import Foundation

public enum MealType: String, Codable, CaseIterable, Sendable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"
}

public struct IngredientDetail: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var cookMethod: String?
    public init(name: String, cookMethod: String? = nil) {
        self.name = name
        self.cookMethod = cookMethod
    }
}

public struct Meal: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let userId: String?
    public var name: String
    public var mealType: String
    public var timestamp: Date
    public var notes: String?
    public var isCustom: Bool?
    public var ingredients: [String]?
    public var ingredientDetails: [IngredientDetail]?
    public var dishId: Int?
    public var containsGluten: Bool?
    public var containsDairy: Bool?
    public var containsGrains: Bool?
    public var containsSugar: Bool?
    public var containsNuts: Bool?
    public var date: String
    /// Symptom names that followed this meal within the correlation window (M4+).
    public var suspiciousFor: [String]?
    public var suspicion: String?

    /// Ingredient names, preferring the detailed list.
    public var ingredientNames: [String] {
        if let details = ingredientDetails, !details.isEmpty { return details.map(\.name) }
        return ingredients ?? []
    }
}

public struct NewMeal: Encodable, Sendable {
    public var name: String
    public var mealType: MealType
    public var timestamp: Date
    public var tz: String
    public var notes: String?
    public var isCustom: Bool = true
    public var ingredientDetails: [IngredientDetail]
    public var dishId: Int?
    public var containsGluten: Bool = false
    public var containsDairy: Bool = false
    public var containsGrains: Bool = false
    public var containsSugar: Bool = false
    public var containsNuts: Bool = false

    public init(name: String, mealType: MealType, timestamp: Date, tz: String, notes: String? = nil, ingredientDetails: [IngredientDetail] = [], dishId: Int? = nil, containsGluten: Bool = false, containsDairy: Bool = false, containsGrains: Bool = false, containsSugar: Bool = false, containsNuts: Bool = false) {
        self.name = name; self.mealType = mealType; self.timestamp = timestamp; self.tz = tz; self.notes = notes
        self.ingredientDetails = ingredientDetails; self.dishId = dishId
        self.containsGluten = containsGluten; self.containsDairy = containsDairy; self.containsGrains = containsGrains
        self.containsSugar = containsSugar; self.containsNuts = containsNuts
    }
}

public struct MealPatch: Encodable, Sendable {
    public var name: String?
    public var mealType: MealType?
    public var timestamp: Date?
    public var tz: String?
    public var notes: String?
    public var ingredientDetails: [IngredientDetail]?
    public var containsGluten: Bool?
    public var containsDairy: Bool?
    public var containsGrains: Bool?
    public var containsSugar: Bool?
    public var containsNuts: Bool?
    public init(name: String? = nil, mealType: MealType? = nil, timestamp: Date? = nil, tz: String? = nil, notes: String? = nil, ingredientDetails: [IngredientDetail]? = nil, containsGluten: Bool? = nil, containsDairy: Bool? = nil, containsGrains: Bool? = nil, containsSugar: Bool? = nil, containsNuts: Bool? = nil) {
        self.name = name; self.mealType = mealType; self.timestamp = timestamp; self.tz = tz; self.notes = notes
        self.ingredientDetails = ingredientDetails; self.containsGluten = containsGluten; self.containsDairy = containsDairy
        self.containsGrains = containsGrains; self.containsSugar = containsSugar; self.containsNuts = containsNuts
    }
}
