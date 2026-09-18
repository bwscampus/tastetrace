import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

struct SuspectsDigestView: View {
    let suspects: SuspectsDigest
    let model: DigestViewModel

    var body: some View {
        HeroGradientCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("24-HOUR PRE-FLARE CORRELATION").font(TTFont.captionSemibold).tracking(1).foregroundStyle(TTColor.successTint)
                    Spacer()
                    StatusBadge("⟲ \(suspects.windowHours)h Lookback", tone: .primary).background(Color.white.opacity(0.15), in: Capsule())
                }
                Text("Top Ingredient Suspects").font(.system(size: 28, weight: .bold))
                Text("Matches ingredients logged within \(suspects.windowHours) hours prior to flare-up symptoms.").font(TTFont.body).opacity(0.9)
                Divider().overlay(Color.white.opacity(0.3))
                HStack(spacing: 8) {
                    heroStat("\(suspects.flares) Flares", "Recorded This Week", .white)
                    heroStat("\(suspects.mealsEvaluated) Meals", "Evaluated", TTColor.warning)
                    heroStat(suspects.leadSuspect?.capitalizedFirst ?? "None yet", "#1 Lead Suspect", TTColor.successTint)
                }
            }
        }

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suspects.symptomFilters) { filter in
                    let selected = (filter.name == "All Symptoms" && model.symptomFilter == nil) || filter.name == model.symptomFilter
                    TTChip("\(filter.name) (\(filter.count))", selected: selected) {
                        Task { await model.filterSuspects(by: filter.name == "All Symptoms" ? nil : filter.name) }
                    }
                }
            }
        }

        TTCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(suspects.windowHours)h Pre-Flare Ingredient Frequency").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                        Text("Times ingredient appeared in \(suspects.windowHours)h window before flare").font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                    }
                    Spacer()
                    StatusBadge("Top 5 Chart", tone: .warning)
                }
                if suspects.ingredients.isEmpty {
                    Text(suspects.flares == 0 ? "No flare-ups this week — nothing to correlate." : "No meals were logged in the window before this week's flares.")
                        .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                }
                ForEach(Array(suspects.ingredients.enumerated()), id: \.element.id) { index, suspect in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(index + 1)").font(TTFont.captionSemibold).foregroundStyle(.white)
                                .frame(width: 24, height: 24).background(index == 0 ? TTColor.danger : TTColor.textSecondary, in: Circle())
                            Text(suspect.name.capitalizedFirst).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                            Spacer()
                            Text("\(suspect.flaresWithIngredient) / \(suspect.flaresTotal) Flares (\(Int((suspect.share * 100).rounded()))%)")
                                .font(TTFont.bodySemibold).foregroundStyle(index == 0 ? TTColor.danger : TTColor.navy)
                        }
                        FrequencyBar(fraction: suspect.share, gradient: index == 0)
                        HStack {
                            Text(suspect.avgOnsetHours.map { String(format: "Avg onset: %.1fh prior", $0) } ?? "Avg onset: —").font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                            Spacer()
                            Text("Logged \(suspect.timesLoggedThisWeek)x this week").font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                        }
                    }
                }
            }
        }

        TimingWindowsCard(windows: suspects.timingWindows)
        SynthesisCard(suspects: suspects, model: model)

        if !suspects.ingredients.isEmpty {
            Text("Suspect Breakdown Cards").font(TTFont.screenTitle).foregroundStyle(TTColor.navy).padding(.top, 6)
        }
        ForEach(suspects.ingredients) { suspect in
            SuspectCard(suspect: suspect, math: model.math) { Task { await model.toggleWatchlist(suspect) } }
        }
    }

    private func heroStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(TTFont.cardTitle).foregroundStyle(color).lineLimit(3).minimumScaleFactor(0.7)
            Text(label).font(TTFont.caption).opacity(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TimingWindowsCard: View {
    let windows: SuspectsDigest.TimingWindows

    var body: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pre-Flare Timing Windows").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                HStack(spacing: 8) {
                    window("0 – 4 Hours", windows.early, "Rapid upper GI onset", TTColor.danger, TTColor.dangerTint)
                    window("4 – 12 Hours", windows.mid, "Small bowel digestion", TTColor.warning, TTColor.warningTint)
                    window("12 – 24 Hours", windows.late, "Colonic fermentation", TTColor.primary, TTColor.infoTint)
                }
            }
        }
    }

    private func window(_ title: String, _ w: SuspectsDigest.TimingWindow, _ note: String, _ color: Color, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title.uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            Text("\(w.flares) Flare\(w.flares == 1 ? "" : "s")").font(TTFont.screenTitle).foregroundStyle(color)
            Text(w.topIngredients.isEmpty ? "None" : w.topIngredients.map { $0.capitalizedFirst }.joined(separator: ", "))
                .font(TTFont.captionSemibold).foregroundStyle(TTColor.navy).multilineTextAlignment(.center).lineLimit(3)
            Text(note).font(.system(size: 11)).foregroundStyle(color.opacity(0.9)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(tint, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(color.opacity(0.5), lineWidth: 1))
    }
}

