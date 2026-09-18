import Foundation
import Observation
import TasteTraceAPI
import TasteTraceCore

@Observable
@MainActor
final class TodayViewModel {
    var day: DayEntries?
    var isLoading = false
    var fromCache = false
    var error: String?
    var toast: String?

    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    var math: DateMath { env.dateMath }
    var today: Date { Date() }
    var todayString: String { math.dayString(today) }

    /// Which coverage slots have a meal logged today (server coverage arrives in M3).
    var loggedSlots: Set<MealSlot> {
        Set((day?.meals ?? []).compactMap { MealSlot.slot(for: $0.mealType) })
    }

    var coverageFraction: Double { Double(loggedSlots.count) / Double(MealSlot.allCases.count) }

    /// The next unlogged slot, shown as the pending timeline placeholder.
    var pendingSlot: MealSlot? {
        MealSlot.allCases.first { !loggedSlots.contains($0) }
    }

    func load() async {
        isLoading = day == nil
        defer { isLoading = false }
        do {
            let loaded = try await env.run { try await env.entries.day(todayString, tz: math.tzIdentifier) }
            day = loaded.value
            fromCache = loaded.fromCache
            error = nil
            toast = loaded.fromCache ? "Showing cached entries (offline)." : "Daily hub ready."
        } catch let apiError as APIError {
            error = apiError.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ item: TimelineItem) async {
        do {
            switch item {
            case .meal(let meal):
                try await env.run { try await env.entries.deleteMeal(id: meal.id, on: todayString) }
            case .symptom(let symptom):
                try await env.run { try await env.entries.deleteSymptom(id: symptom.id, on: todayString) }
            }
            toast = "Entry removed."
            await load()
        } catch let apiError as APIError {
            error = apiError.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
