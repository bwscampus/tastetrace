import SwiftUI
import Observation
import TasteTraceAPI
import TasteTraceCore
import TasteTraceUI

@Observable
@MainActor
final class ExportViewModel {
    var from: Date
    var to: Date
    var isBusy = false
    var error: String?
    var fileURL: URL?

    private let env: AppEnvironment

    init(env: AppEnvironment, weeks: Int = 4) {
        self.env = env
        let end = env.dateMath.startOfDay(Date())
        to = end
        from = env.dateMath.addingDays(-(weeks * 7 - 1), to: end)
    }

    var math: DateMath { env.dateMath }

    private func tempFile(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: name)
    }

    func exportCSV() async {
        await produce(name: "tastetrace-\(math.dayString(from))-\(math.dayString(to)).csv") {
            try await env.run { try await env.api.csvExport(from: math.dayString(from), to: math.dayString(to), tz: math.tzIdentifier) }
        }
    }

    func exportPDF(_ kind: ReportKind, weekStart: Date? = nil) async {
        #if canImport(UIKit)
        let fromDay = weekStart.map { math.dayString($0) } ?? math.dayString(from)
        let toDay = weekStart.map { math.dayString(math.addingDays(6, to: $0)) } ?? math.dayString(to)
        await produce(name: "tastetrace-\(kind.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))-\(fromDay).pdf") {
            let bundle = try await env.run { try await env.api.ledger(from: fromDay, to: toDay, tz: math.tzIdentifier) }
            return ReportRenderer.render(kind, bundle: bundle, math: math)
        }
        #else
        error = "PDF export needs iOS."
        #endif
    }

    private func produce(name: String, _ make: () async throws -> Data) async {
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let data = try await make()
            let url = tempFile(name)
            try data.write(to: url, options: .atomic)
            fileURL = url
        } catch let apiError as APIError { error = apiError.message } catch { self.error = error.localizedDescription }
    }
}

/// Picks a range, builds the file, then hands it to the share sheet.
struct ExportView: View {
    let kind: ReportKind?
    let weekStart: Date?
    @State private var model: ExportViewModel

    init(env: AppEnvironment, kind: ReportKind?, weekStart: Date? = nil) {
        self.kind = kind
        self.weekStart = weekStart
        _model = State(initialValue: ExportViewModel(env: env))
    }

    var body: some View {
        @Bindable var model = model
        TTScreen {
            InfoBanner(emoji: "📄", title: kind?.rawValue ?? "Raw Data (CSV)",
                       message: kind == nil ? "Every meal and symptom in the range, one row each, with ingredients and cook methods."
                                            : "A shareable summary of your logs and the associations TasteTrace observed, formatted for a dietitian or gastroenterologist.")
            if weekStart == nil {
                TTCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Date range")
                        DatePicker("From", selection: $model.from, in: ...model.to, displayedComponents: .date)
                        DatePicker("To", selection: $model.to, in: model.from...Date(), displayedComponents: .date)
                    }
                    .environment(\.calendar, model.math.calendar)
                    .environment(\.timeZone, model.math.timeZone)
                }
            }
            if let url = model.fileURL {
                TTCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ready: \(url.lastPathComponent)").font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                        ShareLink(item: url) {
                            Label("Share or save", systemImage: "square.and.arrow.up")
                                .font(TTFont.cardTitle).frame(maxWidth: .infinity).padding(.vertical, 14)
                                .foregroundStyle(.white).background(TTColor.primary, in: RoundedRectangle(cornerRadius: TTRadius.button))
                        }
                    }
                }
            }
            ErrorText(model.error)
        } bottom: {
            PinnedBottomBar {
                PrimaryButton(model.fileURL == nil ? "Generate" : "Regenerate", systemImage: "doc.badge.gearshape", isLoading: model.isBusy) {
                    Task {
                        if let kind { await model.exportPDF(kind, weekStart: weekStart) } else { await model.exportCSV() }
                    }
                }
            }
        }
        .navigationTitle(kind?.rawValue ?? "Export CSV")
    }
}
