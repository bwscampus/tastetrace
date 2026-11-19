import Foundation
import Observation
import TasteTraceAPI
import TasteTraceCore

/// History search: meals containing a food and symptoms matching a name.
/// The Digest's food cards open it limited to foods.
@Observable
@MainActor
final class HistorySearchViewModel {
    enum Scope: Hashable { case foods, foodsAndSymptoms }

    var query: String
    let scope: Scope
    var foods: FoodOccurrences?
    var symptoms: SymptomOccurrences?
    var isLoading = false
    var error: String?

    private let env: AppEnvironment

    init(env: AppEnvironment, query: String, scope: Scope) {
        self.env = env
        self.query = query
        self.scope = scope
    }

    var math: DateMath { env.dateMath }
    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasResults: Bool { foods != nil || symptoms != nil }
    var nothingFound: Bool { (foods?.total ?? 0) == 0 && (symptoms?.total ?? 0) == 0 }

    func search() async {
        let text = trimmedQuery
        guard !text.isEmpty else { foods = nil; symptoms = nil; return }
        isLoading = !hasResults
        defer { isLoading = false }
        do {
            let tz = math.tzIdentifier
            async let foodTask = env.run { try await env.api.foodOccurrences(text, tz: tz) }
            if scope == .foodsAndSymptoms {
                async let symptomTask = env.run { try await env.api.symptomOccurrences(text, tz: tz) }
                let (foundFoods, foundSymptoms) = try await (foodTask, symptomTask)
                foods = foundFoods
                symptoms = foundSymptoms
            } else {
                foods = try await foodTask
            }
            error = nil
        } catch let apiError as APIError {
            error = apiError.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
