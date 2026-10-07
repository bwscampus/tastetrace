import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

/// Two-step meal logging presented as a sheet: pick the foods (saved tiles and/or
/// new ones), give each its ingredients, then log them together.
struct LogMealFlow: View {
    @Environment(Router.self) private var router
    @State private var model: LogMealViewModel

    init(env: AppEnvironment, date: Date) {
        _model = State(initialValue: LogMealViewModel(env: env, date: date))
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            LogMealStep1View(model: model)
                .navigationDestination(for: LogMealViewModel.Step.self) { _ in
                    VerifyIngredientsView(model: model)
                }
        }
        .sheet(isPresented: $model.showSaveSheet) {
            SaveDishSheet(model: model)
                .presentationDetents([.large])
        }
        #if canImport(UIKit)
        .sheet(isPresented: $model.showPhotoSheet) {
            MealPhotoSheet(model: model)
                .presentationDetents([.medium, .large])
        }
        #endif
        .onChange(of: model.completed) { _, done in
            if done { router.sheet = nil }
        }
        .task { await model.loadDishes() }
    }
}

struct LogMealStep1View: View {
    @Environment(Router.self) private var router
    @Bindable var model: LogMealViewModel
    @State private var pendingDelete: Dish?
    @State private var editingDish: Dish?
    @State private var showLibrary = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        TTScreen {
            InfoBanner(emoji: "⚡️", title: "Build your meal",
                       message: "Tap every saved tile you ate and add any new foods. Pasta and a salad? Add both, then list each one's ingredients.")
            DateTimeCard(title: "Meal Date & Time", subtitle: "Helps map digestive correlation windows", day: $model.day, time: $model.time, math: model.math)

            SectionLabel("1. Select meal category")
            // Routed through the model so a category picked here is known to be
            // deliberate, and a guess from a photo will not overwrite it.
            MealCategoryGrid(selection: Binding(
                get: { model.mealType },
                set: { model.chooseMealType($0) }
            ))

            SectionLabel("Quick sensitivity filter (optional)")
            HStack(spacing: 8) {
                ForEach(SensitivityFlag.allCases.prefix(4)) { flag in
                    let on = model.flags.contains(flag)
                    Button {
                        if on { model.flags.remove(flag) } else { model.flags.insert(flag) }
                    } label: {
                        VStack(spacing: 6) {
                            Text(flag.emoji).font(.title3)
                            Text(flag.rawValue.uppercased()).font(TTFont.captionSemibold).tracking(0.8)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(on ? TTColor.primary : TTColor.textSecondary)
                        .background(on ? TTColor.infoTint : TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(on ? TTColor.primary : TTColor.cardBorder, lineWidth: on ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            SectionLabel("2. Saved shortcuts & custom entry")
            TTCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Custom saved dish tiles").font(TTFont.captionSemibold).tracking(0.8).textCase(.uppercase).foregroundStyle(TTColor.navy)
                        Spacer()
                        Button { showLibrary = true } label: {
                            HStack(spacing: 4) { Text("Grid Library"); Image(systemName: "arrow.right.to.line") }
                                .font(TTFont.bodySemibold).foregroundStyle(TTColor.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    Divider().overlay(TTColor.cardBorder)
                    if model.dishes.isEmpty {
                        Text("Foods you save while logging show up here. Tap one or more to add them to this meal.")
                            .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                    }
                    ForEach(model.dishes.prefix(4)) { dish in
                        DishTileRow(dish: dish, selected: model.isSelected(dish),
                                    onLog: { model.toggleTile(dish) },
                                    onEdit: { editingDish = dish },
                                    onDelete: { pendingDelete = dish })
                    }
                }
            }

            TTCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add a food").font(TTFont.captionSemibold).tracking(0.8).textCase(.uppercase).foregroundStyle(TTColor.navy)
                    MealInputMethodCard(model: model) { nameFieldFocused = true }
                    HStack(spacing: 10) {
                        Image(systemName: "pencil.and.scribble").foregroundStyle(TTColor.primary)
                        TextField("Pasta, side salad…", text: $model.newFoodName)
                            .font(TTFont.body).foregroundStyle(TTColor.inputText)
                            .focused($nameFieldFocused)
                            .onSubmit { model.addNewFood() }
                        Button("Add") { model.addNewFood() }
                            .font(TTFont.bodySemibold).foregroundStyle(TTColor.primary).buttonStyle(.plain)
                            .disabled(!model.canAddFood)
                    }
                    .padding(12)
                    .background(TTColor.background, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
                    Text("Add each food separately; you'll list the ingredients for each one next.")
                        .font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                }
            }

            if !model.items.isEmpty {
                SectionLabel("3. In this meal (\(model.items.count))")
                TTCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.items) { item in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                                    Text(item.isFromTile ? "Saved tile • \(item.ingredients.count) ingredient\(item.ingredients.count == 1 ? "" : "s")" : "New food")
                                        .font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                                }
                                Spacer()
                                Button { model.remove(item) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(TTColor.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(item.name)")
                            }
                        }
                    }
                }
            }
            ErrorText(model.error)
        } bottom: {
            PinnedBottomBar {
                PrimaryButton(model.items.count > 1 ? "Ingredients for \(model.items.count) foods →" : "Next: ingredients →") {
                    model.goToIngredients()
                }
                .opacity(model.canContinue ? 1 : 0.5).disabled(!model.canContinue)
            }
        }
        .navigationTitle("Log a Meal")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { router.sheet = nil } } }
        .sheet(isPresented: $showLibrary) { DishLibraryView(model: model) }
        .sheet(item: $editingDish) { dish in EditDishView(dish: dish, model: model) }
        .confirmationDialog("Delete this saved dish?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let dish = pendingDelete { Task { await model.deleteTile(dish) } }
                pendingDelete = nil
            }
        }
    }
}

