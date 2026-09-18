import Foundation
import UserNotifications
import TasteTraceAPI
import TasteTraceCore

/// Schedules the daily nudge and optional meal check-ins as local notifications.
public final class ReminderScheduler: @unchecked Sendable {
    private let center: UNUserNotificationCenter?
    static let nudgeId = "tastetrace.nudge"
    static let checkInIds = ["tastetrace.checkin.breakfast", "tastetrace.checkin.lunch", "tastetrace.checkin.dinner"]
    static let checkInTimes: [(hour: Int, minute: Int, slot: String)] = [(9, 30, "breakfast"), (13, 30, "lunch"), (19, 30, "dinner")]

    public init(center: UNUserNotificationCenter? = ReminderScheduler.defaultCenter) {
        self.center = center
    }

    /// The notification center is unavailable outside an app bundle (e.g. `swift test`).
    public static var defaultCenter: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    /// Re-creates the pending reminders from settings. Returns false when permission is denied.
    @discardableResult
    public func sync(settings: UserSettings, math: DateMath) async -> Bool {
        guard let center else { return false }
        center.removePendingNotificationRequests(withIdentifiers: [Self.nudgeId] + Self.checkInIds)
        guard settings.nudgesEnabled || settings.mealCheckInsEnabled else { return true }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }

        if settings.nudgesEnabled, let (hour, minute) = Self.parse(settings.nudgeTime) {
            let content = UNMutableNotificationContent()
            content.title = "Evening check-in 🍽️"
            content.body = "Anything from today still unlogged? A quick entry keeps your ledger complete."
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: Self.nudgeId, content: content, trigger: Self.dailyTrigger(hour: hour, minute: minute, math: math)))
        }

        if settings.mealCheckInsEnabled {
            for (index, time) in Self.checkInTimes.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "Log your \(time.slot)?"
                content.body = "Tap to record what you ate and keep your coverage streak alive."
                content.sound = .default
                try? await center.add(UNNotificationRequest(identifier: Self.checkInIds[index], content: content, trigger: Self.dailyTrigger(hour: time.hour, minute: time.minute, math: math)))
            }
        }
        return true
    }

    /// Cancels the check-in for a slot that has already been logged today.
    public func cancelCheckIn(for slot: String) {
        guard let index = Self.checkInTimes.firstIndex(where: { $0.slot == slot }) else { return }
        center?.removePendingNotificationRequests(withIdentifiers: [Self.checkInIds[index]])
    }

    static func dailyTrigger(hour: Int, minute: Int, math: DateMath) -> UNCalendarNotificationTrigger {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.timeZone = math.timeZone
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    }

    public static func parse(_ hhmm: String) -> (Int, Int)? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    public static func hhmm(from date: Date, math: DateMath) -> String {
        let c = math.calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 20, c.minute ?? 30)
    }

    public static func date(fromHHMM hhmm: String, math: DateMath) -> Date {
        let (hour, minute) = parse(hhmm) ?? (20, 30)
        return math.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
