import Foundation
import TasteTraceAPI

/// The three coverage slots. Snacks are logged but don't count toward coverage.
public enum MealSlot: String, CaseIterable, Identifiable, Sendable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"

    public var id: String { rawValue }

    public var emoji: String {
        switch self {
        case .breakfast: return "🥣"
        case .lunch: return "🥗"
        case .dinner: return "🍛"
        }
    }

    public var mealType: MealType {
        switch self {
        case .breakfast: return .breakfast
        case .lunch: return .lunch
        case .dinner: return .dinner
        }
    }

    public static func slot(for mealType: String) -> MealSlot? { MealSlot(rawValue: mealType) }
}

public extension MealType {
    var emoji: String {
        switch self {
        case .breakfast: return "🥣"
        case .lunch: return "🥪"
        case .dinner: return "🍛"
        case .snack: return "🍎"
        }
    }

    var subtitle: String {
        switch self {
        case .breakfast: return "Morning log"
        case .lunch: return "Mid-day log"
        case .dinner: return "Evening log"
        case .snack: return "Between meals"
        }
    }
}
