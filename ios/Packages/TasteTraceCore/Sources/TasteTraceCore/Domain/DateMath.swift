import Foundation

/// Calendar helpers that always work in one explicit timezone, matching the
/// backend's `tz` parameter.
public struct DateMath: Sendable {
    public let timeZone: TimeZone
    public let calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2 // Monday, as in the History week strip
        self.calendar = calendar
    }

    public var tzIdentifier: String { timeZone.identifier }

    private static let dayFormatterCache = NSCache<NSString, DateFormatter>()

    private var dayFormatter: DateFormatter {
        if let cached = Self.dayFormatterCache.object(forKey: timeZone.identifier as NSString) { return cached }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        Self.dayFormatterCache.setObject(formatter, forKey: timeZone.identifier as NSString)
        return formatter
    }

    /// "YYYY-MM-DD" for an instant.
    public func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }

    /// Start of the local day for a "YYYY-MM-DD" string.
    public func date(fromDay day: String) -> Date? { dayFormatter.date(from: day) }

    public func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    public func endOfDay(_ date: Date) -> Date {
        calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay(date))!
    }

    public func addingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    /// Monday..Sunday containing `date`.
    public func week(containing date: Date) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        return (0..<7).map { addingDays($0, to: start) }
    }

    /// The 7 days ending on `date` (for digests: weekStart = date - 6).
    public func trailingWeek(endingOn date: Date) -> [Date] {
        (0..<7).reversed().map { addingDays(-$0, to: startOfDay(date)) }
    }

    public func isSameDay(_ a: Date, _ b: Date) -> Bool { calendar.isDate(a, inSameDayAs: b) }

    /// Short weekday label ("Fri").
    public func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    /// Combines a calendar day with a wall-clock time.
    public func combine(day: Date, time: Date) -> Date {
        let d = calendar.dateComponents([.year, .month, .day], from: day)
        let t = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: t.hour, minute: t.minute))!
    }
}
