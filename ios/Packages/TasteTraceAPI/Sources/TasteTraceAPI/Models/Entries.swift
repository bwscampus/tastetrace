import Foundation

/// `GET /api/entries/date` — everything logged on one local day.
public struct DayEntries: Codable, Equatable, Sendable {
    public let date: String
    public var meals: [Meal]
    public var symptoms: [Symptom]
    public var flares: Int?
    public var entries: Int?

    public init(date: String, meals: [Meal], symptoms: [Symptom], flares: Int? = nil, entries: Int? = nil) {
        self.date = date; self.meals = meals; self.symptoms = symptoms; self.flares = flares; self.entries = entries
    }

    /// Meals and symptoms interleaved by time.
    public var timeline: [TimelineItem] {
        (meals.map(TimelineItem.meal) + symptoms.map(TimelineItem.symptom)).sorted { $0.timestamp < $1.timestamp }
    }
}

public enum TimelineItem: Equatable, Identifiable, Sendable {
    case meal(Meal)
    case symptom(Symptom)

    public var id: String {
        switch self {
        case .meal(let meal): return "meal-\(meal.id)"
        case .symptom(let symptom): return "symptom-\(symptom.id)"
        }
    }

    public var timestamp: Date {
        switch self {
        case .meal(let meal): return meal.timestamp
        case .symptom(let symptom): return symptom.timestamp
        }
    }
}

/// Foods logged as one meal. Each food is still its own entry on the server so
/// its ingredients are tracked separately; this only puts them on one card.
public struct MealGroup: Equatable, Identifiable, Sendable {
    /// Oldest first; never empty.
    public let meals: [Meal]

    public init(meals: [Meal]) { self.meals = meals }

    public var id: String { "meals-\(meals[0].id)" }
    public var mealType: String { meals[0].mealType }
    public var timestamp: Date { meals[0].timestamp }
}

/// A timeline row once a meal's foods are put together.
public enum DayItem: Equatable, Identifiable, Sendable {
    case meals(MealGroup)
    case symptom(Symptom)

    public var id: String {
        switch self {
        case .meals(let group): return group.id
        case .symptom(let symptom): return "symptom-\(symptom.id)"
        }
    }

    public var timestamp: Date {
        switch self {
        case .meals(let group): return group.timestamp
        case .symptom(let symptom): return symptom.timestamp
        }
    }
}

extension DayEntries {
    /// The timeline with each meal's foods on one row: all of the day's Breakfast,
    /// Lunch or Dinner foods go together, and snacks when logged at the same time.
    public var groupedTimeline: [DayItem] {
        var groups: [[Meal]] = []
        for meal in meals.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let index = groups.firstIndex(where: { Self.sameMeal($0[0], meal) }) {
                groups[index].append(meal)
            } else {
                groups.append([meal])
            }
        }
        let items = groups.map { DayItem.meals(MealGroup(meals: $0)) } + symptoms.map(DayItem.symptom)
        return items.sorted { $0.timestamp < $1.timestamp }
    }

    static func sameMeal(_ a: Meal, _ b: Meal) -> Bool {
        guard a.mealType == b.mealType else { return false }
        return a.mealType != MealType.snack.rawValue || a.timestamp == b.timestamp
    }
}

/// `GET /api/entries/markers` — per-day counts for calendar decoration.
public struct DayMarker: Codable, Equatable, Sendable {
    public let meals: Int
    public let symptoms: Int
    public var maxIntensity: Int?
    public var status: String?

    public init(meals: Int, symptoms: Int, maxIntensity: Int? = nil, status: String? = nil) {
        self.meals = meals; self.symptoms = symptoms; self.maxIntensity = maxIntensity; self.status = status
    }
}

public typealias Markers = [String: DayMarker]
