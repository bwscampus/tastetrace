import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

/// Search results: every time a food was eaten (with any symptoms that
/// followed) and, from History, every matching symptom (with the meals eaten
/// before it). Tapping a result opens its day in History.
struct HistorySearchView: View {
    @Environment(Router.self) private var router
    @State private var model: HistorySearchViewModel

    init(env: AppEnvironment, query: String, scope: HistorySearchViewModel.Scope) {
        _model = State(initialValue: HistorySearchViewModel(env: env, query: query, scope: scope))
    }

    var body: some View {
        @Bindable var model = model
        TTScreen {
            FoodSearchField(text: $model.query, prompt: model.scope == .foods ? "Search a food" : "Search foods or symptoms") {
                Task { await model.search() }
            }
            if model.isLoading { ProgressView().frame(maxWidth: .infinity).padding() }
            if model.hasResults, model.nothingFound {
                TTCard(padding: 14) {
                    Text("Nothing logged matches \"\(model.trimmedQuery)\".")
                        .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            if let foods = model.foods, foods.total > 0 {
                SectionLabel("Foods")
                summary("Eaten \(foods.total) time\(foods.total == 1 ? "" : "s")",
                        "Symptoms followed within \(foods.windowHours) hours on \(foods.withSymptoms) of them")
                ForEach(foods.occurrences) { occurrence in
                    Button { openDay(occurrence.date) } label: { OccurrenceCard(occurrence: occurrence, math: model.math) }
                        .buttonStyle(.plain)
                }
                moreNote(shown: foods.occurrences.count, total: foods.total)
            }
            if let symptoms = model.symptoms, symptoms.total > 0 {
                SectionLabel("Symptoms")
                summary("Logged \(symptoms.total) time\(symptoms.total == 1 ? "" : "s")",
                        "A meal came within \(symptoms.windowHours) hours before \(symptoms.withMeals) of them")
                ForEach(symptoms.occurrences) { occurrence in
                    Button { openDay(occurrence.date) } label: { SymptomOccurrenceCard(occurrence: occurrence, math: model.math) }
                        .buttonStyle(.plain)
                }
                moreNote(shown: symptoms.occurrences.count, total: symptoms.total)
            }
            if let error = model.error { InfoBanner(systemImage: "exclamationmark.triangle.fill", message: error, tone: .warning) }
        }
        .navigationTitle((model.foods?.query ?? model.trimmedQuery).capitalizedFirst)
        .task { if !model.hasResults { await model.search() } }
        .refreshable { await model.search() }
    }

    private func summary(_ title: String, _ detail: String) -> some View {
        TTCard(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                Text(detail).font(TTFont.body).foregroundStyle(TTColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func moreNote(shown: Int, total: Int) -> some View {
        if total > shown {
            Text("Showing the latest \(shown) of \(total).")
                .font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func openDay(_ day: String) {
        guard let date = model.math.date(fromDay: day) else { return }
        router.historyPath = []
        router.showHistory(on: date)
    }
}

/// Text field that runs a search on return.
struct FoodSearchField: View {
    @Binding var text: String
    var prompt = "Search a food, e.g. avocado"
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(TTColor.textSecondary)
            TextField(prompt, text: $text)
                .font(TTFont.body).foregroundStyle(TTColor.inputText)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(TTColor.dot)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .background(TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
    }
}

struct OccurrenceCard: View {
    let occurrence: FoodOccurrences.Occurrence
    let math: DateMath

    var body: some View {
        TTCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(occurrence.mealName).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TTColor.textSecondary)
                }
                Text("\(Formatting.shortDay(occurrence.mealAt, math: math)), \(Formatting.time(occurrence.mealAt, math: math)) • \(occurrence.mealType)")
                    .font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                if occurrence.symptomsAfter.isEmpty {
                    StatusBadge("No symptoms after", tone: .success)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(occurrence.symptomsAfter.enumerated()), id: \.offset) { _, symptom in
                            Text("→ \(symptom.name) at \(Formatting.time(symptom.at, math: math)) (\(Self.onset(symptom.onsetHours)) later)")
                                .font(TTFont.body).foregroundStyle(TTColor.danger)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func onset(_ hours: Double) -> String {
        hours < 1 ? "\(Int((hours * 60).rounded())) min" : String(format: "%.1f h", hours)
    }
}

struct SymptomOccurrenceCard: View {
    let occurrence: SymptomOccurrences.Occurrence
    let math: DateMath

    var body: some View {
        TTCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(occurrence.name).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                    Spacer()
                    StatusBadge(occurrence.intensity.map { "\($0) / 5" } ?? occurrence.severity, tone: .danger)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TTColor.textSecondary)
                }
                Text("\(Formatting.shortDay(occurrence.at, math: math)), \(Formatting.time(occurrence.at, math: math))")
                    .font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                if occurrence.mealsBefore.isEmpty {
                    StatusBadge("No meal logged before", tone: .neutral)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(occurrence.mealsBefore.enumerated()), id: \.offset) { _, meal in
                            Text("← \(meal.mealName) at \(Formatting.time(meal.at, math: math)) (\(OccurrenceCard.onset(meal.onsetHours)) before)")
                                .font(TTFont.body).foregroundStyle(TTColor.navy)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