/// Saved tile row: tap to add it to (or take it out of) the meal, Edit / Delete on the right.
struct DishTileRow: View {
    let dish: Dish
    var selected = false
    let onLog: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onLog) {
                HStack(spacing: 12) {
                    EmojiCircle(dish.emoji, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(dish.name).font(TTFont.cardTitle).foregroundStyle(TTColor.navy).lineLimit(1)
                            StatusBadge(selected ? "✓ Added" : "Saved", tone: selected ? .primary : .success)
                        }
                        Text(dish.ingredientNames.isEmpty ? "No ingredients saved" : Formatting.joinedList(dish.ingredientNames))
                            .font(TTFont.body).foregroundStyle(TTColor.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            Button("Edit", action: onEdit)
                .font(TTFont.bodySemibold).foregroundStyle(TTColor.primary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(TTColor.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
                .buttonStyle(.plain)
            Button(action: onDelete) {
                Image(systemName: "trash").foregroundStyle(TTColor.danger)
                    .frame(width: 36, height: 36).background(TTColor.dangerTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(dish.name)")
        }
        .padding(12)
        .background(selected ? TTColor.infoTint : TTColor.background, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(selected ? TTColor.primary : TTColor.cardBorder, lineWidth: selected ? 2 : 1))
    }
}

/// All saved tiles in a grid; tapping adds or removes a tile from the meal, the trash button deletes it.
struct DishLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    let model: LogMealViewModel
    @State private var pendingDelete: Dish?

    var body: some View {
        NavigationStack {
            TTScreen {
                if model.dishes.isEmpty {
                    EmptyStateView(emoji: "🍽️", title: "No saved dishes yet", message: "Save a new food when you log a meal and it will appear here.")
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(model.dishes) { dish in
                        let selected = model.isSelected(dish)
                        Button { model.toggleTile(dish) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(dish.emoji).font(.system(size: 32))
                                    Spacer()
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected ? TTColor.primary : TTColor.cardBorder)
                                }
                                Text(dish.name).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy).lineLimit(2)
                                Text("Logged \(dish.timesLogged)×").font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(selected ? TTColor.infoTint : TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(selected ? TTColor.primary : TTColor.cardBorder, lineWidth: selected ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottomTrailing) {
                            Button { pendingDelete = dish } label: {
                                Image(systemName: "trash").font(.system(size: 14)).foregroundStyle(TTColor.danger)
                                    .frame(width: 32, height: 32).background(TTColor.dangerTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .accessibilityLabel("Delete \(dish.name)")
                        }
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = dish }
                        }
                    }
                }
                ErrorText(model.error)
            }
            .navigationTitle("Grid Library")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete this saved dish?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("Delete", role: .destructive) {
                    if let dish = pendingDelete { Task { await model.deleteTile(dish) } }
                    pendingDelete = nil
                }
            } message: {
                Text("It disappears from your tiles. Meals you already logged keep their foods.")
            }
        }
    }
}

struct VerifyIngredientsView: View {
    @Bindable var model: LogMealViewModel

    var body: some View {
        TTScreen {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Step 2 of 2").font(TTFont.captionSemibold).tracking(1).textCase(.uppercase).foregroundStyle(TTColor.primary)
                    Text("Ingredients for each food").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                }
                Spacer()
                StatusBadge("\(model.items.count) food\(model.items.count == 1 ? "" : "s")", tone: .info)
            }
            .padding(TTSpacing.card)
            .background(TTColor.infoTint, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))

            TriggerTracesCard(hits: model.watchlistHits)

            ForEach($model.items) { $item in
                MealItemIngredientsCard(item: $item,
                                        position: (model.items.firstIndex { $0.id == item.id } ?? 0) + 1,
                                        count: model.items.count,
                                        onRemove: model.items.count > 1 ? { model.remove(item) } : nil)
            }

            TTCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Meal notes (optional)")
                    TextField("Anything else about this meal", text: $model.notes, axis: .vertical)
                        .lineLimit(2...4).font(TTFont.body).foregroundStyle(TTColor.inputText)
                }
            }
            ErrorText(model.error)
        } bottom: {
            PinnedBottomBar {
                PrimaryButton(model.items.count > 1 ? "Log Meal (\(model.items.count) foods)" : "Log Meal",
                              systemImage: "square.and.arrow.down.fill", isLoading: model.isBusy) {
                    Task { await model.reviewAndComplete() }
                }
                .opacity(model.canComplete ? 1 : 0.5)
                .disabled(!model.canComplete)
            }
        }
        .navigationTitle("Verify Ingredients")
    }
}

