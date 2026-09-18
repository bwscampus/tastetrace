import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

/// Weekly Health Digest: week pager + Trends / Symptoms / Suspects segments.
struct DigestView: View {
    @Environment(Router.self) private var router
    @State private var model: DigestViewModel

    init(env: AppEnvironment, weekStart: Date? = nil, segment: DigestSegment = .trends) {
        let model = DigestViewModel(env: env, weekStart: weekStart)
        model.segment = segment
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        TTScreen {
            header
            weekPager
            TTSegmentedControl(options: DigestSegment.allCases, selection: $model.segment) { $0.rawValue }
            if model.isLoading { ProgressView().frame(maxWidth: .infinity).padding() }
            switch model.segment {
            case .trends:
                if let digest = model.digest { TrendsView(digest: digest, model: model) }
            case .symptoms:
                if let digest = model.digest { SymptomsDigestView(digest: digest, model: model) }
            case .suspects:
                if let suspects = model.suspects { SuspectsDigestView(suspects: suspects, model: model) }
            }
            if let error = model.error { InfoBanner(emoji: "⚠️", message: error, tone: .warning) }
        } bottom: {
            if model.segment != .trends, model.digest != nil {
                PinnedBottomBar {
                    SecondaryButton("Export Weekly Digest Report (PDF)", systemImage: "square.and.arrow.up") {
                        router.sheet = .export(kind: ReportKind.weeklyDigest.rawValue, weekStart: model.weekStart)
                    }
                }
            }
        }
        .navigationBarHidden()
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private var header: some View {
        HStack {
            IconCircleButton(systemImage: "arrow.left") { router.tab = .today }
            Spacer()
            switch model.segment {
            case .trends: ScreenHeading("Weekly Health Digest", subtitle: "7-Day Summary", subtitleUppercased: true)
            case .symptoms: ScreenHeading("Weekly Symptom Digest", subtitle: "Symptom Occurrences", subtitleUppercased: true)
            case .suspects: ScreenHeading("Food Suspect Digest", subtitle: "24h Window Roundup", subtitleUppercased: true)
            }
            Spacer()
            IconCircleButton(systemImage: "doc.richtext") { router.sheet = .export(kind: ReportKind.weeklyDigest.rawValue, weekStart: model.weekStart) }
        }
    }

    private var weekPager: some View {
        TTCard(padding: 10) {
            HStack {
                Button { Task { await model.shift(weeks: -1) } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(TTColor.primary)
                        .frame(width: 44, height: 44).background(TTColor.infoTint, in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                VStack(spacing: 2) {
                    Text(model.rangeLabel).font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                    Text(model.segment == .suspects ? "\(model.suspects?.flares ?? 0) Symptom Flare-ups Logged" : "Baseline comparison: All History")
                        .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                }
                Spacer()
                Button { Task { await model.shift(weeks: 1) } } label: {
                    Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(model.canGoForward ? TTColor.primary : TTColor.dot)
                        .frame(width: 44, height: 44).background(model.canGoForward ? TTColor.infoTint : TTColor.neutralTint, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canGoForward)
            }
        }
    }
}

struct TrendsView: View {
    let digest: WeeklyDigest
    let model: DigestViewModel

    var body: some View {
        HeroGradientCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WEEKLY AVERAGE").font(TTFont.captionSemibold).tracking(1).foregroundStyle(TTColor.successTint)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", digest.trends.index)).font(TTFont.heroNumber)
                            Text("/ 10").font(TTFont.cardTitle).opacity(0.8)
                        }
                        Text("Physical Discomfort Index").font(TTFont.body).opacity(0.9)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(deltaLabel).font(TTFont.bodySemibold)
                        Text(String(format: "vs All-Time (%.1f)", digest.trends.baselineIndex)).font(TTFont.caption).opacity(0.8)
                    }
                    .padding(10).background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                Divider().overlay(Color.white.opacity(0.3))
                HStack {
                    stat("\(digest.trends.discomfortFreeDays) Days", "Discomfort Free", .white)
                    Spacer()
                    stat("\(digest.trends.severeDays) Days", "Severe Peak (\(digest.trends.severePeakDay.map { String(model.dayName($0).prefix(3)) } ?? "—"))", TTColor.warning)
                    Spacer()
                    stat("\(Int((digest.trends.mealLogDepth * 100).rounded()))%", "Meal Log Depth", TTColor.successTint)
                }
            }
        }

        TTCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Discomfort vs Historical Baseline").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                        Text(String(format: "Dashed line = All-History Baseline (%.1f)", digest.trends.baselineIndex)).font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                    }
                    Spacer()
                    StatusBadge(digest.trends.dataCompleteness == "complete" ? "✓ Complete Data" : digest.trends.dataCompleteness == "partial" ? "Partial Data" : "No Data",
                                tone: digest.trends.dataCompleteness == "complete" ? .success : .warning)
                }
                DiscomfortBarChart(bars: digest.trends.days.map { .init(id: $0.date, label: $0.weekday, value: $0.index, level: $0.level) },
                                   baseline: digest.trends.baselineIndex)
                HStack(spacing: 14) {
                    legend("Zero Discomfort", TTColor.success)
                    legend("Moderate (1-4)", TTColor.primary)
                    legend("High Flare (5+)", TTColor.danger)
                }
            }
        }

        Button { withAnimation { model.segment = .suspects } } label: {
            linkCard(icon: "fork.knife", tint: TTColor.warning, title: "View Food Suspect Digest", subtitle: "Ingredient frequency in 24h prior to flare-ups", border: TTColor.warning)
        }
        .buttonStyle(.plain)
        Button { withAnimation { model.segment = .symptoms } } label: {
            linkCard(icon: "waveform.path.ecg", tint: TTColor.primary, title: "View Symptom Occurrence Cards", subtitle: "Severity, duration and peak days per symptom", border: TTColor.primary)
        }
        .buttonStyle(.plain)
    }

    private var deltaLabel: String {
        let delta = digest.trends.deltaVsBaselinePercent
        if delta == 0 { return "↓ Same as Avg" }
        return delta < 0 ? "↓ \(abs(delta))% Better" : "↑ \(delta)% Worse"
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(TTFont.cardTitle).foregroundStyle(color)
            Text(label).font(TTFont.caption).opacity(0.85)
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
        }
    }

    private func linkCard(icon: String, tint: Color, title: String, subtitle: String, border: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(.white)
                .frame(width: 48, height: 48).background(tint, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                Text(subtitle).font(TTFont.body).foregroundStyle(TTColor.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(tint)
        }
        .padding(TTSpacing.card)
        .background(TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous).stroke(border, lineWidth: 1.5))
    }
}

