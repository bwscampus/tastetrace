import Foundation
import Observation
import TasteTraceAPI
import TasteTraceCore

/// Quick Log: pick symptoms from the grid with an intensity each, log them all at once.
@Observable
@MainActor
final class QuickLogViewModel {
    var catalog: [SymptomCatalogItem] = SymptomCatalogDefaults.items
    var customItems: [CustomSymptom] = []
    /// Selected symptoms keyed by catalog key → intensity 1-5.
    var selections: [String: Int] = [:]
    var timestamp: Date
    var timeEdited = false
    var durationMinutes: Int?
    var notes = ""
    var search = ""
    var isBusy = false
    var error: String?
    var completed = false

    private let env: AppEnvironment

    init(env: AppEnvironment, date: Date) {
        self.env = env
        let now = Date()
        timestamp = env.dateMath.isSameDay(date, now) ? now : env.dateMath.combine(day: date, time: now)
        timeEdited = !env.dateMath.isSameDay(date, now)
    }

    var math: DateMath { env.dateMath }

    /// Grid = defaults + custom symptoms, filtered by the search text.
    var gridItems: [SymptomCatalogItem] {
        let all = catalog
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(query) || ($0.bodyRegion ?? "").lowercased().contains(query) }
    }

    /// True when the search names a symptom that isn't in the grid yet.
    var canCreateCustom: Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.count >= 2 && !catalog.contains { $0.name.lowercased() == query.lowercased() }
    }

    var selectedCount: Int { selections.count }
    var loggingForLabel: String { timeEdited ? Formatting.time(timestamp, math: math) : "Just Now" }

    func loadCatalog() async {
        if let fetched = try? await env.run({ try await env.api.symptomCatalog() }) {
            customItems = fetched.custom
            catalog = fetched.defaults + fetched.custom.map(\.catalogItem)
        }
    }

    func toggle(_ item: SymptomCatalogItem) {
        if selections[item.key] != nil { selections[item.key] = nil } else { selections[item.key] = 3 }
    }

    func setIntensity(_ level: Int, for item: SymptomCatalogItem) {
        selections[item.key] = level
    }

    func createCustomSymptom() async {
        let name = search.trimmingCharacters(in: .whitespaces)
        guard canCreateCustom else { return }
        do {
            let created = try await env.run { try await env.api.createCustomSymptom(NewCustomSymptom(name: name)) }
            customItems.append(created)
            catalog.append(created.catalogItem)
            selections[created.key] = 3
            search = ""
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }

    func submit() async {
        guard !selections.isEmpty else { error = "Tap at least one symptom."; return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        let items = catalog.compactMap { item -> SymptomBatch.Item? in
            guard let intensity = selections[item.key] else { return nil }
            return SymptomBatch.Item(name: item.name, catalogKey: item.key, intensity: intensity)
        }
        do {
            _ = try await env.run {
                try await env.api.createSymptoms(SymptomBatch(timestamp: timestamp, tz: math.tzIdentifier, durationMinutes: durationMinutes,
                                                              notes: notes.isEmpty ? nil : notes, items: items))
            }
            await env.entries.invalidate(math.dayString(timestamp))
            completed = true
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }
}
