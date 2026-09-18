import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

/// Comma-separated input plus the "Ingredients & Cook Methods" list. Shared
/// by Verify Ingredients, Edit Dish and Edit Meal.
struct IngredientEditor: View {
    @Binding var input: String
    @Binding var ingredients: [IngredientDetail]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Add/search blueprint ingredients")
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(TTColor.primary)
                TextField("avocado, sourdough bread, salt", text: $input)
                    .font(TTFont.body)
                    .onSubmit(add)
                Button("Add", action: add)
                    .font(TTFont.bodySemibold)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(TTColor.primary, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                    .buttonStyle(.plain)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
            .background(TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))

            SectionLabel("Ingredients & cook methods")
            if ingredients.isEmpty {
                Text("No ingredients yet. Add each one so TasteTrace can tell which part of the dish matters.")
                    .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
            }
            ForEach(ingredients, id: \.self) { ingredient in
                IngredientRow(ingredient: ingredient,
                              onMethod: { method in setMethod(method, for: ingredient) },
                              onRemove: { ingredients.removeAll { $0 == ingredient } })
            }
        }
    }

    private func add() {
        for name in parseIngredientInput(input, existing: ingredients.map(\.name)) {
            ingredients.append(IngredientDetail(name: name))
        }
        input = ""
    }

    private func setMethod(_ method: CookMethod?, for ingredient: IngredientDetail) {
        guard let index = ingredients.firstIndex(of: ingredient) else { return }
        ingredients[index].cookMethod = method?.rawValue
    }
}

struct IngredientRow: View {
    let ingredient: IngredientDetail
    let onMethod: (CookMethod?) -> Void
    let onRemove: () -> Void

    var body: some View {
        TTCard(padding: 12) {
            HStack(spacing: 10) {
                Text(ingredient.name.capitalizedFirst).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                Spacer()
                Menu {
                    Button("No cook method") { onMethod(nil) }
                    ForEach(CookMethod.allCases) { method in
                        Button(method.label) { onMethod(method) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(CookMethod.label(for: ingredient.cookMethod) ?? "Prep style")
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                    }
                    .font(TTFont.captionSemibold)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundStyle(ingredient.cookMethod == nil ? TTColor.textSecondary : TTColor.primary)
                    .background(ingredient.cookMethod == nil ? TTColor.neutralTint : TTColor.infoTint, in: Capsule())
                }
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(TTColor.danger)
                        .frame(width: 28, height: 28).background(TTColor.dangerTint, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(ingredient.name)")
            }
        }
    }
}

/// 2×2 grid of Breakfast / Lunch / Dinner / Snack.
struct MealCategoryGrid: View {
    @Binding var selection: MealType

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(MealType.allCases, id: \.self) { type in
                let selected = selection == type
                Button { selection = type } label: {
                    HStack(spacing: 12) {
                        Text(type.emoji).font(.system(size: 28))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.rawValue).font(TTFont.cardTitle).foregroundStyle(selected ? TTColor.primary : TTColor.navy)
                            Text(type.subtitle).font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(selected ? TTColor.primary : TTColor.cardBorder, lineWidth: selected ? 2 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Date + time pickers in a card.
struct DateTimeCard: View {
    let title: String
    let subtitle: String
    @Binding var day: Date
    @Binding var time: Date
    let math: DateMath

    var body: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "clock").font(.title3).foregroundStyle(TTColor.primary)
                        .frame(width: 44, height: 44).background(TTColor.infoTint, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                        Text(subtitle).font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                    }
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Date")
                        DatePicker("", selection: $day, in: ...Date(), displayedComponents: .date).labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Time")
                        DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                    }
                }
                .environment(\.calendar, math.calendar)
                .environment(\.timeZone, math.timeZone)
            }
        }
    }
}
