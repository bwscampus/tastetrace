import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

struct TodayView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @State private var model: TodayViewModel
    @State private var pendingDelete: TimelineItem?

    init(env: AppEnvironment) {
        _model = State(initialValue: TodayViewModel(env: env))
    }

    var body: some View {
        TTScreen {
            header
            if let coverage = model.coverage {
                StreakCard(streak: coverage.streak, mealsToday: coverage.week.last?.meals ?? 0) {
                    router.todayPath.append(.coverage(date: model.today))
                }
            }
            HStack(spacing: 12) {
                PrimaryButton("Log Meal", systemImage: "plus.circle.fill") { router.sheet = .logMeal(date: model.today) }
                SecondaryButton("Log Symptom", systemImage: "waveform.path.ecg") { router.sheet = .quickLog(date: model.today) }
            }
            // Nothing to show until the first entry of the day.
            if model.hasEntries {
                TimelineSection(model: model, onDelete: { pendingDelete = $0 })
            }
            if let error = model.error {
                InfoBanner(systemImage: "exclamationmark.triangle.fill", message: error, tone: .warning)
            }
        } bottom: {
            if let toast = model.toast {
                ToastView(toast).padding(.horizontal, TTSpacing.screen).padding(.bottom, 6)
            }
        }
        .navigationBarHidden()
        .task { await model.load() }
        .refreshable { await model.load() }
        .confirmationDialog("Delete this entry?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let item = pendingDelete { Task { await model.delete(item) } }
                pendingDelete = nil
            }
        }
        .onChange(of: router.sheet) { _, sheet in
            if sheet == nil { Task { await model.load() } }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Formatting.todayHeader(model.today, math: model.math))
                    .font(TTFont.captionSemibold).tracking(1.2).foregroundStyle(TTColor.primary)
                HStack(spacing: 8) {
                    Image(systemName: "fork.knife").font(.system(size: 22, weight: .semibold)).foregroundStyle(TTColor.primary)
                    Text("TasteTrace").font(.system(size: 30, weight: .bold)).foregroundStyle(TTColor.navy)
                }
                Text(Formatting.greeting(at: model.today, name: greetingName, math: model.math))
                    .font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
            }
            Spacer()
            HStack(spacing: 10) {
                IconCircleButton(systemImage: "bell", showsDot: true) { router.sheet = .notifications }
                IconCircleButton(systemImage: "slider.horizontal.3") { router.sheet = .profile }
            }
        }
        .padding(.top, 4)
    }

    /// First name from onboarding, else the profile's display name.
    private var greetingName: String? {
        guard let user = env.session.user else { return nil }
        if let first = user.firstName, !first.trimmingCharacters(in: .whitespaces).isEmpty { return first }
        return user.displayName
    }
}

/// Daily logging streak, tapping through to the coverage detail.
struct StreakCard: View {
    let streak: Coverage.Streak
    let mealsToday: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            TTCard(padding: 14) {
                HStack(spacing: 14) {
                    Text("🔥").font(.system(size: 28))
                        .frame(width: 52, height: 52)
                        .background(TTColor.successTint, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(streak.days)-Day Streak").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                        Text(message).font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(TTColor.primary).font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var message: String {
        if streak.todayCounts { return "Today counts. Keep it going tomorrow." }
        let left = max(streak.threshold - mealsToday, 1)
        let meals = "\(left) more meal\(left == 1 ? "" : "s")"
        return streak.days == 0 ? "Log \(meals) today to start a streak." : "Log \(meals) today to keep it going."
    }
}

/// Today's Timeline card: entries in time order plus the next pending slot.
struct TimelineSection: View {
    @Environment(Router.self) private var router
    let model: TodayViewModel
    let onDelete: (TimelineItem) -> Void

    var body: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(TTColor.success, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).frame(width: 40, height: 40)
                        Text("\(model.day?.entries ?? model.day?.timeline.count ?? 0)").font(TTFont.captionSemibold).foregroundStyle(TTColor.success)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's Timeline").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                        Text("\(model.day?.timeline.count ?? 0) Events logged • \(model.fromCache ? "Offline copy" : "Ledger ready")")
                            .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                    }
                    Spacer()
                }
                Divider().overlay(TTColor.cardBorder)

                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }

                ForEach(model.day?.groupedTimeline ?? []) { item in
                    HStack(alignment: .top, spacing: 10) {
                        TimelineRail(color: itemColor(item))
                        switch item {
                        case .meals(let group):
                            MealGroupCard(group: group, math: model.math,
                                          onEdit: { router.sheet = .editMeal(id: $0.id) },
                                          onDelete: { onDelete(.meal($0)) })
                        case .symptom(let symptom):
                            SymptomEntryCard(symptom: symptom, math: model.math,
                                             onEdit: { router.sheet = .editSymptom(id: symptom.id) },
                                             onDelete: { onDelete(.symptom(symptom)) })
                        }
                    }
                }

                // Always offers the next meal, so a second lunch or a late snack is one tap away.
                Button { router.sheet = .logMeal(date: model.today) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        TimelineRail(color: TTColor.primary)
                        DashedPlaceholderCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.pendingSlot.map { "+ Log \($0.rawValue)" } ?? "+ Log another meal")
                                        .font(TTFont.cardTitle).foregroundStyle(TTColor.primary)
                                    Text("Tap to add a meal").font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(TTColor.primary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func itemColor(_ item: DayItem) -> Color {
        if case .symptom = item { return TTColor.warning }
        return TTColor.primary
    }
}

struct TimelineRail: View {
    let color: Color
    var body: some View {
        VStack(spacing: 0) {
            Circle().fill(color).frame(width: 10, height: 10).padding(.top, 18)
            Rectangle().fill(TTColor.cardBorder).frame(width: 2).frame(maxHeight: .infinity)
        }
        .frame(width: 10)
    }
}

extension View {
    /// Hides the navigation bar on both platforms the packages build for.
    func navigationBarHidden() -> some View {
        #if os(iOS)
        return self.toolbar(.hidden, for: .navigationBar)
        #else
        return self
        #endif
    }
}
