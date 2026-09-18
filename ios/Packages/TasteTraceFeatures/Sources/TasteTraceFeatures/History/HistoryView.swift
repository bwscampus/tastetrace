import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

struct HistoryView: View {
    @Environment(Router.self) private var router
    @State private var model: HistoryViewModel
    @State private var pendingDelete: TimelineItem?
    @State private var showJumpToDate = false

    init(env: AppEnvironment) {
        _model = State(initialValue: HistoryViewModel(env: env))
    }

    var body: some View {
        TTScreen {
            header
            WeekStrip(model: model) { date in Task { await model.select(date) } }
            DayChips(model: model) { date in Task { await model.select(date) } }
            daySummary
            if model.isLoading { ProgressView().frame(maxWidth: .infinity).padding() }
            ForEach(model.day?.timeline ?? []) { item in
                switch item {
                case .meal(let meal):
                    MealEntryCard(meal: meal, math: model.math,
                                  onEdit: { router.sheet = .editMeal(id: meal.id) },
                                  onDelete: { pendingDelete = item })
                case .symptom(let symptom):
                    SymptomEntryCard(symptom: symptom, math: model.math, onDelete: { pendingDelete = item })
                }
            }
            if let day = model.day, day.timeline.isEmpty, !model.isLoading {
                TTCard {
                    Text("Nothing logged on this day.").font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            if let error = model.error { InfoBanner(emoji: "⚠️", message: error, tone: .warning) }
            digestBanner
        }
        .navigationBarHidden()
        .task { await model.load() }
        .refreshable { await model.load() }
        .onChange(of: router.historyDate) { _, date in
            if let date { Task { await model.select(date) }; router.historyDate = nil }
        }
        .onChange(of: router.sheet) { _, sheet in
            if sheet == nil { Task { await model.load() } }
        }
        .sheet(isPresented: $showJumpToDate) {
            JumpToDateSheet(date: model.selectedDate, math: model.math) { date in
                showJumpToDate = false
                Task { await model.select(date) }
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let item = pendingDelete { Task { await model.delete(item) } }
                pendingDelete = nil
            }
        }
    }

    private var header: some View {
        HStack {
            IconCircleButton(systemImage: "chevron.left") { router.tab = .today }
            Spacer()
            ScreenHeading("Symptom & Food History", subtitle: Formatting.monthYear(model.selectedDate, math: model.math) + " 📅")
            Spacer()
            Button {
                router.showDigest(weekStart: model.math.addingDays(-6, to: model.selectedDate))
            } label: {
                HStack(spacing: 6) { Image(systemName: "chart.xyaxis.line"); Text("Digest") }
                    .font(TTFont.bodySemibold)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .foregroundStyle(TTColor.primary)
                    .background(TTColor.infoTint, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .trailing) {
            Button("Jump to Date", systemImage: "calendar.badge.checkmark") { showJumpToDate = true }
                .font(TTFont.captionSemibold).labelStyle(.titleAndIcon)
                .foregroundStyle(TTColor.primary)
                .offset(y: 46)
        }
        .padding(.bottom, 28)
    }

    private var daySummary: some View {
        TTCard(padding: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Formatting.longDay(model.selectedDate, math: model.math)).font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                    Text("\(model.day?.timeline.count ?? 0) Recorded Log Entries • \(model.day?.flares ?? model.day?.symptoms.count ?? 0) Symptom Flare\((model.day?.flares ?? 0) == 1 ? "" : "s")")
                        .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                }
                Spacer()
                Button { router.sheet = .logMeal(date: model.selectedDate) } label: {
                    Label("Add Log", systemImage: "plus")
                        .font(TTFont.bodySemibold)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(TTColor.primary, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var digestBanner: some View {
        Button { router.showDigest(weekStart: model.math.addingDays(-6, to: model.selectedDate)) } label: {
            HeroGradientCard {
                HStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line").font(.title3)
                        .frame(width: 44, height: 44).background(Color.white.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review 7-Day Digest Summary").font(TTFont.cardTitle)
                        Text("Chart trends, symptom breakdown & doctor export").font(TTFont.body).opacity(0.85)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").foregroundStyle(TTColor.successTint)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Monday–Sunday strip with a status dot under each day.
struct WeekStrip: View {
    let model: HistoryViewModel
    let onSelect: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Select day to view logs")
            HStack(spacing: 4) {
                ForEach(model.week, id: \.self) { date in
                    let selected = model.math.isSameDay(date, model.selectedDate)
                    let isToday = model.math.isSameDay(date, Date())
                    Button { onSelect(date) } label: {
                        VStack(spacing: 6) {
                            Text(model.math.weekdayLabel(date).prefix(1)).font(TTFont.captionSemibold).foregroundStyle(TTColor.textSecondary)
                            Text("\(model.math.calendar.component(.day, from: date))")
                                .font(TTFont.bodySemibold)
                                .frame(width: 36, height: 36)
                                .foregroundStyle(selected ? .white : TTColor.navy)
                                .background(selected ? TTColor.primary : .clear, in: Circle())
                                .overlay(Circle().stroke(isToday && !selected ? TTColor.primary : .clear, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                            Circle().fill(dotColor(for: date)).frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selected ? TTColor.infoTint : .clear, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(selected ? TTColor.primary : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func dotColor(for date: Date) -> Color {
        guard let marker = model.marker(for: date) else { return .clear }
        switch marker.status ?? (marker.symptoms > 0 ? "symptom" : "meal") {
        case "symptom": return TTColor.warning
        case "meal": return TTColor.primary
        default: return TTColor.success
        }
    }
}

/// Horizontal chips for the selected day and the days before it.
struct DayChips: View {
    let model: HistoryViewModel
    let onSelect: (Date) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.recentDays, id: \.self) { date in
                    let selected = model.math.isSameDay(date, model.selectedDate)
                    TTChip(Formatting.shortDay(date, math: model.math) + (selected ? " (Active)" : ""), selected: selected) { onSelect(date) }
                }
            }
        }
    }
}

struct JumpToDateSheet: View {
    @State var date: Date
    let math: DateMath
    let onPick: (Date) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Jump to Date").font(TTFont.screenTitle).foregroundStyle(TTColor.navy)
            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.calendar, math.calendar)
                .environment(\.timeZone, math.timeZone)
            PrimaryButton("Show Day") { onPick(date) }
        }
        .padding(TTSpacing.screen)
        .background(TTColor.background)
    }
}
