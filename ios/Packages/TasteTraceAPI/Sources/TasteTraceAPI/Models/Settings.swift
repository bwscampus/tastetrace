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
    /// When the user usually eats ("HH:mm"); meal check-ins fire half an hour after.
    public var breakfastTime: String
    public var lunchTime: String
    public var dinnerTime: String

    public init(timezone: String = "UTC", correlationWindowHours: Int = 24, minTriggerCount: Int = 2, minConfidence: Int = 50, streakMealsPerDay: Int = 2, nudgeTime: String = "20:30", nudgesEnabled: Bool = true, mealCheckInsEnabled: Bool = false, breakfastTime: String = "09:00", lunchTime: String = "13:00", dinnerTime: String = "19:00") {
        self.timezone = timezone; self.correlationWindowHours = correlationWindowHours; self.minTriggerCount = minTriggerCount
        self.minConfidence = minConfidence; self.streakMealsPerDay = streakMealsPerDay; self.nudgeTime = nudgeTime
        self.nudgesEnabled = nudgesEnabled; self.mealCheckInsEnabled = mealCheckInsEnabled
        self.breakfastTime = breakfastTime; self.lunchTime = lunchTime; self.dinnerTime = dinnerTime
    }

    enum CodingKeys: String, CodingKey {
        case timezone, correlationWindowHours, minTriggerCount, minConfidence, streakMealsPerDay
        case nudgeTime, nudgesEnabled, mealCheckInsEnabled, breakfastTime, lunchTime, dinnerTime
    }

    /// Meal times fall back to the defaults so settings cached by an older build still decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timezone = try c.decode(String.self, forKey: .timezone)
        correlationWindowHours = try c.decode(Int.self, forKey: .correlationWindowHours)
        minTriggerCount = try c.decode(Int.self, forKey: .minTriggerCount)
        minConfidence = try c.decode(Int.self, forKey: .minConfidence)
        streakMealsPerDay = try c.decode(Int.self, forKey: .streakMealsPerDay)
        nudgeTime = try c.decode(String.self, forKey: .nudgeTime)
        nudgesEnabled = try c.decode(Bool.self, forKey: .nudgesEnabled)
        mealCheckInsEnabled = try c.decode(Bool.self, forKey: .mealCheckInsEnabled)
        breakfastTime = try c.decodeIfPresent(String.self, forKey: .breakfastTime) ?? "09:00"
        lunchTime = try c.decodeIfPresent(String.self, forKey: .lunchTime) ?? "13:00"
        dinnerTime = try c.decodeIfPresent(String.self, forKey: .dinnerTime) ?? "19:00"
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
    public var breakfastTime: String?
    public var lunchTime: String?
    public var dinnerTime: String?
    public init(timezone: String? = nil, correlationWindowHours: Int? = nil, minTriggerCount: Int? = nil, minConfidence: Int? = nil, streakMealsPerDay: Int? = nil, nudgeTime: String? = nil, nudgesEnabled: Bool? = nil, mealCheckInsEnabled: Bool? = nil, breakfastTime: String? = nil, lunchTime: String? = nil, dinnerTime: String? = nil) {
        self.timezone = timezone; self.correlationWindowHours = correlationWindowHours; self.minTriggerCount = minTriggerCount
        self.minConfidence = minConfidence; self.streakMealsPerDay = streakMealsPerDay; self.nudgeTime = nudgeTime
        self.nudgesEnabled = nudgesEnabled; self.mealCheckInsEnabled = mealCheckInsEnabled
        self.breakfastTime = breakfastTime; self.lunchTime = lunchTime; self.dinnerTime = dinnerTime
    }
}
