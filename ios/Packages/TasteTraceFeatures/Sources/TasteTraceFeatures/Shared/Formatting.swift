import Foundation
import TasteTraceCore

enum Formatting {
    static func time(_ date: Date, math: DateMath) -> String {
        let formatter = DateFormatter()
        formatter.calendar = math.calendar
        formatter.timeZone = math.timeZone
        formatter.dateFormat = "hh:mm a"
        return formatter.string(from: date)
    }

    /// "Thursday, Oct 23, 2024"
    static func longDay(_ date: Date, math: DateMath) -> String {
        let formatter = DateFormatter()
        formatter.calendar = math.calendar
        formatter.timeZone = math.timeZone
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: date)
    }

    /// "Thu, Oct 23"
    static func shortDay(_ date: Date, math: DateMath) -> String {
        let formatter = DateFormatter()
        formatter.calendar = math.calendar
        formatter.timeZone = math.timeZone
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    /// "TODAY • SEP 17"
    static func todayHeader(_ date: Date, math: DateMath) -> String {
        let formatter = DateFormatter()
        formatter.calendar = math.calendar
        formatter.timeZone = math.timeZone
        formatter.dateFormat = "MMM d"
        return "Today • \(formatter.string(from: date))".uppercased()
    }

    /// "October 2024"
    static func monthYear(_ date: Date, math: DateMath) -> String {
        let formatter = DateFormatter()
        formatter.calendar = math.calendar
        formatter.timeZone = math.timeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    static func joinedList(_ items: [String], max: Int = 4) -> String {
        let shown = items.prefix(max).map { $0.capitalizedFirst }
        let rest = items.count - shown.count
        return rest > 0 ? shown.joined(separator: ", ") + " +\(rest)" : shown.joined(separator: ", ")
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
