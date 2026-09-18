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
            DigestHeroCard(index: model.digest?.trends.index, changePercent: model.digest?.trends.changeVsPreviousPercent,
                           occurrences: model.digest?.trends.occurrences, days: model.digest?.trends.days ?? [],
                           onViewReport: { router.showDigest(weekStart: model.math.addingDays(-6, to: model.today)) })
            CoverageCard(logged: model.loggedSlots, fraction: model.coverageFraction,
                         streakDays: model.coverage?.streak.days,
                         nudge: model.coverage.map { $0.nudge.enabled ? Formatting.clock($0.nudge.time) : nil } ?? nil) {
                router.todayPath.append(.coverage(date: model.today))
            }
            HStack(spacing: 12) {
                PrimaryButton("Log Meal", systemImage: "plus.circle.fill") { router.sheet = .logMeal(date: model.today) }
                SecondaryButton("Log Symptom", emoji: "💛") { router.sheet = .quickLog(date: model.today) }
            }
            TimelineSection(model: model, onDelete: { pendingDelete = $0 })
            if let error = model.error {
                InfoBanner(emoji: "⚠️", message: error, tone: .warning)
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
                    Text("🍽️").font(.system(size: 26))
                    Text("TasteTrace").font(.system(size: 30, weight: .bold)).foregroundStyle(TTColor.navy)
                }
                if let user = env.session.user {
                    Text("Signed in as \(user.email)").font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                }
            }
            Spacer()
            HStack(spacing: 10) {
                IconCircleButton(systemImage: "bell", showsDot: true) { router.sheet = .notifications }
                IconCircleButton(systemImage: "slider.horizontal.3") { router.sheet = .profile }
            }
        }
        .padding(.top, 4)
    }
}

/// 7-day digest hero. Shows a placeholder until the digest endpoint lands (M4).
struct DigestHeroCard: View {
    var index: Double? = nil
    var changePercent: Int? = nil
    var occurrences: Int? = nil
    var days: [WeeklyDigest.DayTrend] = []
    let onViewReport: () -> Void

    var body: some View {
        HeroGradientCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StatusBadge("7-Day Digest", tone: .primary, uppercased: true)
                        .background(Color.white.opacity(0.15), in: Capsule())
                    if let changePercent {
                        StatusBadge("\(changePercent <= 0 ? "↓" : "↑") \(abs(changePercent))% \(changePercent <= 0 ? "Better" : "Worse")", tone: changePercent <= 0 ? .success : .danger)
                    }
                    Spacer()
                    Button(action: onViewReport) {
                        HStack(spacing: 2) { Text("View Report"); Image(systemName: "chevron.right") }
                            .font(TTFont.bodySemibold)
                    }
                    .buttonStyle(.plain)
                }
                if let index {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.1f", index)).font(TTFont.heroNumber)
                                Text("/ 10").font(TTFont.cardTitle).opacity(0.8)
                            }
                            Text("Weekly Discomfort Index • \(occurrences ?? 0) Occurrences").font(TTFont.body).opacity(0.9)
                        }
                        Spacer()
                        SparklineView(values: days.map(\.index), levels: days.map(\.level))
                    }
                } else {
                    Text("—").font(TTFont.heroNumber)
                    Text("Log meals and symptoms this week to see your discomfort index.").font(TTFont.body).opacity(0.9)
                }
            }
        }
    }
}

/// Daily coverage summary row (ring + slot ticks).
struct CoverageCard: View {
    let logged: Set<MealSlot>
    let fraction: Double
    var streakDays: Int? = nil
    var nudge: String? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            TTCard(padding: 14) {
                HStack(spacing: 14) {
                    RingProgress(progress: fraction, lineWidth: 7) {
                        Text("\(logged.count)/\(MealSlot.allCases.count)").font(TTFont.captionSemibold).foregroundStyle(TTColor.primary)
                    }
                    .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Daily Coverage: \(Int((fraction * 100).rounded()))%")
                                .font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                            if let streakDays, streakDays > 0 {
                                StatusBadge("🔥 \(streakDays)-Day Streak", tone: .success)
                            }
                        }
                        Text(MealSlot.allCases.map { "\($0.rawValue) \($0.emoji)\(logged.contains($0) ? " ✓" : "")" }.joined(separator: " • ") + (nudge.map { " • Nudge \($0)" } ?? ""))
                            .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(TTColor.primary).font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Today's Timeline card: entries in time order plus the next pending slot.
struct TimelineSection: View {
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

                ForEach(model.day?.timeline ?? []) { item in
                    HStack(alignment: .top, spacing: 10) {
                        TimelineRail(color: itemColor(item))
                        switch item {
                        case .meal(let meal):
                            MealEntryCard(meal: meal, math: model.math, onDelete: { onDelete(item) })
                        case .symptom(let symptom):
                            SymptomEntryCard(symptom: symptom, math: model.math, onDelete: { onDelete(item) })
                        }
                    }
                }

                if let pending = model.pendingSlot {
                    HStack(alignment: .top, spacing: 10) {
                        TimelineRail(color: TTColor.primary)
                        DashedPlaceholderCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("+ \(pending.rawValue) Tracker (Ready)").font(TTFont.cardTitle).foregroundStyle(TTColor.primary)
                                    Text("Keep pattern continuity active").font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                                }
                                Spacer()
                                StatusBadge("Pending", tone: .info)
                            }
                        }
                    }
                }
            }
        }
    }

    private func itemColor(_ item: TimelineItem) -> Color {
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
