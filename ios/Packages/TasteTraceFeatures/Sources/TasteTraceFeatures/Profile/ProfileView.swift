import SwiftUI
import Observation
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

@Observable
@MainActor
final class ProfileViewModel {
    var profile: Profile?
    var settings: UserSettings?
    var displayName = ""
    var discoveryPurpose = ""
    var sensitivityTags: [String] = []
    var isSaving = false
    var error: String?
    var saved = false

    private let env: AppEnvironment
    init(env: AppEnvironment) { self.env = env }

    var isDirty: Bool {
        guard let profile else { return false }
        return displayName != (profile.displayName ?? "") || discoveryPurpose != (profile.discoveryPurpose ?? "") || sensitivityTags != profile.sensitivityTags
    }

    func load() async {
        do {
            async let p = env.run { try await env.api.profile() }
            async let s = env.run { try await env.api.settings() }
            let loaded = try await p
            profile = loaded
            settings = try await s
            displayName = loaded.displayName ?? ""
            discoveryPurpose = loaded.discoveryPurpose ?? ""
            sensitivityTags = loaded.sensitivityTags
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            profile = try await env.run {
                try await env.api.updateProfile(ProfilePatch(displayName: displayName, discoveryPurpose: discoveryPurpose, sensitivityTags: sensitivityTags))
            }
            await env.session.refreshUser()
            saved = true
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }

    func updateSettings(_ patch: SettingsPatch) async {
        do { settings = try await env.run { try await env.api.updateSettings(patch) } } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }

    func clearLocalHistory() {
        JSONFileStore<UserSettings>.clearAll()
    }

    func signOut() async { await env.session.signOut() }
}

struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @State private var model: ProfileViewModel
    @State private var showTags = false
    @State private var confirmClear = false

    init(env: AppEnvironment) { _model = State(initialValue: ProfileViewModel(env: env)) }