/// AI Pattern Synthesis card. Until the synthesis endpoint lands (M5) it
/// summarises the suspects payload locally.
struct SynthesisCard: View {
    let suspects: SuspectsDigest
    let model: DigestViewModel

    private var text: String {
        guard let lead = suspects.ingredients.first, suspects.flares > 0 else {
            return "Not enough flares this week to synthesise a pattern. Keep logging meals and symptoms and this card will summarise what tends to come before your flare-ups."
        }
        let onset = lead.avgOnsetHours.map { String(format: "%.1f hours", $0) } ?? "an unknown delay"
        return "In the \(suspects.windowHours)-hour lookback before flares, \(lead.name) appeared in \(lead.flaresWithIngredient) of \(lead.flaresTotal) flare windows (\(Int((lead.share * 100).rounded()))%), with an average meal-to-flare delay of \(onset). These are only observed associations rather than proof of a trigger, and the small number of windows means there is still considerable uncertainty."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wand.and.stars").foregroundStyle(.white).frame(width: 36, height: 36).background(TTColor.primary, in: RoundedRectangle(cornerRadius: 10))
                Text("AI Pattern Synthesis").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                Spacer()
                StatusBadge("AI", tone: .primary)
            }
            Text("“\(text)”").font(TTFont.body).foregroundStyle(TTColor.navy)
            if let lead = suspects.ingredients.first {
                HStack(spacing: 10) {
                    Button { Task { await model.toggleWatchlist(lead) } } label: {
                        Label(lead.onWatchlist ? "On Watchlist" : "Add \(lead.name.capitalizedFirst) to Watchlist", systemImage: "eye")
                            .font(TTFont.bodySemibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(.white).background(TTColor.primary, in: RoundedRectangle(cornerRadius: TTRadius.tile))
                    }
                    .buttonStyle(.plain)
                    Button { model.segment = .symptoms } label: {
                        Label("Deep Breakdown", systemImage: "arrow.triangle.branch")
                            .font(TTFont.bodySemibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(TTColor.primary)
                            .overlay(RoundedRectangle(cornerRadius: TTRadius.tile).stroke(TTColor.primary, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(TTSpacing.card)
        .background(TTColor.infoTint, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous).stroke(TTColor.primary, lineWidth: 1.5))
    }
}

struct SuspectCard: View {
    let suspect: SuspectsDigest.Suspect
    let math: DateMath
    let onWatchlist: () -> Void

    var body: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "fork.knife").foregroundStyle(TTColor.danger).frame(width: 44, height: 44).background(TTColor.dangerTint, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suspect.name.capitalizedFirst).font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                        Text("\(suspect.exposuresAllTime) logged exposure\(suspect.exposuresAllTime == 1 ? "" : "s") all-time").font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                    }
                    Spacer()
                    StatusBadge("\(Int((suspect.share * 100).rounded()))% \(math.tzIdentifier.isEmpty ? "" : "")24h Flare Rate", tone: .danger)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent Meals Before Flares:").font(TTFont.bodySemibold).foregroundStyle(TTColor.textSecondary)
                    ForEach(suspect.recentPairs) { pair in
                        Text("• \(Formatting.shortDay(pair.mealAt, math: math)) \(Formatting.time(pair.mealAt, math: math)): \(pair.mealName) → Flare at \(Formatting.time(pair.flareAt, math: math)) (\(pair.symptoms.joined(separator: ", ")))")
                            .font(TTFont.body).foregroundStyle(TTColor.navy)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(TTColor.background, in: RoundedRectangle(cornerRadius: TTRadius.tile))
                HStack(spacing: 10) {
                    Text("Confidence \(suspect.confidence)%")
                        .font(TTFont.bodySemibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(TTColor.primary)
                        .overlay(RoundedRectangle(cornerRadius: TTRadius.tile).stroke(TTColor.cardBorder, lineWidth: 1))
                    Button(action: onWatchlist) {
                        Text(suspect.onWatchlist ? "Tracking ✓" : "Track in Watchlist")
                            .font(TTFont.bodySemibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundStyle(.white).background(suspect.onWatchlist ? TTColor.success : TTColor.primary, in: RoundedRectangle(cornerRadius: TTRadius.tile))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
