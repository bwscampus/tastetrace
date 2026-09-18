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
