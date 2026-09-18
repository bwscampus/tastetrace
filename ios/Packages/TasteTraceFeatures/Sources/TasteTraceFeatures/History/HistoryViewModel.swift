import Foundation
import Observation
import TasteTraceAPI
import TasteTraceCore

@Observable
@MainActor
final class HistoryViewModel {
    var selectedDate: Date
    var day: DayEntries?
    var markers: Markers = [:]
    var isLoading = false
    var fromCache = false
    var error: String?

    private let env: AppEnvironment

    init(env: AppEnvironment, selectedDate: Date = Date()) {
        self.env = env
        self.selectedDate = env.dateMath.startOfDay(selectedDate)
    }

    var math: DateMath { env.dateMath }
    var selectedDay: String { math.dayString(selectedDate) }
    var week: [Date] { math.week(containing: selectedDate) }

    /// Recent days for the horizontal chip row: selected day and the 6 before it.
    var recentDays: [Date] { (0..<7).map { math.addingDays(-$0, to: selectedDate) } }

    func marker(for date: Date) -> DayMarker? { markers[math.dayString(date)] }

    func select(_ date: Date) async {
        selectedDate = math.startOfDay(date)
        await loadDay()
        if !week.contains(where: { markers[math.dayString($0)] != nil }) { await loadMarkers() }
    }

    func load() async {
        async let dayTask: () = loadDay()
        async let markersTask: () = loadMarkers()
        _ = await (dayTask, markersTask)
    }

    func loadDay() async {
        isLoading = day == nil
        defer { isLoading = false }
        do {
            let loaded = try await env.run { try await env.entries.day(selectedDay, tz: math.tzIdentifier) }
            day = loaded.value
            fromCache = loaded.fromCache
            error = nil
        } catch let apiError as APIError {
            error = apiError.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMarkers() async {
        // The visible week plus a week on either side, so swiping stays decorated
        let start = math.addingDays(-7, to: week.first!)
        let end = math.endOfDay(math.addingDays(7, to: week.last!))
        if let loaded = try? await env.run({ try await env.entries.markers(from: start, to: end, tz: math.tzIdentifier) }) {
            markers.merge(loaded.value) { _, new in new }
        }
    }

    func delete(_ item: TimelineItem) async {
        do {
            switch item {
            case .meal(let meal):
                try await env.run { try await env.entries.deleteMeal(id: meal.id, on: selectedDay) }
            case .symptom(let symptom):
                try await env.run { try await env.entries.deleteSymptom(id: symptom.id, on: selectedDay) }
            }
            await load()
        } catch let apiError as APIError {
            error = apiError.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
