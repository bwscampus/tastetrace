import Foundation

/// `GET /api/digest/weekly`
public struct WeeklyDigest: Codable, Equatable, Sendable {
    public struct DayTrend: Codable, Equatable, Identifiable, Sendable {
        public let date: String
        public let weekday: String
        public let index: Double
        public let occurrences: Int
        public let maxIntensity: Int
        public let level: String // zero | moderate | high
        public var id: String { date }
    }

    public struct Trends: Codable, Equatable, Sendable {
        public let index: Double
        public let baselineIndex: Double
        public let deltaVsBaselinePercent: Int
        public let previousWeekIndex: Double
        public let changeVsPreviousPercent: Int
        public let occurrences: Int
        public let flares: Int
        public let discomfortFreeDays: Int
        public let severeDays: Int
        public let severePeakDay: String?
        public let mealLogDepth: Double
        public let dataCompleteness: String
        public let days: [DayTrend]
    }

    public struct Distribution: Codable, Equatable, Identifiable, Sendable {
        public let name: String
        public let catalogKey: String?
        public let count: Int
        public let share: Double
        public var id: String { name }
    }

    public struct SymptomCard: Codable, Equatable, Identifiable, Sendable {
        public let name: String
        public let catalogKey: String?
        public let emoji: String?
        public let occurrences: Int
        public let shareOfWeek: Double
        public let avgSeverity10: Double
        public let avgDurationMinutes: Int?
        public let peakDay: String?
        public let vsBaseline: String // up | same | down
        public let topTriggers: [String]
        public var id: String { name }
    }

    public struct OnsetWindows: Codable, Equatable, Sendable {
        public let under1h: Int
        public let from1to3h: Int
        public let over3h: Int
        public let unmatched: Int
        public var total: Int { under1h + from1to3h + over3h + unmatched }
    }

    public struct Symptoms: Codable, Equatable, Sendable {
        public let total: Int
        public let baselinePerWeek: Double
        public let vsBaseline: String
        public let distinct: Int
        public let distribution: [Distribution]
        public let cards: [SymptomCard]
        public let onsetWindows: OnsetWindows
    }

    public let weekStart: String
    public let weekEnd: String
    public let previousWeekStart: String
    public let hasNextWeek: Bool
    public let trends: Trends
    public let symptoms: Symptoms
}

/// `GET /api/digest/suspects`
public struct SuspectsDigest: Codable, Equatable, Sendable {
    public struct Pair: Codable, Equatable, Identifiable, Sendable {
        public let mealId: Int
        public let mealName: String
        public let mealAt: Date
        public let flareAt: Date
        public let symptoms: [String]
        public let onsetHours: Double
        public var id: String { "\(mealId)-\(flareAt.timeIntervalSince1970)" }
    }

    public struct Suspect: Codable, Equatable, Identifiable, Sendable {
        public let name: String
        public let flaresWithIngredient: Int
        public let flaresTotal: Int
        public let share: Double
        public let avgOnsetHours: Double?
        public let timesLoggedThisWeek: Int
        public let exposuresAllTime: Int
        public let confidence: Int
        public var onWatchlist: Bool
        public let recentPairs: [Pair]
        public var id: String { name }
    }

    public struct SymptomFilter: Codable, Equatable, Identifiable, Sendable {
        public let name: String
        public let count: Int
        public var id: String { name }
    }

    public struct TimingWindow: Codable, Equatable, Sendable {
        public let flares: Int
        public let topIngredients: [String]
    }

    public struct TimingWindows: Codable, Equatable, Sendable {
        public let early: TimingWindow
        public let mid: TimingWindow
        public let late: TimingWindow

        enum CodingKeys: String, CodingKey {
            case early = "0to4h", mid = "4to12h", late = "12to24h"
        }
    }

    public let weekStart: String
    public let weekEnd: String
    public let windowHours: Int
    public let flares: Int
    public let mealsEvaluated: Int
    public let leadSuspect: String?
    public let symptomFilters: [SymptomFilter]
    public var ingredients: [Suspect]
    public let timingWindows: TimingWindows
}

/// `GET /api/insights/triggers`
public struct TriggerInsights: Codable, Equatable, Sendable {
    public struct SymptomCount: Codable, Equatable, Identifiable, Sendable {
        public let name: String
        public let emoji: String
        public let count: Int
        public var id: String { name }
    }

    public struct Evidence: Codable, Equatable, Identifiable, Sendable {
        public let mealId: Int
        public let mealName: String
        public let mealAt: Date
        public let symptomAt: Date
        public let onsetHours: Double
        public var id: String { "\(mealId)-\(symptomAt.timeIntervalSince1970)" }
    }

    public struct Card: Codable, Equatable, Identifiable, Sendable {
        public let item: String
        public let dimension: String
        public let symptomName: String
        public let confidence: Int
        public let tier: String // strong | likely | watch
        public let exposures: Int
        public let flareExposures: Int
        public let hitRate: Double
        public let baselineRate: Double?
        public let lift: Double?
        public let avgOnsetHours: Double?
        public let lastFlareAt: Date?
        public let evidence: [Evidence]
        public var id: String { "\(dimension)|\(item)|\(symptomName)" }
    }

    public let dimension: String
    public let minConfidence: Int
    public let windowHours: Int
    public let symptoms: [SymptomCount]
    public let cards: [Card]
    public let hiddenBelowThreshold: Int
}

public struct WatchlistItem: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let ingredient: String
    public let source: String
    public let createdAt: Date?
    public let confidenceMax: Int?
}
