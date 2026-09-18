import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

/// Two-step meal logging presented as a sheet: pick category/tile, verify ingredients, save.
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

    var body: some View {
        TTScreen {
            InfoBanner(emoji: "⚡️", title: "Quick speed logs",
                       message: "Tap any saved food tile to log instantly with its saved ingredients! Or create a new custom recipe.")
            DateTimeCard(title: "Meal Date & Time", subtitle: "Helps map digestive correlation windows", day: $model.day, time: $model.time, math: model.math)

            SectionLabel("1. Select meal category")
            MealCategoryGrid(selection: $model.mealType)

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
                        Text("Dishes you save from a new recipe show up here for one-tap logging.")
                            .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                    }
                    ForEach(model.dishes.prefix(4)) { dish in
                        DishTileRow(dish: dish,
                                    onLog: { Task { await model.logTile(dish) } },
                                    onEdit: { editingDish = dish },
                                    onDelete: { pendingDelete = dish })
                    }
                }
            }

            TTCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Write new recipe").font(TTFont.captionSemibold).tracking(0.8).textCase(.uppercase).foregroundStyle(TTColor.navy)
                    HStack(spacing: 10) {
                        Image(systemName: "pencil.and.scribble").foregroundStyle(TTColor.primary)
                        TextField("Avocado Sourdough Toast", text: $model.recipeName).font(TTFont.body)
                    }
                    .padding(12)
                    .background(TTColor.background, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
                    PrimaryButton("Configure ingredients & prep styles →", isLoading: model.isBusy) { model.configureRecipe() }
                        .opacity(model.canConfigure ? 1 : 0.5).disabled(!model.canConfigure)
                }
            }
            ErrorText(model.error)
        } bottom: {
            Text("Select category above and tap a tile, or configure custom recipe! 🥣")
                .font(TTFont.body.italic()).foregroundStyle(TTColor.textSecondary)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(TTColor.background)
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

/// Saved tile row: tap to log instantly, Edit / Delete on the right.
struct DishTileRow: View {
    let dish: Dish
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
                            StatusBadge("Saved", tone: .success)
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
        .background(TTColor.background, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
    }
}

/// All saved tiles in a grid; tapping logs with the current category/time.
struct DishLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    let model: LogMealViewModel

    var body: some View {
        NavigationStack {
            TTScreen {
                if model.dishes.isEmpty {
                    EmptyStateView(emoji: "🍽️", title: "No saved dishes yet", message: "Save a recipe from the Verify Ingredients step and it will appear here.")
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(model.dishes) { dish in
                        Button { Task { await model.logTile(dish) }; dismiss() } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(dish.emoji).font(.system(size: 32))
                                Text(dish.name).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy).lineLimit(2)
                                Text("Logged \(dish.timesLogged)×").font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Grid Library")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
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
                    Text("Analyze Ingredient Traces").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                }
                Spacer()
                StatusBadge("Reviewing Blueprints", tone: .info)
            }
            .padding(TTSpacing.card)
            .background(TTColor.infoTint, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))

            TTCard {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Dish name / label")
                    HStack {
                        TextField("Dish name", text: $model.dishName).font(TTFont.screenTitle).foregroundStyle(TTColor.navy)
                        Image(systemName: "pencil").foregroundStyle(TTColor.primary)
                    }
                }
            }

            TriggerTracesCard(hits: model.watchlistHits)
            IngredientEditor(input: $model.ingredientInput, ingredients: $model.ingredients)

            DashedPlaceholderCard {
                HStack(spacing: 10) {
                    Image(systemName: "star").foregroundStyle(TTColor.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("First Log Save Suggestion").font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                        Text("Save this dish as a tile so its ingredients are remembered next time.").font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                    }
                }
            }
            ErrorText(model.error)
        } bottom: {
            PinnedBottomBar {
                PrimaryButton("Complete Meal & Review Save", systemImage: "square.and.arrow.down.fill", isLoading: model.isBusy) {
                    model.showSaveSheet = true
                }
                .opacity(model.dishName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                .disabled(model.dishName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Verify Ingredients")
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

struct SaveDishSheet: View {
    @Bindable var model: LogMealViewModel

    var body: some View {
        TTScreen {
            VStack(spacing: 10) {
                ZStack(alignment: .bottom) {
                    Text(model.stampEmoji).font(.system(size: 40))
                        .frame(width: 96, height: 96)
                        .background(TTColor.infoTint, in: Circle())
                        .overlay(Circle().stroke(TTColor.primary, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
                    Text("NEW SHORTCUT").font(.system(size: 10, weight: .bold)).tracking(1)
                        .padding(.horizontal, 10).padding(.vertical, 5).foregroundStyle(.white)
                        .background(TTColor.primary, in: Capsule()).offset(y: 10)
                }
                Text("Save custom dish?").font(TTFont.screenTitle).foregroundStyle(TTColor.navy).padding(.top, 8)
                Text("Saved dishes become one-tap tiles with their ingredients remembered.")
                    .font(TTFont.body).foregroundStyle(TTColor.textSecondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            TTCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Dish name / label")
                    TextField("Dish name", text: $model.dishName)
                        .font(TTFont.cardTitle).foregroundStyle(TTColor.primary)
                        .padding(12)
                        .background(TTColor.background, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
                    SectionLabel("Select stamp emoji")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(LogMealViewModel.stampOptions, id: \.self) { emoji in
                                let selected = model.stampEmoji == emoji
                                Button { model.stampEmoji = emoji } label: {
                                    Text(emoji).font(.system(size: 28))
                                        .frame(width: 60, height: 60)
                                        .background(selected ? TTColor.infoTint : TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(selected ? TTColor.primary : TTColor.cardBorder, lineWidth: selected ? 2 : 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Divider().overlay(TTColor.cardBorder)
                    HStack {
                        Text("Associated Ingredients:").font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                        Spacer()
                        StatusBadge(model.ingredients.isEmpty ? "No ingredients entered" : "\(model.ingredients.count) ingredient\(model.ingredients.count == 1 ? "" : "s")", tone: .info)
                    }
                }
            }
            ErrorText(model.error)
        } bottom: {
            PinnedBottomBar {
                PrimaryButton("Save & Complete Log", systemImage: "square.and.arrow.down.fill", isLoading: model.isBusy) {
                    Task { await model.complete(saveAsDish: true) }
                }
                SecondaryButton("Just Log Once (No Shortcut)") {
                    Task { await model.complete(saveAsDish: false) }
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
                        TextField("Name", text: $name).font(TTFont.cardTitle)
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
