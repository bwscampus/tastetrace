import Foundation

/// `GET /api/foods/occurrences`: every logged meal containing a food, newest first.
public struct FoodOccurrences: Codable, Equatable, Sendable {
    public struct SymptomAfter: Codable, Equatable, Sendable {
        public let name: String
        public let at: Date
        public let onsetHours: Double
    }

    public struct Occurrence: Codable, Equatable, Identifiable, Sendable {
        public let mealId: Int
        public let mealName: String
        public let mealType: String
        public let mealAt: Date
        public let date: String
        public let matched: [String]
        public let symptomsAfter: [SymptomAfter]
        public var id: Int { mealId }
    }

    public let query: String
    public let windowHours: Int
    public let total: Int
    public let withSymptoms: Int
    public let occurrences: [Occurrence]
}
