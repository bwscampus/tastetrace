import Foundation
import Observation
import TasteTraceAPI
import TasteTraceCore

/// Every logged meal containing one food, for History's search and the Digest's food cards.
@Observable
@MainActor
final class FoodOccurrencesViewModel {
    var query: String
    var result: FoodOccurrences?
    var isLoading = false
    var error: String?

    private let env: AppEnvironment

    init(env: AppEnvironment, query: String) {
        self.env = env
        self.query = query
    }

    var math: DateMath { env.dateMath }
    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    func search() async {
        let text = trimmedQuery
        guard !text.isEmpty else { result = nil; return }
        isLoading = result == nil
        defer { isLoading = false }
        do {
            result = try await env.run { try await env.api.foodOccurrences(text, tz: math.tzIdentifier) }
            error = nil
        } catch let apiError as APIError {
            error = apiError.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