struct SymptomsDigestView: View {
    let digest: WeeklyDigest
    let model: DigestViewModel
    private let palette: [Color] = [TTColor.danger, TTColor.primary, TTColor.warning, TTColor.success, TTColor.heroBottom]

    var body: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel("Total recorded events")
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(digest.symptoms.total)").font(TTFont.heroNumber).foregroundStyle(TTColor.navy)
                            Text("Occurrences").font(TTFont.screenTitle).foregroundStyle(TTColor.textSecondary)
                        }
                        Text("Across \(digest.symptoms.distinct) distinct symptom categor\(digest.symptoms.distinct == 1 ? "y" : "ies")").font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(baselineLabel(digest.symptoms.vsBaseline)).font(TTFont.bodySemibold).foregroundStyle(baselineColor(digest.symptoms.vsBaseline))
                        Text(String(format: "Baseline: %.1f / week", digest.symptoms.baselinePerWeek)).font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                    }
                    .padding(10).background(TTColor.neutralTint, in: RoundedRectangle(cornerRadius: 12))
                }
                HStack {
                    Text("Symptom Distribution").font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                    Spacer()
                    Text("100% Categorized").font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                }
                if digest.symptoms.total > 0 {
                    DistributionBar(segments: digest.symptoms.distribution.enumerated().map { .init(id: $1.name, share: $1.share, color: palette[$0 % palette.count]) })
                } else {
                    Text("No symptoms logged this week.").font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                }
            }
        }

        if !digest.symptoms.cards.isEmpty {
            Text("Structured Breakdown by Symptom").font(TTFont.screenTitle).foregroundStyle(TTColor.navy).padding(.top, 6)
        }
        ForEach(Array(digest.symptoms.cards.enumerated()), id: \.element.id) { index, card in
            SymptomDigestCard(card: card, color: palette[index % palette.count], peakDay: model.dayName(card.peakDay))
        }

        TTCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Onset Time Window Distribution").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                Text("When symptoms tend to flare relative to meal times:").font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                onsetRow("< 1 Hour Post-Meal", digest.symptoms.onsetWindows.under1h)
                onsetRow("1–3 Hours Post-Meal", digest.symptoms.onsetWindows.from1to3h)
                onsetRow("3+ Hours Post-Meal", digest.symptoms.onsetWindows.over3h)
                if digest.symptoms.onsetWindows.unmatched > 0 {
                    onsetRow("No meal in window", digest.symptoms.onsetWindows.unmatched)
                }
            }
        }
    }

    private func onsetRow(_ label: String, _ count: Int) -> some View {
        let total = max(digest.symptoms.onsetWindows.total, 1)
        return HStack(spacing: 12) {
            Text(label).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy).frame(width: 130, alignment: .leading)
            FrequencyBar(fraction: Double(count) / Double(total))
            Text("\(count) (\(Int((Double(count) / Double(total) * 100).rounded()))%)").font(TTFont.bodySemibold)
                .foregroundStyle(count > 0 ? TTColor.primary : TTColor.textSecondary).frame(width: 70, alignment: .trailing)
        }
    }

    func baselineLabel(_ value: String) -> String {
        switch value { case "up": return "↑ Above Avg"; case "down": return "↓ Below Avg"; default: return "↓ Same as Avg" }
    }

    func baselineColor(_ value: String) -> Color {
        switch value { case "up": return TTColor.danger; default: return TTColor.success }
    }
}

