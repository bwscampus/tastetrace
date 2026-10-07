import Foundation
import UserNotifications
import TasteTraceAPI
import TasteTraceCore

/// Schedules the daily nudge and optional meal check-ins as local notifications.
/// Each check-in fires `checkInDelayMinutes` after the user's usual meal time.
public final class ReminderScheduler: @unchecked Sendable {
    private let center: UNUserNotificationCenter?
    static let nudgeId = "tastetrace.nudge"
    static let checkInIds = ["tastetrace.checkin.breakfast", "tastetrace.checkin.lunch", "tastetrace.checkin.dinner"]
    static let checkInSlots = ["breakfast", "lunch", "dinner"]
    static let checkInDelayMinutes = 30

    public init(center: UNUserNotificationCenter? = ReminderScheduler.defaultCenter) {
        self.center = center
    }

    /// The notification center is unavailable outside an app bundle (e.g. `swift test`).
    ///
    /// Checking for an actual `.app` is what works: under `swift test` the main
    /// bundle is the xctest binary, which *has* an identifier, so testing for a
    /// nil identifier let `current()` be called and it trapped with
    /// "bundleProxyForCurrentProcess is nil" the moment anything built an
    /// AppEnvironment in a test.
    public static var defaultCenter: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
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
            for (index, time) in Self.checkInTimes(for: settings).enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "Log your \(time.slot)?"
                content.body = "Tap to record what you ate and keep your coverage streak alive."
                content.sound = .default
                try? await center.add(UNNotificationRequest(identifier: Self.checkInIds[index], content: content, trigger: Self.dailyTrigger(hour: time.hour, minute: time.minute, math: math)))
            }
        }
        return true
    }

    /// Cancels every pending and delivered reminder. Called when the session
    /// ends, so a signed-out or deleted account stops getting nudges.
    public func cancelAll() {
        center?.removeAllPendingNotificationRequests()
        center?.removeAllDeliveredNotifications()
    }

    /// Cancels the check-in for a slot that has already been logged today.
    public func cancelCheckIn(for slot: String) {
        guard let index = Self.checkInSlots.firstIndex(of: slot) else { return }
        center?.removePendingNotificationRequests(withIdentifiers: [Self.checkInIds[index]])
    }

    /// Breakfast, lunch and dinner check-in times: the saved meal time plus the delay.
    public static func checkInTimes(for settings: UserSettings) -> [(hour: Int, minute: Int, slot: String)] {
        let mealTimes = [settings.breakfastTime, settings.lunchTime, settings.dinnerTime]
        let fallbacks = [(9, 0), (13, 0), (19, 0)]
        return checkInSlots.indices.map { index in
            let (hour, minute) = parse(mealTimes[index]) ?? fallbacks[index]
            let total = (hour * 60 + minute + checkInDelayMinutes) % (24 * 60)
            return (hour: total / 60, minute: total % 60, slot: checkInSlots[index])
        }
    }

    /// "9:30 • 13:30 • 19:30" for the settings screens.
    public static func checkInSummary(for settings: UserSettings) -> String {
        checkInTimes(for: settings).map { String(format: "%d:%02d", $0.hour, $0.minute) }.joined(separator: " • ")
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
