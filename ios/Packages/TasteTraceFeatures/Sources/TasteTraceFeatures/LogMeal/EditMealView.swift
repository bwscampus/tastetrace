import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

/// Edits a logged meal from History: name, category, time, ingredients, notes.
struct EditMealView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    let mealId: Int
    @State private var meal: Meal?
    @State private var name = ""
    @State private var mealType: MealType = .lunch
    @State private var day = Date()
    @State private var time = Date()
    @State private var input = ""
    @State private var ingredients: [IngredientDetail] = []
    @State private var notes = ""
    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        TTScreen {
            if meal == nil && error == nil {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
            if meal != nil {
                TTCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Meal name")
                        TextField("Name", text: $name).font(TTFont.cardTitle)
                    }
                }
                DateTimeCard(title: "When did you eat?", subtitle: "Adjusting time re-maps correlation windows", day: $day, time: $time, math: env.dateMath)
                SectionLabel("Meal category")
                MealCategoryGrid(selection: $mealType)
                IngredientEditor(input: $input, ingredients: $ingredients)
                TTCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Notes")
                        TextField("Anything else about this meal", text: $notes, axis: .vertical).lineLimit(2...5).font(TTFont.body)
                    }
                }
            }
            ErrorText(error)
        } bottom: {
            if meal != nil {
                PinnedBottomBar { PrimaryButton("Save Changes", isLoading: isBusy) { Task { await save() } } }
            }
        }
        .navigationTitle("Edit Meal")
        .task { await load() }
    }

    private func load() async {
        do {
            let loaded = try await env.run { try await env.api.meal(id: mealId) }
            meal = loaded
            name = loaded.name
            mealType = MealType(rawValue: loaded.mealType) ?? .lunch
            day = env.dateMath.startOfDay(loaded.timestamp)
            time = loaded.timestamp
            ingredients = loaded.ingredientDetails ?? loaded.ingredientNames.map { IngredientDetail(name: $0) }
            notes = loaded.notes ?? ""
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard let meal else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let timestamp = env.dateMath.combine(day: day, time: time)
            _ = try await env.run {
                try await env.api.updateMeal(id: meal.id, MealPatch(name: name, mealType: mealType, timestamp: timestamp, tz: env.dateMath.tzIdentifier,
                                                                    notes: notes, ingredientDetails: ingredients))
            }
            await env.entries.invalidate(meal.date)
            await env.entries.invalidate(env.dateMath.dayString(timestamp))
            router.sheet = nil
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }
}