struct SymptomDigestCard: View {
    let card: WeeklyDigest.SymptomCard
    let color: Color
    let peakDay: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(card.emoji ?? "⚡️").font(.title2).frame(width: 48, height: 48).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name).font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                    Text("\(card.occurrences) Occurrence\(card.occurrences == 1 ? "" : "s") (\(Int((card.shareOfWeek * 100).rounded()))% of week)").font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                }
                Spacer()
                StatusBadge(card.vsBaseline == "up" ? "Above Baseline" : card.vsBaseline == "down" ? "Below Baseline" : "Same as Baseline", tone: card.vsBaseline == "up" ? .danger : .success)
            }
            HStack {
                metric("Avg Severity", String(format: "%.1f / 10", card.avgSeverity10), color)
                Spacer()
                metric("Avg Duration", card.avgDurationMinutes.map { $0 < 30 ? "< 30 min" : $0 < 90 ? "~1 hour" : Formatting.duration($0) } ?? "—", TTColor.navy)
                Spacer()
                metric("Peak Day", peakDay, TTColor.navy)
            }
            .padding(12).frame(maxWidth: .infinity)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: TTRadius.tile))
            HStack {
                Text("Top Triggers:").font(TTFont.bodySemibold).foregroundStyle(TTColor.textSecondary)
                if card.topTriggers.isEmpty {
                    Text("Not enough data yet").font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                } else {
                    StatusBadge(card.topTriggers.map { $0.capitalizedFirst }.joined(separator: ", "), tone: .danger)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(TTColor.textSecondary)
            }
        }
        .padding(TTSpacing.card)
        .background(TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous).stroke(color.opacity(0.35), lineWidth: 1.5))
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(TTFont.captionSemibold).foregroundStyle(TTColor.textSecondary)
            Text(value).font(TTFont.cardTitle).foregroundStyle(color)
        }
    }
}
