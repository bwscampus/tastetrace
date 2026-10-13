import Foundation
import Observation
import TasteTraceAPI
import TasteTraceCore

enum DigestSegment: String, CaseIterable { case trends = "Trends", symptoms = "Symptoms", suspects = "Suspects" }

/// Weekly digest state: the 7-day window, the trends/symptoms payload and the suspects payload.
@Observable
@MainActor
final class DigestViewModel {
    var weekStart: Date
    var segment: DigestSegment = .trends
    var digest: WeeklyDigest?
    var suspects: SuspectsDigest?
    var symptomFilter: String?
    var isLoading = false
    var error: String?

    private let env: AppEnvironment
    private var cache: [String: WeeklyDigest] = [:]

    init(env: AppEnvironment, weekStart: Date?) {
        self.env = env
        self.weekStart = env.dateMath.startOfDay(weekStart ?? env.dateMath.addingDays(-6, to: Date()))
    }

    var math: DateMath { env.dateMath }
    var weekStartString: String { math.dayString(weekStart) }
    var weekEnd: Date { math.addingDays(6, to: weekStart) }
    var canGoForward: Bool { math.addingDays(7, to: weekStart) <= Date() }

    /// "Sep 11 – Sep 17, 2026"
    var rangeLabel: String {
        let f = DateFormatter()
        f.calendar = math.calendar; f.timeZone = math.timeZone
        f.dateFormat = "MMM d"
        let year = DateFormatter()
        year.calendar = math.calendar; year.timeZone = math.timeZone
        year.dateFormat = "MMM d, yyyy"
        return "\(f.string(from: weekStart)) – \(year.string(from: weekEnd))"
    }

    func load() async {
        isLoading = digest == nil
        defer { isLoading = false }
        do {
            async let digestTask = env.run { try await env.api.weeklyDigest(weekStart: weekStartString, tz: math.tzIdentifier) }
            async let suspectsTask = env.run { try await env.api.suspects(weekStart: weekStartString, symptom: symptomFilter, tz: math.tzIdentifier) }
            digest = try await digestTask
            suspects = try await suspectsTask
            error = nil
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }

    func shift(weeks: Int) async {
        weekStart = math.addingDays(7 * weeks, to: weekStart)
        digest = nil
        suspects = nil
        await load()
    }

    func filterSuspects(by symptom: String?) async {
        symptomFilter = symptom
        if let fresh = try? await env.run({ try await env.api.suspects(weekStart: weekStartString, symptom: symptom, tz: math.tzIdentifier) }) {
            suspects = fresh
        }
    }

    func toggleWatchlist(_ suspect: SuspectsDigest.Suspect) async {
        do {
            if suspect.onWatchlist {
                let items = try await env.run { try await env.api.watchlist() }
                if let item = items.first(where: { $0.ingredient == suspect.name.lowercased() }) {
                    try await env.run { try await env.api.removeFromWatchlist(id: item.id) }
                }
            } else {
                _ = try await env.run { try await env.api.addToWatchlist(suspect.name, source: "suspect") }
            }
            if let index = suspects?.ingredients.firstIndex(where: { $0.id == suspect.id }) {
                suspects?.ingredients[index].onWatchlist.toggle()
            }
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }

    /// Day label for a "YYYY-MM-DD" ("Friday").
    func dayName(_ day: String?) -> String {
        guard let day, let date = math.date(fromDay: day) else { return "—" }
        let f = DateFormatter()
        f.calendar = math.calendar; f.timeZone = math.timeZone
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }
}