    var body: some View {
        @Bindable var model = model
        TTScreen {
            if let profile = model.profile {
                TTCard {
                    HStack(spacing: 14) {
                        ZStack(alignment: .bottomTrailing) {
                            Text(profile.avatarEmoji ?? "👤").font(.system(size: 34))
                                .frame(width: 76, height: 76).background(TTColor.infoTint, in: Circle())
                                .overlay(Circle().stroke(TTColor.primary, lineWidth: 2))
                            Image(systemName: "camera.fill").font(.system(size: 10)).foregroundStyle(.white)
                                .frame(width: 22, height: 22).background(TTColor.primary, in: Circle())
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(model.displayName.isEmpty ? shownName(profile) : model.displayName).font(TTFont.screenTitle).foregroundStyle(TTColor.navy).lineLimit(1).minimumScaleFactor(0.7)
                                Image(systemName: "checkmark.seal").foregroundStyle(TTColor.primary)
                            }
                            Text(profile.email).font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                            StatusBadge("📖 Journaler for \(profile.journalerDays) Day\(profile.journalerDays == 1 ? "" : "s")", tone: .info)
                            StatusBadge("✉️ Email Account Active", tone: .success)
                        }
                    }
                }

                TTCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Account Basics", systemImage: "person.text.rectangle").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                            Spacer()
                            Text("Personal Info").font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                        }
                        LabeledField("Display Name", text: $model.displayName)
                        LabeledField("Primary Discovery Purpose", text: $model.discoveryPurpose)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SENSITIVITY DISCOVERY BASELINE").font(TTFont.captionSemibold).tracking(0.8).foregroundStyle(TTColor.textSecondary)
                            Button { showTags = true } label: {
                                HStack {
                                    Text(model.sensitivityTags.isEmpty ? "No sensitivity categories tagged yet" : model.sensitivityTags.map { $0.capitalizedFirst }.joined(separator: ", "))
                                        .font(TTFont.body).foregroundStyle(TTColor.navy).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "tag.fill").foregroundStyle(TTColor.primary)
                                }
                                .padding(12)
                                .background(TTColor.background, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TTCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Ledger Export & Sharing", systemImage: "square.and.arrow.up.on.square").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                            Spacer()
                            StatusBadge("Clinical Ready", tone: .success, uppercased: true)
                        }
                        Text("Export your complete food, symptom, and preparation history for review with a dietitian or gastroenterologist.")
                            .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                        NavigationLink { ExportPlaceholder(title: "Practitioner Report (PDF)") } label: { exportRow("Practitioner Report (PDF)", icon: "doc.richtext", primary: true) }
                        NavigationLink { ExportPlaceholder(title: "Export Raw Data (CSV)") } label: { exportRow("Export Raw Data (CSV)", icon: "tablecells", primary: false) }
                    }
                }

                TTCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Journal Preferences").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                        NavigationLink { TrackingRulesView(model: model) } label: {
                            prefRow(icon: "slider.horizontal.3", tint: TTColor.primary, title: "Tracking Rules & Thresholds",
                                    subtitle: "\(model.settings?.correlationWindowHours ?? 24)h correlation window & trigger counts")
                        }
                        NavigationLink { RemindersView(model: model) } label: {
                            prefRow(icon: "bell", tint: TTColor.warning, title: "Logging Nudges & Reminders", subtitle: "Meal check-ins and symptom follow-ups")
                        }
                        NavigationLink { WatchlistView(env: env) } label: {
                            prefRow(icon: "eye", tint: TTColor.success, title: "Ingredient Watchlist", subtitle: "Ingredients flagged while logging meals")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Account Actions").font(TTFont.cardTitle).foregroundStyle(TTColor.danger)
                    Button { confirmClear = true } label: { dangerRow("Clear Local Journal History", icon: "trash") }
                    Button { Task { await model.signOut(); router.sheet = nil } } label: { dangerRow("Sign Out of Account", icon: "rectangle.portrait.and.arrow.right") }
                }
                .padding(TTSpacing.card)
                .background(TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous).stroke(TTColor.danger.opacity(0.4), lineWidth: 1.5))
            } else if model.error == nil {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
            ErrorText(model.error)
        } bottom: {
            if model.profile != nil {
                PinnedBottomBar {
                    PrimaryButton(model.saved && !model.isDirty ? "Saved ✓" : "Save Profile Changes", systemImage: model.saved && !model.isDirty ? nil : "checkmark", isLoading: model.isSaving) {
                        Task { await model.save() }
                    }
                    .opacity(model.isDirty ? 1 : 0.6)
                }
            }
        }
        .navigationTitle("User Profile")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await model.save() } }.disabled(!model.isDirty) }
        }
        .task { await model.load() }
        .sheet(isPresented: $showTags) { SensitivityTagsSheet(tags: $model.sensitivityTags) }
        .confirmationDialog("Clear cached entries on this device? Your account data on the server is not affected.", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Local History", role: .destructive) { model.clearLocalHistory() }
        }
    }

    private func shownName(_ profile: Profile) -> String {
        let full = [profile.firstName, profile.lastName].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? profile.email : full
    }

    private func exportRow(_ title: String, icon: String, primary: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(primary ? TTColor.primary : TTColor.navy)
            Text(title).font(TTFont.cardTitle).foregroundStyle(primary ? TTColor.primary : TTColor.navy)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(primary ? TTColor.primary : TTColor.textSecondary)
        }
        .padding(14)
        .background(primary ? TTColor.infoTint : TTColor.background, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(primary ? TTColor.primary : TTColor.cardBorder, lineWidth: primary ? 1.5 : 1))
    }

    private func prefRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                Text(subtitle).font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(TTColor.textSecondary)
        }
        .padding(14)
        .background(TTColor.background, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
    }

    private func dangerRow(_ title: String, icon: String) -> some View {
        HStack {
            Text(title).font(TTFont.bodySemibold).foregroundStyle(TTColor.danger)
            Spacer()
            Image(systemName: icon).foregroundStyle(TTColor.danger)
        }
        .padding(14)
        .background(TTColor.dangerTint, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(TTColor.danger.opacity(0.4), lineWidth: 1))
    }
}

struct ExportPlaceholder: View {
    let title: String
    var body: some View {
        EmptyStateView(emoji: "📄", title: title, message: "Exports arrive in the final milestone.").background(TTColor.background)
    }
}

struct SensitivityTagsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var tags: [String]
    private let options = ["gluten", "dairy", "grains", "sugar", "nuts", "soy", "eggs", "shellfish", "fodmap", "caffeine", "alcohol", "histamine"]

    var body: some View {
        NavigationStack {
            TTScreen {
                SectionLabel("Tag categories you already suspect")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        TTChip(option.capitalizedFirst, selected: tags.contains(option)) {
                            if let index = tags.firstIndex(of: option) { tags.remove(at: index) } else { tags.append(option) }
                        }
                    }
                }
            } bottom: {
                PinnedBottomBar { PrimaryButton("Done") { dismiss() } }
            }
            .navigationTitle("Sensitivity Baseline")
        }
    }
}

