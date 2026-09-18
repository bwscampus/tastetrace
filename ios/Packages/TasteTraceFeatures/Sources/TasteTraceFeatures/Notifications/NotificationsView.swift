import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

/// The bell: what's pending today and the scheduled reminders.
struct NotificationsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @State private var coverage: Coverage?
    @State private var settings: UserSettings?

    var body: some View {
        TTScreen {
            if let coverage {
                SectionLabel("Today")
                ForEach(MealSlot.allCases) { slot in
                    let logged = coverage.slots[slot.rawValue]?.logged ?? false
                    TTCard(padding: 12) {
                        HStack(spacing: 12) {
                            EmojiCircle(slot.emoji, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(logged ? "\(slot.rawValue) logged" : "\(slot.rawValue) still pending").font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                                Text(logged ? "Recorded at \(coverage.slots[slot.rawValue]?.time ?? "")" : "Tap to log it now").font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                            }
                            Spacer()
                            StatusBadge(logged ? "Done" : "Pending", tone: logged ? .success : .info)
                        }
                    }
                    .onTapGesture { if !logged { router.sheet = .logMeal(date: Date()) } }
                }
                if coverage.streak.days > 0 {
                    InfoBanner(emoji: "🔥", title: "\(coverage.streak.days)-day streak", message: coverage.streak.todayCounts ? "Today already counts." : "Log \(coverage.streak.threshold) meals today to keep it going.", tone: .success)
                }
            }
            if let settings {
                SectionLabel("Scheduled reminders")
                TTCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Post-dinner nudge").font(TTFont.bodySemibold).foregroundStyle(TTColor.navy); Spacer(); Text(settings.nudgesEnabled ? Formatting.clock(settings.nudgeTime) : "Off").font(TTFont.bodySemibold).foregroundStyle(TTColor.primary) }
                        HStack { Text("Meal check-ins").font(TTFont.bodySemibold).foregroundStyle(TTColor.navy); Spacer(); Text(settings.mealCheckInsEnabled ? "9:30 • 13:30 • 19:30" : "Off").font(TTFont.bodySemibold).foregroundStyle(TTColor.primary) }
                    }
                }
                Button("Change reminders") { router.sheet = .profile }.font(TTFont.bodySemibold).foregroundStyle(TTColor.primary).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Notifications")
        .task {
            coverage = try? await env.run { try await env.api.coverage(on: env.dateMath.dayString(Date()), tz: env.dateMath.tzIdentifier) }
            settings = try? await env.run { try await env.api.settings() }
        }
    }
}