/// One food of the meal: its name and its own ingredient list.
struct MealItemIngredientsCard: View {
    @Binding var item: MealItem
    let position: Int
    let count: Int
    let onRemove: (() -> Void)?

    private var provenanceLabel: String {
        switch item.origin {
        case .tile: return " • saved tile"
        case .photo: return " • from your photo"
        case .typed: return ""
        }
    }

    /// Low confidence earns a stronger ask, because the alternative is a wrong
    /// ingredient quietly becoming a suspect weeks later.
    private var photoNote: String? {
        guard item.origin == .photo else { return nil }
        return item.photoConfidence == "low"
            ? "Read with low confidence — please check every ingredient."
            : "Read from your photo. Check it before logging."
    }

    var body: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Food \(position) of \(count)\(provenanceLabel)")
                            .font(TTFont.captionSemibold).tracking(0.8).textCase(.uppercase).foregroundStyle(TTColor.primary)
                        TextField("Food name", text: $item.name)
                            .font(TTFont.cardTitle).foregroundStyle(TTColor.inputText)
                    }
                    if let onRemove {
                        Button(action: onRemove) { Image(systemName: "trash").foregroundStyle(TTColor.danger) }
                            .buttonStyle(.plain).accessibilityLabel("Remove \(item.name)")
                    }
                }
                if item.isFromTile && item.ingredients != item.savedIngredients {
                    Text("Edited for this meal only; the saved tile keeps its ingredients.")
                        .font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                }
                if let note = photoNote {
                    // A recognition is a draft. These ingredients become the
                    // evidence behind the digest's suspects, so a wrong one is
                    // worth more than a moment's attention now.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "camera").foregroundStyle(TTColor.primary)
                        Text(note).font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                    }
                }
                IngredientEditor(input: $item.ingredientInput, ingredients: $item.ingredients)
            }
        }
    }
}