/// Correlation window, trigger counts, confidence floor, streak rule.
struct TrackingRulesView: View {
    let model: ProfileViewModel
    @State private var window = 24
    @State private var minTriggers = 2
    @State private var minConfidence = 50
    @State private var streakMeals = 2

    var body: some View {
        TTScreen {
            InfoBanner(emoji: "🧭", message: "These thresholds drive the digest, suspects and trigger insights. Changing the window recomputes your correlations.")
            TTCard {
                VStack(alignment: .leading, spacing: 16) {
                    stepper("Correlation window", value: $window, range: 1...72, unit: "h", help: "How long after a meal a symptom still counts.")
                    stepper("Minimum trigger count", value: $minTriggers, range: 1...20, unit: "×", help: "Flares needed before an item can pass the confidence floor.")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text("Confidence floor").font(TTFont.bodySemibold).foregroundStyle(TTColor.navy); Spacer(); Text("\(minConfidence)%").font(TTFont.bodySemibold).foregroundStyle(TTColor.primary) }
                        Slider(value: Binding(get: { Double(minConfidence) }, set: { minConfidence = Int($0) }), in: 0...100, step: 5)
                        Text("Trigger cards below this are hidden.").font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                    }
                    stepper("Streak rule", value: $streakMeals, range: 1...6, unit: " meals/day", help: "Meals per day needed to keep the streak alive.")
                }
            }
        } bottom: {
            PinnedBottomBar {
                PrimaryButton("Save Rules") {
                    Task { await model.updateSettings(SettingsPatch(correlationWindowHours: window, minTriggerCount: minTriggers, minConfidence: minConfidence, streakMealsPerDay: streakMeals)) }
                }
            }
        }
        .navigationTitle("Tracking Rules")
        .onAppear {
            if let s = model.settings { window = s.correlationWindowHours; minTriggers = s.minTriggerCount; minConfidence = s.minConfidence; streakMeals = s.streakMealsPerDay }
        }
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: value, in: range) {
                HStack { Text(title).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy); Spacer(); Text("\(value.wrappedValue)\(unit)").font(TTFont.bodySemibold).foregroundStyle(TTColor.primary) }
            }
            Text(help).font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
        }
    }
}

/// Nudge time and meal check-in toggles; schedules local notifications.
struct RemindersView: View {
    @Environment(AppEnvironment.self) private var env
    let model: ProfileViewModel
    @State private var nudgesEnabled = true
    @State private var nudgeTime = Date()
    @State private var checkIns = false
    @State private var permissionDenied = false

    var body: some View {
        TTScreen {
            InfoBanner(emoji: "🔔", message: "Reminders are scheduled on this device from your saved preferences.")
            TTCard {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Post-dinner nudge", isOn: $nudgesEnabled).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                    DatePicker("Nudge time", selection: $nudgeTime, displayedComponents: .hourAndMinute).font(TTFont.body).disabled(!nudgesEnabled)
                    Toggle("Meal check-ins (9:30, 13:30, 19:30)", isOn: $checkIns).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                    if permissionDenied {
                        Text("Notifications are turned off for TasteTrace in Settings.").font(TTFont.caption).foregroundStyle(TTColor.danger)
                    }
                }
            }
        } bottom: {
            PinnedBottomBar {
                PrimaryButton("Save Reminders") {
                    Task {
                        let hhmm = ReminderScheduler.hhmm(from: nudgeTime, math: env.dateMath)
                        await model.updateSettings(SettingsPatch(nudgeTime: hhmm, nudgesEnabled: nudgesEnabled, mealCheckInsEnabled: checkIns))
                        if let settings = model.settings {
                            let granted = await env.reminders.sync(settings: settings, math: env.dateMath)
                            permissionDenied = !granted && (nudgesEnabled || checkIns)
                        }
                    }
                }
            }
        }
        .navigationTitle("Nudges & Reminders")
        .onAppear {
            if let s = model.settings {
                nudgesEnabled = s.nudgesEnabled; checkIns = s.mealCheckInsEnabled
                nudgeTime = ReminderScheduler.date(fromHHMM: s.nudgeTime, math: env.dateMath)
            }
        }
    }
}
