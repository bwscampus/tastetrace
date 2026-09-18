import Foundation
import Observation

public enum AppTab: Hashable, CaseIterable {
    case today, history, digest, triggers

    public var title: String {
        switch self {
        case .today: return "Today"
        case .history: return "History"
        case .digest: return "Digest"
        case .triggers: return "Triggers"
        }
    }

    public var systemImage: String {
        switch self {
        case .today: return "book.fill"
        case .history: return "calendar"
        case .digest: return "chart.pie.fill"
        case .triggers: return "questionmark.square.fill"
        }
    }
}

/// Modal flows presented over the tabs.
public enum AppSheet: Identifiable, Hashable {
    case logMeal(date: Date)
    case quickLog(date: Date)
    case profile
    case notifications
    case editMeal(id: Int)
    case editSymptom(id: Int)
    case export(kind: String?, weekStart: Date?)

    public var id: String {
        switch self {
        case .logMeal: return "logMeal"
        case .quickLog: return "quickLog"
        case .profile: return "profile"
        case .notifications: return "notifications"
        case .editMeal(let id): return "editMeal-\(id)"
        case .editSymptom(let id): return "editSymptom-\(id)"
        case .export(let kind, _): return "export-\(kind ?? "csv")"
        }
    }
}

/// Pushed destinations inside a tab.
public enum Route: Hashable {
    case coverage(date: Date)
    case digest(weekStart: Date)
    case suspects(weekStart: Date)
    case symptomDigest(weekStart: Date)
}

@Observable
@MainActor
public final class Router {
    public var tab: AppTab = .today
    public var sheet: AppSheet?
    public var todayPath: [Route] = []
    public var historyPath: [Route] = []
    public var digestPath: [Route] = []
    public var triggersPath: [Route] = []
    /// Day the History tab should show when switched to.
    public var historyDate: Date?

    public init() {}

    public func showHistory(on date: Date) {
        historyDate = date
        tab = .history
    }

    public func showDigest(weekStart: Date) {
        digestPath = [.digest(weekStart: weekStart)]
        tab = .digest
    }
}