/// Watchlist warning card ("Sensitivity Trigger Traces").
struct TriggerTracesCard: View {
    let hits: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("⚠️ Sensitivity Trigger Traces").font(TTFont.captionSemibold).tracking(0.8).textCase(.uppercase).foregroundStyle(TTColor.warning)
                Spacer()
                StatusBadge("Watchlist Alert", tone: .warning)
            }
            Group {
                if hits.isEmpty {
                    Text("✨ No active digestive warning flags detected for this meal.")
                } else {
                    Text("👀 On your watchlist: " + hits.map { $0.capitalizedFirst }.joined(separator: ", "))
                }
            }
            .font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(14)
            .background(TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
        }
        .padding(TTSpacing.card)
        .background(TTColor.warningTint, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous).stroke(TTColor.warningBorder, lineWidth: 1.5))
    }
}

/// Offers to save the meal's new foods as one-tap tiles before logging.
struct SaveDishSheet: View {
    @Bindable var model: LogMealViewModel

    var body: some View {
        TTScreen {
            VStack(spacing: 8) {
                Text("⭐").font(.system(size: 40))
                    .frame(width: 84, height: 84)
                    .background(TTColor.infoTint, in: Circle())
                    .overlay(Circle().stroke(TTColor.primary, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
                Text("Save new foods as tiles?").font(TTFont.screenTitle).foregroundStyle(TTColor.navy).padding(.top, 6)
                Text("Saved foods become one-tap tiles with their ingredients remembered.")
                    .font(TTFont.body).foregroundStyle(TTColor.textSecondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            ForEach($model.items) { $item in
                if !item.isFromTile {
                    TTCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $item.saveAsTile) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                                    Text(item.ingredients.isEmpty ? "No ingredients entered" : "\(item.ingredients.count) ingredient\(item.ingredients.count == 1 ? "" : "s")")
                                        .font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                                }
                            }
                            if item.saveAsTile {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(LogMealViewModel.stampOptions, id: \.self) { emoji in
                                            let selected = item.emoji == emoji
                                            Button { item.emoji = emoji } label: {
                                                Text(emoji).font(.system(size: 24))
                                                    .frame(width: 48, height: 48)
                                                    .background(selected ? TTColor.infoTint : TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                                                    .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(selected ? TTColor.primary : TTColor.cardBorder, lineWidth: selected ? 2 : 1))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            ErrorText(model.error)
        } bottom: {
            PinnedBottomBar {
                PrimaryButton("Log Meal", systemImage: "square.and.arrow.down.fill", isLoading: model.isBusy) {
                    Task { await model.complete() }
                }
            }
        }
    }
}

/// Edits a saved tile's name, emoji and ingredients.
struct EditDishView: View {
    @Environment(\.dismiss) private var dismiss
    let dish: Dish
    let model: LogMealViewModel
    @State private var name: String
    @State private var emoji: String
    @State private var input = ""
    @State private var ingredients: [IngredientDetail]
    @State private var isBusy = false
    @State private var error: String?

    init(dish: Dish, model: LogMealViewModel) {
        self.dish = dish
        self.model = model
        _name = State(initialValue: dish.name)
        _emoji = State(initialValue: dish.emoji)
        _ingredients = State(initialValue: dish.ingredients)
    }

    var body: some View {
        NavigationStack {
            TTScreen {
                TTCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Dish name")
                        TextField("Name", text: $name).font(TTFont.cardTitle).foregroundStyle(TTColor.inputText)
                        SectionLabel("Stamp emoji")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(LogMealViewModel.stampOptions, id: \.self) { option in
                                    Button { emoji = option } label: {
                                        Text(option).font(.system(size: 26)).frame(width: 52, height: 52)
                                            .background(emoji == option ? TTColor.infoTint : TTColor.card, in: RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(emoji == option ? TTColor.primary : TTColor.cardBorder, lineWidth: 1.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                IngredientEditor(input: $input, ingredients: $ingredients)
                ErrorText(error)
            } bottom: {
                PinnedBottomBar {
                    PrimaryButton("Save Changes", isLoading: isBusy) { Task { await save() } }
                }
            }
            .navigationTitle("Edit Dish")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let updated = try await model.updateDish(id: dish.id, DishPatch(name: name, emoji: emoji, ingredients: ingredients))
            model.dishes = model.dishes.map { $0.id == updated.id ? updated : $0 }
            dismiss()
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }
}
