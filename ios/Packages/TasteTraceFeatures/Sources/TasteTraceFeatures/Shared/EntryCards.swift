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
                        MealStatusBadge(meals: [meal])
                    }
                    // Named so several foods logged for one meal can be told apart
                    Text(meal.ingredientNames.isEmpty ? meal.name : "\(meal.name): \(Formatting.joinedList(meal.ingredientNames))")
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

/// One meal with all its foods ("Dinner": pasta, salad, bread); each food keeps
/// its own edit and delete because each is its own entry on the server.
struct MealGroupCard: View {
    let group: MealGroup
    let math: DateMath
    var onEdit: ((Meal) -> Void)?
    var onDelete: ((Meal) -> Void)?

    var body: some View {
        if group.meals.count == 1, let meal = group.meals.first {
            let edit: (() -> Void)? = onEdit.map { handler in { handler(meal) } }
            let delete: (() -> Void)? = onDelete.map { handler in { handler(meal) } }
            MealEntryCard(meal: meal, math: math, onEdit: edit, onDelete: delete)
        } else {
            TTCard(padding: 14) {
                HStack(alignment: .top, spacing: 12) {
                    EmojiCircle(MealType(rawValue: group.mealType)?.emoji ?? "🍽️")
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("\(group.mealType) (\(Formatting.time(group.timestamp, math: math)))")
                                .font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            MealStatusBadge(meals: group.meals)
                        }
                        ForEach(group.meals) { meal in
                            foodRow(meal)
                        }
                    }
                }
            }
        }
    }

    private func foodRow(_ meal: Meal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy).lineLimit(1)
                // A food added later in the meal shows its own time
                let details = [Formatting.joinedList(meal.ingredientNames),
                               meal.timestamp != group.timestamp ? Formatting.time(meal.timestamp, math: math) : ""]
                    .filter { !$0.isEmpty }
                if !details.isEmpty {
                    Text(details.joined(separator: " • "))
                        .font(TTFont.body).foregroundStyle(TTColor.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                if let onDelete {
                    Button { onDelete(meal) } label: { Image(systemName: "trash").foregroundStyle(TTColor.danger) }
                        .buttonStyle(.plain).accessibilityLabel("Delete \(meal.name)")
                }
                if let onEdit {
                    Button { onEdit(meal) } label: { Image(systemName: "square.and.pencil").foregroundStyle(TTColor.primary) }
                        .buttonStyle(.plain).accessibilityLabel("Edit \(meal.name)")
                }
            }
            .font(.system(size: 17, weight: .semibold))
        }
        .padding(.top, 6)
        .overlay(alignment: .top) { Divider().overlay(TTColor.cardBorder) }
    }
}

/// Only a food the Triggers page lists earns "Suspicious Trigger"; a symptom
/// merely following the meal is just noted.
struct MealStatusBadge: View {
    let meals: [Meal]

    var body: some View {
        if meals.contains(where: { $0.suspicion == "correlated" }) {
            StatusBadge("Suspicious Trigger", tone: .danger)
        } else if meals.contains(where: { !($0.suspiciousFor ?? []).isEmpty }) {
            StatusBadge("Symptom followed", tone: .warning)
        } else {
            StatusBadge("Logged", tone: .success)
        }
    }
}

/// Symptom row used by History and the Today timeline.
struct SymptomEntryCard: View {
    let symptom: Symptom
    let math: DateMath
    var onEdit: (() -> Void)?
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
                if onEdit != nil || onDelete != nil {
                    HStack(spacing: 14) {
                        if let onDelete {
                            Button(action: onDelete) { Image(systemName: "trash").foregroundStyle(TTColor.danger) }
                                .buttonStyle(.plain).accessibilityLabel("Delete symptom")
                        }
                        if let onEdit {
                            Button(action: onEdit) { Image(systemName: "square.and.pencil").foregroundStyle(TTColor.primary) }
                                .buttonStyle(.plain).accessibilityLabel("Edit symptom time and details")
                        }
                    }
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
