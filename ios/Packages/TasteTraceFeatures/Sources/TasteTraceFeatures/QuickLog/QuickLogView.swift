import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

struct QuickLogView: View {
    @Environment(Router.self) private var router
    @State private var model: QuickLogViewModel
    @State private var showTimeEditor = false
    @State private var showAdvanced = false

    init(env: AppEnvironment, date: Date) {
        _model = State(initialValue: QuickLogViewModel(env: env, date: date))
    }

    var body: some View {
        @Bindable var model = model
        TTScreen {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(TTColor.primary)
                    Text("Logging for: ").font(TTFont.body).foregroundStyle(TTColor.navy)
                    + Text(model.loggingForLabel).font(TTFont.bodySemibold).foregroundStyle(TTColor.primary)
                }
                Spacer()
                Button("Edit Time") { showTimeEditor = true }
                    .font(TTFont.bodySemibold).foregroundStyle(TTColor.primary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(TTColor.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
                    .buttonStyle(.plain)
            }
            .padding(TTSpacing.card)
            .background(TTColor.infoTint, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(TTColor.primary)
                TextField("Search other custom symptoms…", text: $model.search)
                    .font(TTFont.bodySemibold)
                    .onSubmit { Task { await model.createCustomSymptom() } }
                if model.canCreateCustom {
                    Button("Add") { Task { await model.createCustomSymptom() } }
                        .font(TTFont.bodySemibold).foregroundStyle(TTColor.primary).buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(TTColor.card, in: Capsule())
            .overlay(Capsule().stroke(TTColor.primary, lineWidth: 1.5))

            SectionLabel("🥣 Digestive discomfort grid")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(model.gridItems) { item in
                    SymptomGridCard(item: item, intensity: model.selections[item.key],
                                    onToggle: { model.toggle(item) },
                                    onIntensity: { model.setIntensity($0, for: item) })
                }
            }
            if model.gridItems.isEmpty {
                Text("No symptom matches “\(model.search)”. Press Add to create it.")
                    .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
            }

            InfoBanner(emoji: "💡", title: "Digestive First",
                       message: "Tracking exact physical intensities helps TasteTrace run cross-checks with recent ingredients. Let us isolate your triggers!",
                       tone: .warning)
            ErrorText(model.error)
        } bottom: {
            PinnedBottomBar {
                PrimaryButton(model.selectedCount > 0 ? "Log Selected Instantly (\(model.selectedCount))" : "Log Selected Instantly",
                              systemImage: "square.and.arrow.down.fill", isLoading: model.isBusy) {
                    Task { await model.submit() }
                }
                .opacity(model.selectedCount > 0 ? 1 : 0.5).disabled(model.selectedCount == 0)
                SecondaryButton("Advanced Settings & Timers", systemImage: "slider.horizontal.3") { showAdvanced = true }
            }
        }
        .navigationTitle("Quick Log")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { router.sheet = nil } }
        }
        .task { await model.loadCatalog() }
        .onChange(of: model.completed) { _, done in if done { router.sheet = nil } }
        .sheet(isPresented: $showTimeEditor) {
            SymptomTimeSheet(timestamp: $model.timestamp, edited: $model.timeEdited, math: model.math)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAdvanced) {
            AdvancedSymptomSettingsView(durationMinutes: $model.durationMinutes, notes: $model.notes)
                .presentationDetents([.medium, .large])
        }
    }
}

/// One grid cell: emoji, name, body region, 1–5 intensity picker, checkmark when selected.
struct SymptomGridCard: View {
    let item: SymptomCatalogItem
    let intensity: Int?
    let onToggle: () -> Void
    let onIntensity: (Int) -> Void

    private var selected: Bool { intensity != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 8) {
                    Text(item.emoji).font(.system(size: 26))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(TTFont.cardTitle).foregroundStyle(TTColor.navy).lineLimit(1).minimumScaleFactor(0.8)
                        Text(item.bodyRegion ?? "Custom").font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? TTColor.primary : TTColor.cardBorder)
                }
            }
            .buttonStyle(.plain)
            Divider().overlay(TTColor.cardBorder)
            HStack {
                Text("INTENSITY:").font(TTFont.captionSemibold).tracking(0.6).foregroundStyle(TTColor.textSecondary)
                Spacer()
                Text(intensity.map { "Level \($0)" } ?? "None").font(TTFont.captionSemibold).foregroundStyle(selected ? TTColor.primary : TTColor.textSecondary)
            }
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { level in
                    Button { onIntensity(level) } label: {
                        Text("\(level)")
                            .font(TTFont.bodySemibold)
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .foregroundStyle(intensity == level ? .white : TTColor.navy)
                            .background(intensity == level ? TTColor.primary : TTColor.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.name) intensity \(level)")
                }
            }
        }
        .padding(12)
        .background(TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous).stroke(selected ? TTColor.primary : TTColor.cardBorder, lineWidth: selected ? 2 : 1))
    }
}

struct SymptomTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var timestamp: Date
    @Binding var edited: Bool
    let math: DateMath

    var body: some View {
        VStack(spacing: 16) {
            Text("When did it start?").font(TTFont.screenTitle).foregroundStyle(TTColor.navy)
            DatePicker("", selection: $timestamp, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .environment(\.calendar, math.calendar)
                .environment(\.timeZone, math.timeZone)
            HStack(spacing: 10) {
                SecondaryButton("Just Now") { timestamp = Date(); edited = false; dismiss() }
                PrimaryButton("Use This Time") { edited = true; dismiss() }
            }
        }
        .padding(TTSpacing.screen)
        .background(TTColor.background)
    }
}

/// Duration and notes for the batch being logged.
struct AdvancedSymptomSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var durationMinutes: Int?
    @Binding var notes: String

    private let options: [(String, Int?)] = [("Unknown", nil), ("< 30 min", 20), ("~1 hour", 60), ("2–3 hours", 150), ("Half a day", 480), ("All day", 960)]

    var body: some View {
        NavigationStack {
            TTScreen {
                SectionLabel("How long did it last?")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(options, id: \.0) { label, minutes in
                        TTChip(label, selected: durationMinutes == minutes) { durationMinutes = minutes }
                    }
                }
                SectionLabel("Notes")
                TextField("Anything that might matter (stress, sleep, medication)…", text: $notes, axis: .vertical)
                    .lineLimit(3...6).font(TTFont.body)
                    .padding(12)
                    .background(TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
            } bottom: {
                PinnedBottomBar { PrimaryButton("Done") { dismiss() } }
            }
            .navigationTitle("Advanced Settings & Timers")
        }
    }
}
