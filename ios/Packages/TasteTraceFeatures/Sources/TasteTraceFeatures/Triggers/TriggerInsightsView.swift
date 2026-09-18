import SwiftUI
import Observation
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

enum TriggerDimension: String, CaseIterable { case ingredient, cookMethod = "cook_method"
    var label: String { self == .ingredient ? "Ingredients" : "Cooking Styles" }
    var emoji: String { self == .ingredient ? "🌾" : "🍳" }
}

@Observable
@MainActor
final class TriggerInsightsViewModel {
    var dimension: TriggerDimension = .ingredient
    var symptom: String?
    var insights: TriggerInsights?
    var minConfidence: Int?
    var isLoading = false
    var error: String?

    private let env: AppEnvironment
    init(env: AppEnvironment) { self.env = env }
    var math: DateMath { env.dateMath }

    func load() async {
        isLoading = insights == nil
        defer { isLoading = false }
        do {
            insights = try await env.run { try await env.api.triggerInsights(dimension: dimension.rawValue, symptom: symptom, minConfidence: minConfidence) }
            error = nil
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }
}

struct TriggerInsightsView: View {
    @Environment(Router.self) private var router
    @State private var model: TriggerInsightsViewModel

    init(env: AppEnvironment) {
        _model = State(initialValue: TriggerInsightsViewModel(env: env))
    }

    var body: some View {
        @Bindable var model = model
        TTScreen {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DIGESTIVE EVIDENCE LEDGER").font(TTFont.captionSemibold).tracking(1.2).foregroundStyle(TTColor.primary)
                    Text("Trigger Insights").font(.system(size: 28, weight: .bold)).foregroundStyle(TTColor.navy)
                }
                Spacer()
                IconCircleButton(systemImage: "slider.horizontal.3") { router.sheet = .profile }
            }

            Button { withAnimation { model.symptom = nil }; Task { await model.load() } } label: {
                HStack(spacing: 12) {
                    Text("📊").font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Symptom Rankings & Tiers").font(TTFont.cardTitle)
                        Text("Tap here to view symptom-specific confidence tiers, co-log evidence cards, and selective plate stamps.")
                            .font(TTFont.caption).opacity(0.9)
                    }
                    Spacer()
                    StatusBadge("Enter ▸", tone: .primary)
                }
                .padding(TTSpacing.card)
                .background(TTColor.heroTop, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            TTSegmentedControl(options: TriggerDimension.allCases, selection: $model.dimension) { "\($0.emoji) \($0.label)" }
                .onChange(of: model.dimension) { _, _ in Task { await model.load() } }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    TTChip("All Triggers", selected: model.symptom == nil) { model.symptom = nil; Task { await model.load() } }
                    ForEach(model.insights?.symptoms ?? []) { s in
                        TTChip("\(s.emoji) \(s.name)", selected: model.symptom == s.name) { model.symptom = s.name; Task { await model.load() } }
                    }
                }
            }

            if model.isLoading { ProgressView().frame(maxWidth: .infinity).padding() }

            if let insights = model.insights {
                if insights.cards.isEmpty {
                    EmptyStateView(emoji: "🔍", title: "Not Enough Discomfort Patterns Yet",
                                   message: "Keep logging your meals and symptoms! Cards below \(insights.minConfidence)% confidence are currently filtered by your settings\(insights.hiddenBelowThreshold > 0 ? " (\(insights.hiddenBelowThreshold) hidden)" : "").",
                                   actionTitle: "Go to History") { router.showHistory(on: Date()) }
                        .frame(minHeight: 360)
                }
                ForEach(insights.cards) { card in
                    TriggerCard(card: card, math: model.math)
                }
                if insights.hiddenBelowThreshold > 0 && !insights.cards.isEmpty {
                    Text("\(insights.hiddenBelowThreshold) weaker association\(insights.hiddenBelowThreshold == 1 ? "" : "s") hidden below \(insights.minConfidence)% confidence.")
                        .font(TTFont.caption).foregroundStyle(TTColor.textSecondary).frame(maxWidth: .infinity)
                }
            }
            if let error = model.error { InfoBanner(emoji: "⚠️", message: error, tone: .warning) }
        } bottom: {
            PinnedBottomBar {
                PrimaryButton("Export Doctor Evidence Ledger (PDF)", systemImage: "doc.richtext") {}
            }
        }
        .navigationBarHidden()
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

struct TriggerCard: View {
    let card: TriggerInsights.Card
    let math: DateMath

    private var tone: BadgeTone {
        switch card.tier { case "strong": return .danger; case "likely": return .warning; default: return .info }
    }

    var body: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.item.capitalizedFirst).font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                        Text("→ \(card.symptomName)").font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(card.confidence)%").font(TTFont.screenTitle).foregroundStyle(tone.foreground)
                        StatusBadge(card.tier.capitalized, tone: tone)
                    }
                }
                FrequencyBar(fraction: Double(card.confidence) / 100, color: tone.foreground)
                HStack {
                    metric("Exposures", "\(card.exposures)")
                    Spacer()
                    metric("Followed by flare", "\(card.flareExposures) (\(Int((card.hitRate * 100).rounded()))%)")
                    Spacer()
                    metric("Lift vs baseline", card.lift.map { String(format: "%.1f×", $0) } ?? "—")
                    Spacer()
                    metric("Avg onset", card.avgOnsetHours.map { String(format: "%.1fh", $0) } ?? "—")
                }
                if !card.evidence.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Co-log evidence").font(TTFont.captionSemibold).foregroundStyle(TTColor.textSecondary)
                        ForEach(card.evidence) { e in
                            Text("• \(Formatting.shortDay(e.mealAt, math: math)) \(e.mealName) → \(card.symptomName) \(String(format: "%.1fh", e.onsetHours)) later")
                                .font(TTFont.caption).foregroundStyle(TTColor.navy)
                        }
                    }
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(TTColor.textSecondary)
            Text(value).font(TTFont.captionSemibold).foregroundStyle(TTColor.navy)
        }
    }
}
