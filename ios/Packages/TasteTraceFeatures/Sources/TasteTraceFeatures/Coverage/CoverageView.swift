import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

/// Daily Logging Coverage: streak hero, coverage wheel, nudge, 7-day breakdown.
struct CoverageView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    let date: Date
    @State private var coverage: Coverage?
    @State private var error: String?

    var body: some View {
        TTScreen {
            if let coverage {
                StreakHero(coverage: coverage)
                CoverageWheelCard(coverage: coverage) { slot in
                    router.sheet = .logMeal(date: date)
                    _ = slot
                }
                NudgeCard(nudge: coverage.nudge) { router.sheet = .profile }
                WeekBreakdownCard(coverage: coverage)
            } else if error == nil {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
            if let error { InfoBanner(emoji: "⚠️", message: error, tone: .warning) }
        }
        .navigationTitle("Daily Logging Coverage")
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: router.sheet) { _, sheet in if sheet == nil { Task { await load() } } }
    }

    private func load() async {
        do {
            coverage = try await env.run { try await env.api.coverage(on: env.dateMath.dayString(date), tz: env.dateMath.tzIdentifier) }
            error = nil
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }
}

struct StreakHero: View {
    let coverage: Coverage

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text("🔥").font(.system(size: 120)).opacity(0.18).offset(x: 10, y: -10)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    StatusBadge("Active Ledger", tone: .primary, uppercased: true).background(Color.white.opacity(0.15), in: Capsule())
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Rule Threshold").font(TTFont.caption).opacity(0.85)
                        Text(coverage.streak.rule).font(TTFont.bodySemibold).foregroundStyle(TTColor.successTint)
                    }
                }
                Text("\(coverage.streak.days) Day Streak 🔥").font(.system(size: 32, weight: .bold))
                Text(coverage.streak.days == 0
                     ? "Start logging at least \(coverage.streak.threshold) meals today to begin your active daily streak."
                     : coverage.streak.todayCounts ? "Today counts. Keep the ledger going tomorrow."
                     : "Log \(coverage.streak.threshold - coverage.week.last!.meals) more meal\(coverage.streak.threshold - coverage.week.last!.meals == 1 ? "" : "s") today to extend your streak.")
                    .font(TTFont.body).opacity(0.9)
                HStack(spacing: 4) {
                    ForEach(coverage.week) { day in
                        let isToday = day.date == coverage.date
                        VStack(spacing: 6) {
                            Text(day.weekday.uppercased()).font(TTFont.captionSemibold).foregroundStyle(isToday ? TTColor.successTint : .white.opacity(0.7))
                            Text(day.meals > 0 || isToday ? "\(day.meals)" : "–")
                                .font(TTFont.bodySemibold)
                                .frame(width: 34, height: 34)
                                .background(isToday ? TTColor.primary : day.metThreshold ? Color.white.opacity(0.25) : Color.white.opacity(0.1), in: Circle())
                            Text(isToday ? "Today" : day.meals > 0 ? "\(day.meals) meal\(day.meals == 1 ? "" : "s")" : "–")
                                .font(.system(size: 10)).foregroundStyle(isToday ? TTColor.successTint : .white.opacity(0.7))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
            }
            .padding(TTSpacing.card)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TTColor.heroTop, in: RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: TTRadius.card, style: .continuous))
    }
}

struct CoverageWheelCard: View {
    let coverage: Coverage
    let onSlot: (MealSlot) -> Void

    var body: some View {
        TTCard {
            VStack(spacing: 18) {
                HStack {
                    Text("Today's Meal Coverage Wheel").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                    Spacer()
                    StatusBadge("\(coverage.percent)% Complete", tone: .info)
                }
                RingProgress(progress: coverage.fraction, lineWidth: 16, color: TTColor.primary) {
                    VStack(spacing: 2) {
                        Text("🍽️").font(.title2)
                        Text("\(coverage.loggedCount) / \(coverage.slotTotal)").font(.system(size: 30, weight: .bold)).foregroundStyle(TTColor.navy)
                        Text("MEALS RECORDED").font(TTFont.captionSemibold).tracking(1).foregroundStyle(TTColor.textSecondary)
                    }
                }
                .frame(width: 200, height: 200)
                HStack(spacing: 10) {
                    ForEach(MealSlot.allCases) { slot in
                        let status = coverage.slots[slot.rawValue]
                        let logged = status?.logged ?? false
                        Button { if !logged { onSlot(slot) } } label: {
                            VStack(spacing: 4) {
                                Text(slot.emoji).font(.title2)
                                Text(slot.rawValue).font(TTFont.bodySemibold).foregroundStyle(slotColor(slot))
                                Text(logged ? (status?.time ?? "Logged") : "Pending" + (slot == .dinner ? " ⊕" : ""))
                                    .font(TTFont.captionSemibold).foregroundStyle(slotColor(slot))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(slotTint(slot), in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(slotColor(slot).opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func slotColor(_ slot: MealSlot) -> Color {
        switch slot { case .breakfast: return TTColor.success; case .lunch: return TTColor.primary; case .dinner: return TTColor.warning }
    }

    private func slotTint(_ slot: MealSlot) -> Color {
        switch slot { case .breakfast: return TTColor.successTint; case .lunch: return TTColor.infoTint; case .dinner: return TTColor.warningTint }
    }
}

struct NudgeCard: View {
    let nudge: Coverage.Nudge
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            TTCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.title3).foregroundStyle(TTColor.primary)
                        .frame(width: 48, height: 48).background(TTColor.infoTint, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(nudge.enabled ? "Post-Dinner Nudge Scheduled" : "Nudges Off").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                            Spacer()
                            Text(Formatting.clock(nudge.time)).font(TTFont.bodySemibold).foregroundStyle(TTColor.primary)
                        }
                        Text("You'll get a gentle nudge after dinner eating window. Tap to customize nudge timers.")
                            .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                    }
                    Image(systemName: "chevron.right").foregroundStyle(TTColor.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct WeekBreakdownCard: View {
    let coverage: Coverage

    var body: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("7-Day Log Breakdown").font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                    Spacer()
                    Text("\(coverage.weekSlots.logged) / \(coverage.weekSlots.total) Slots Logged").font(TTFont.bodySemibold).foregroundStyle(TTColor.primary)
                }
                ForEach(MealSlot.allCases) { slot in
                    let tally = coverage.weekSlots.bySlot[slot.rawValue]
                    let logged = tally?.logged ?? 0
                    let total = tally?.total ?? 7
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(slot.emoji) \(slot.rawValue) Coverage").font(TTFont.body).foregroundStyle(TTColor.navy)
                            Spacer()
                            Text("\(Int((Double(logged) / Double(max(total, 1)) * 100).rounded()))% (\(logged)/\(total) days)")
                                .font(TTFont.captionSemibold).foregroundStyle(TTColor.primary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(TTColor.neutralTint)
                                Capsule().fill(TTColor.primary).frame(width: geo.size.width * CGFloat(logged) / CGFloat(max(total, 1)))
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
        }
    }
}

extension Formatting {
    /// "20:30" → "08:30 PM"
    static func clock(_ hhmm: String) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return hhmm }
        let hour12 = parts[0] % 12 == 0 ? 12 : parts[0] % 12
        return String(format: "%02d:%02d %@", hour12, parts[1], parts[0] < 12 ? "AM" : "PM")
    }
}
