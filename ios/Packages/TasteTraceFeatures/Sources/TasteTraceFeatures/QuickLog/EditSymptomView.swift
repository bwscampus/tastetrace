import SwiftUI
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

/// Edits a logged symptom from History: intensity, time, duration, notes.
struct EditSymptomView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    let symptomId: Int
    @State private var symptom: Symptom?
    @State private var intensity = 3
    @State private var timestamp = Date()
    @State private var durationMinutes: Int?
    @State private var notes = ""
    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        TTScreen {
            if symptom == nil && error == nil { ProgressView().frame(maxWidth: .infinity).padding() }
            if let symptom {
                TTCard {
                    HStack(spacing: 12) {
                        EmojiCircle(SymptomCatalogDefaults.emoji(for: symptom), size: 52, tint: TTColor.dangerTint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(symptom.name).font(TTFont.screenTitle).foregroundStyle(TTColor.navy)
                            Text(symptom.bodyRegion ?? SymptomCatalogDefaults.item(forKey: symptom.catalogKey)?.bodyRegion ?? "Symptom")
                                .font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                        }
                    }
                }
                TTCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Intensity")
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { level in
                                Button { intensity = level } label: {
                                    Text("\(level)").font(TTFont.cardTitle)
                                        .frame(maxWidth: .infinity).frame(height: 44)
                                        .foregroundStyle(intensity == level ? .white : TTColor.navy)
                                        .background(intensity == level ? TTColor.primary : TTColor.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("Level \(intensity) • \(SeverityMapping.severity(forIntensity: intensity))").font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                    }
                }
                TTCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("When")
                        DatePicker("", selection: $timestamp, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .environment(\.calendar, env.dateMath.calendar)
                            .environment(\.timeZone, env.dateMath.timeZone)
                    }
                }
                AdvancedSymptomSettingsInline(durationMinutes: $durationMinutes, notes: $notes)
            }
            ErrorText(error)
        } bottom: {
            if symptom != nil {
                PinnedBottomBar { PrimaryButton("Save Changes", isLoading: isBusy) { Task { await save() } } }
            }
        }
        .navigationTitle("Edit Symptom")
        .task { await load() }
    }

    private func load() async {
        do {
            let all = try await env.run { try await env.api.symptoms() }
            guard let found = all.first(where: { $0.id == symptomId }) else { error = "Symptom not found."; return }
            symptom = found
            intensity = found.resolvedIntensity
            timestamp = found.timestamp
            durationMinutes = found.durationMinutes
            notes = found.notes ?? ""
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard let symptom else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await env.run {
                try await env.api.updateSymptom(id: symptom.id, SymptomPatch(intensity: intensity, durationMinutes: durationMinutes,
                                                                             timestamp: timestamp, tz: env.dateMath.tzIdentifier, notes: notes))
            }
            await env.entries.invalidate(symptom.date)
            await env.entries.invalidate(env.dateMath.dayString(timestamp))
            router.sheet = nil
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }
}

/// Duration chips + notes, embedded in a card.
struct AdvancedSymptomSettingsInline: View {
    @Binding var durationMinutes: Int?
    @Binding var notes: String
    private let options: [(String, Int?)] = [("Unknown", nil), ("< 30 min", 20), ("~1 hour", 60), ("2–3 hours", 150), ("Half a day", 480), ("All day", 960)]

    var body: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Duration")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(options, id: \.0) { label, minutes in
                        TTChip(label, selected: durationMinutes == minutes) { durationMinutes = minutes }
                    }
                }
                SectionLabel("Notes")
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5).font(TTFont.body)
            }
        }
    }
}
