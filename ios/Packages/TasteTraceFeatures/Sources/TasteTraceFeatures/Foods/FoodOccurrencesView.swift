import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

/// Every time a food was eaten, newest first, with any symptoms that followed.
/// Tapping a meal opens its day in History.
struct FoodOccurrencesView: View {
    @Environment(Router.self) private var router
    @State private var model: FoodOccurrencesViewModel

    init(env: AppEnvironment, query: String) {
        _model = State(initialValue: FoodOccurrencesViewModel(env: env, query: query))
    }

    var body: some View {
        @Bindable var model = model
        TTScreen {
            FoodSearchField(text: $model.query) { Task { await model.search() } }
            if model.isLoading { ProgressView().frame(maxWidth: .infinity).padding() }
            if let result = model.result {
                summary(result)
                ForEach(result.occurrences) { occurrence in
                    Button { openDay(occurrence) } label: {
                        OccurrenceCard(occurrence: occurrence, math: model.math)
                    }
                    .buttonStyle(.plain)
                }
                if result.total > result.occurrences.count {
                    Text("Showing the latest \(result.occurrences.count) of \(result.total).")
                        .font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            if let error = model.error { InfoBanner(systemImage: "exclamationmark.triangle.fill", message: error, tone: .warning) }
        }
        .navigationTitle(model.trimmedQuery.capitalizedFirst)
        .task { if model.result == nil { await model.search() } }
        .refreshable { await model.search() }
    }

    @ViewBuilder
    private func summary(_ result: FoodOccurrences) -> some View {
        TTCard(padding: 14) {
            if result.total == 0 {
                Text("No meals with \"\(result.query)\" yet.")
                    .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Eaten \(result.total) time\(result.total == 1 ? "" : "s")")
                        .font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                    Text("Symptoms followed within \(result.windowHours) hours on \(result.withSymptoms) of them")
                        .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func openDay(_ occurrence: FoodOccurrences.Occurrence) {
        guard let date = model.math.date(fromDay: occurrence.date) else { return }
        router.historyPath = []
        router.showHistory(on: date)
    }
}

/// Text field that runs a food search on return.
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
