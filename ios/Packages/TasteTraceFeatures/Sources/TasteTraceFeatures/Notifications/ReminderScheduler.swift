import Foundation
import UserNotifications
import TasteTraceAPI
import TasteTraceCore

/// Schedules the daily nudge and optional meal check-ins as local notifications.
/// Each check-in fires `checkInDelayMinutes` after the user's usual meal time.
///
/// Check-ins are one-off notifications for each of the next `checkInDays` days
/// rather than one repeating one, so logging a meal can cancel just that day's
/// reminder. Every launch re-syncs, which keeps the window rolling forward.
public final class ReminderScheduler: @unchecked Sendable {
    private let center: UNUserNotificationCenter?
    static let nudgeId = "tastetrace.nudge"
    static let checkInPrefix = "tastetrace.checkin."
    /// The repeating check-ins earlier builds scheduled; removed on every sync.
    static let legacyCheckInIds = ["tastetrace.checkin.breakfast", "tastetrace.checkin.lunch", "tastetrace.checkin.dinner"]
    static let checkInSlots = ["breakfast", "lunch", "dinner"]
    static let checkInDelayMinutes = 15
    static let checkInDays = 7

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

    /// Re-creates the pending reminders from settings. `loggedToday` holds the
    /// slots ("lunch") already logged today, whose check-in is skipped.
    /// Returns false when permission is denied.
    @discardableResult
    public func sync(settings: UserSettings, math: DateMath, loggedToday: Set<String> = []) async -> Bool {
        guard let center else { return false }
        let scheduled = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.checkInPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: [Self.nudgeId] + Self.legacyCheckInIds + scheduled)
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
            for checkIn in Self.checkInSchedule(for: settings, from: Date(), math: math, loggedToday: loggedToday) {
                let content = UNMutableNotificationContent()
                content.title = "Log your \(checkIn.slot)?"
                content.body = "Tap to record what you ate and keep your coverage streak alive."
                content.sound = .default
                var components = math.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: checkIn.fireAt)
                components.timeZone = math.timeZone
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: checkIn.id, content: content, trigger: trigger))
            }
        }
        return true
    }

    /// The check-ins to schedule from `now`: one per slot for each of the next
    /// `checkInDays` days, leaving out any already past and today's for slots
    /// in `loggedToday`.
    static func checkInSchedule(for settings: UserSettings, from now: Date, math: DateMath, loggedToday: Set<String> = []) -> [(id: String, fireAt: Date, slot: String)] {
        let mealTimes = [settings.breakfastTime, settings.lunchTime, settings.dinnerTime]
        let fallbacks = [(9, 0), (13, 0), (19, 0)]
        let today = math.startOfDay(now)
        var schedule: [(id: String, fireAt: Date, slot: String)] = []
        for offset in 0..<checkInDays {
            let day = math.addingDays(offset, to: today)
            for (index, slot) in checkInSlots.enumerated() {
                if offset == 0 && loggedToday.contains(slot) { continue }
                let (hour, minute) = parse(mealTimes[index]) ?? fallbacks[index]
                guard let meal = math.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
                let fireAt = meal.addingTimeInterval(TimeInterval(checkInDelayMinutes * 60))
                if fireAt <= now { continue }
                schedule.append((id: checkInId(slot: slot, day: math.dayString(day)), fireAt: fireAt, slot: slot))
            }
        }
        return schedule
    }

    static func checkInId(slot: String, day: String) -> String { "\(checkInPrefix)\(slot).\(day)" }

    /// Cancels every pending and delivered reminder. Called when the session
    /// ends, so a signed-out or deleted account stops getting nudges.
    public func cancelAll() {
        center?.removeAllPendingNotificationRequests()
        center?.removeAllDeliveredNotifications()
    }

    /// Cancels a day's check-in once that meal is logged. `mealType` is the
    /// meal's category ("Lunch"); snacks and drinks have no check-in.
    public func cancelCheckIn(mealType: String, on day: String) {
        let slot = mealType.lowercased()
        guard Self.checkInSlots.contains(slot) else { return }
        center?.removePendingNotificationRequests(withIdentifiers: [Self.checkInId(slot: slot, day: day)])
        center?.removeDeliveredNotifications(withIdentifiers: [Self.checkInId(slot: slot, day: day)])
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
