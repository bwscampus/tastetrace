import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

/// Foods eaten before this week's symptoms: each food, when it was eaten and
/// the symptom that followed. No scores or percentages, on purpose.
struct SuspectsDigestView: View {
    let suspects: SuspectsDigest
    let model: DigestViewModel

    var body: some View {
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

        if suspects.ingredients.isEmpty {
            TTCard {
                Text(emptyMessage)
                    .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        } else {
            Text("Foods eaten in the \(suspects.windowHours) hours before a symptom on more than one day")
                .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
        }
        ForEach(suspects.ingredients) { suspect in
            SuspectCard(suspect: suspect, math: model.math) { Task { await model.toggleWatchlist(suspect) } }
        }
    }

    private var emptyMessage: String {
        if suspects.flares == 0 { return "No symptoms this week." }
        if suspects.mealsEvaluated == 0 { return "No meals were logged in the hours before this week's symptoms." }
        // One meal before one symptom is a coincidence; a food shows here once it repeats on another day.
        return "No food has come before a symptom on more than one day yet. Keep logging and patterns will show up here."
    }
}

struct SuspectCard: View {
    let suspect: SuspectsDigest.Suspect
    let math: DateMath
    let onWatchlist: () -> Void

    var body: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "fork.knife").foregroundStyle(TTColor.danger).frame(width: 44, height: 44).background(TTColor.dangerTint, in: RoundedRectangle(cornerRadius: 12))
                    Text(suspect.name.capitalizedFirst).font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(suspect.recentPairs) { pair in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Formatting.shortDay(pair.mealAt, math: math)), \(Formatting.time(pair.mealAt, math: math)): \(pair.mealName)")
                                .font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                            Text("→ \(pair.symptoms.joined(separator: ", ")) at \(Formatting.time(pair.flareAt, math: math))")
                                .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                        }
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(TTColor.background, in: RoundedRectangle(cornerRadius: TTRadius.tile))
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
