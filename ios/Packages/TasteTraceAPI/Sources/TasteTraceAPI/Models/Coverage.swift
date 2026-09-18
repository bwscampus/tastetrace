import Foundation

/// `GET /api/coverage` — today's slots, streak and the trailing week.
public struct Coverage: Codable, Equatable, Sendable {
    public struct SlotStatus: Codable, Equatable, Sendable {
        public let logged: Bool
        public let mealId: Int?
        public let time: String?
    }

    public struct Streak: Codable, Equatable, Sendable {
        public let days: Int
        public let threshold: Int
        public let rule: String
        public let todayCounts: Bool
    }

    public struct DayCoverage: Codable, Equatable, Identifiable, Sendable {
        public let date: String
        public let weekday: String
        public let meals: Int
        public let slotsLogged: Int
        public let metThreshold: Bool
        public var id: String { date }
    }

    public struct SlotTally: Codable, Equatable, Sendable {
        public let logged: Int
        public let total: Int
    }

    public struct WeekSlots: Codable, Equatable, Sendable {
        public let logged: Int
        public let total: Int
        public let bySlot: [String: SlotTally]
    }

    public struct Nudge: Codable, Equatable, Sendable {
        public let time: String
        public let enabled: Bool
    }

    public let date: String
    public let slots: [String: SlotStatus]
    public let loggedCount: Int
    public let slotTotal: Int
    public let percent: Int
    public let streak: Streak
    public let week: [DayCoverage]
    public let weekSlots: WeekSlots
    public let nudge: Nudge

    public var fraction: Double { slotTotal == 0 ? 0 : Double(loggedCount) / Double(slotTotal) }
}
