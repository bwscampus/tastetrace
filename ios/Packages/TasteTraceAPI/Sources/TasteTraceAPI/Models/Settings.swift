import Foundation

public struct UserSettings: Codable, Equatable, Sendable {
    public var timezone: String
    public var correlationWindowHours: Int
    public var minTriggerCount: Int
    public var minConfidence: Int
    public var streakMealsPerDay: Int
    public var nudgeTime: String
    public var nudgesEnabled: Bool
    public var mealCheckInsEnabled: Bool

    public init(timezone: String = "UTC", correlationWindowHours: Int = 24, minTriggerCount: Int = 2, minConfidence: Int = 50, streakMealsPerDay: Int = 2, nudgeTime: String = "20:30", nudgesEnabled: Bool = true, mealCheckInsEnabled: Bool = false) {
        self.timezone = timezone; self.correlationWindowHours = correlationWindowHours; self.minTriggerCount = minTriggerCount
        self.minConfidence = minConfidence; self.streakMealsPerDay = streakMealsPerDay; self.nudgeTime = nudgeTime
        self.nudgesEnabled = nudgesEnabled; self.mealCheckInsEnabled = mealCheckInsEnabled
    }
}

public struct SettingsPatch: Encodable, Sendable {
    public var timezone: String?
    public var correlationWindowHours: Int?
    public var minTriggerCount: Int?
    public var minConfidence: Int?
    public var streakMealsPerDay: Int?
    public var nudgeTime: String?
    public var nudgesEnabled: Bool?
    public var mealCheckInsEnabled: Bool?
    public init(timezone: String? = nil, correlationWindowHours: Int? = nil, minTriggerCount: Int? = nil, minConfidence: Int? = nil, streakMealsPerDay: Int? = nil, nudgeTime: String? = nil, nudgesEnabled: Bool? = nil, mealCheckInsEnabled: Bool? = nil) {
        self.timezone = timezone; self.correlationWindowHours = correlationWindowHours; self.minTriggerCount = minTriggerCount
        self.minConfidence = minConfidence; self.streakMealsPerDay = streakMealsPerDay; self.nudgeTime = nudgeTime
        self.nudgesEnabled = nudgesEnabled; self.mealCheckInsEnabled = mealCheckInsEnabled
    }
}
