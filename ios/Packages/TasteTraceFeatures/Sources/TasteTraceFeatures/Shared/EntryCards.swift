import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

/// Meal row used by History and the Today timeline.
struct MealEntryCard: View {
    let meal: Meal
    let math: DateMath
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    private var mealType: MealType? { MealType(rawValue: meal.mealType) }

    var body: some View {
        TTCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                EmojiCircle(mealType?.emoji ?? "🍽️")
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("\(meal.mealType) (\(Formatting.time(meal.timestamp, math: math)))")
                            .font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        if let suspicious = meal.suspiciousFor, !suspicious.isEmpty {
                            StatusBadge("Suspicious Trigger", tone: .danger)
                        } else {
                            StatusBadge("Logged", tone: .success)
                        }
                    }
                    Text(meal.ingredientNames.isEmpty ? meal.name : Formatting.joinedList(meal.ingredientNames))
                        .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if onEdit != nil || onDelete != nil {
                    HStack(spacing: 14) {
                        if let onDelete {
                            Button(action: onDelete) { Image(systemName: "trash").foregroundStyle(TTColor.danger) }
                                .buttonStyle(.plain).accessibilityLabel("Delete meal")
                        }
                        if let onEdit {
                            Button(action: onEdit) { Image(systemName: "square.and.pencil").foregroundStyle(TTColor.primary) }
                                .buttonStyle(.plain).accessibilityLabel("Edit meal")
                        }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.top, 10)
                }
            }
        }
    }
}

/// Symptom row used by History and the Today timeline.
struct SymptomEntryCard: View {
    let symptom: Symptom
    let math: DateMath
    var onDelete: (() -> Void)?

    var body: some View {
        TTCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                EmojiCircle(SymptomCatalogDefaults.emoji(for: symptom), tint: TTColor.dangerTint)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("\(symptom.name) Flare (\(Formatting.time(symptom.timestamp, math: math)))")
                            .font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        StatusBadge("Symptom", tone: .danger)
                    }
                    Text("\(symptom.severity) • Level \(symptom.resolvedIntensity)/5\(symptom.durationMinutes.map { " • \(Formatting.duration($0))" } ?? "")")
                        .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                }
                Spacer(minLength: 0)
                if let onDelete {
                    Button(action: onDelete) { Image(systemName: "trash").foregroundStyle(TTColor.danger) }
                        .buttonStyle(.plain).accessibilityLabel("Delete symptom")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.top, 10)
                }
            }
        }
    }
}

extension Formatting {
    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours == hours.rounded() ? "\(Int(hours)) h" : String(format: "%.1f h", hours)
    }
}
