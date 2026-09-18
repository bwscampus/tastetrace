import Foundation
import TasteTraceAPI
import TasteTraceCore

/// Which report to render from the ledger bundle.
enum ReportKind: String, CaseIterable, Identifiable {
    case practitioner = "Practitioner Report"
    case weeklyDigest = "Weekly Digest Report"
    case evidenceLedger = "Doctor Evidence Ledger"
    var id: String { rawValue }
}

#if canImport(UIKit)
import UIKit

/// Simple flowing-text PDF renderer (US Letter) shared by the three reports.
final class PDFDocumentBuilder {
    private let pageSize = CGRect(x: 0, y: 0, width: 612, height: 792)
    private let margin: CGFloat = 48
    private var cursorY: CGFloat = 0
    private var context: UIGraphicsPDFRendererContext?
    private let title: String

    init(title: String) { self.title = title }

    private var contentWidth: CGFloat { pageSize.width - margin * 2 }

    func render(_ body: (PDFDocumentBuilder) -> Void) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageSize, format: UIGraphicsPDFRendererFormat())
        return renderer.pdfData { ctx in
            context = ctx
            newPage()
            body(self)
        }
    }

    private func newPage() {
        context?.beginPage()
        cursorY = margin
        text(title, size: 10, weight: .semibold, color: .gray)
        cursorY += 6
    }

    private func ensure(_ height: CGFloat) {
        if cursorY + height > pageSize.height - margin { newPage() }
    }

    func heading(_ string: String) {
        cursorY += 10
        text(string, size: 18, weight: .bold)
        cursorY += 4
    }

    func subheading(_ string: String) {
        cursorY += 6
        text(string, size: 13, weight: .semibold)
    }

    func paragraph(_ string: String) {
        text(string, size: 11, weight: .regular)
        cursorY += 4
    }

    func bullet(_ string: String) {
        text("•  " + string, size: 11, weight: .regular, indent: 12)
    }

    func keyValue(_ key: String, _ value: String) {
        text("\(key): \(value)", size: 11, weight: .regular)
    }

    func spacer(_ height: CGFloat = 8) { cursorY += height }

    private func text(_ string: String, size: CGFloat, weight: UIFont.Weight, color: UIColor = .black, indent: CGFloat = 0) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let width = contentWidth - indent
        let bounds = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        ensure(bounds.height + 4)
        attributed.draw(with: CGRect(x: margin + indent, y: cursorY, width: width, height: bounds.height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        cursorY += bounds.height + 4
    }
}

enum ReportRenderer {
    static func render(_ kind: ReportKind, bundle: LedgerBundle, math: DateMath) -> Data {
        let builder = PDFDocumentBuilder(title: "TasteTrace • \(kind.rawValue) • \(bundle.range.from) to \(bundle.range.to)")
        return builder.render { b in
            b.heading(kind.rawValue)
            b.paragraph("Prepared for \(bundle.shownName) (\(bundle.profile?.email ?? "")). Generated \(Formatting.longDay(bundle.generatedAt, math: math)). Times shown in \(bundle.range.tz).")
            b.paragraph("This report lists self-logged meals and symptoms and the statistical associations TasteTrace observed between them. Associations are not diagnoses.")
            switch kind {
            case .practitioner:
                overview(b, bundle)
                triggers(b, bundle)
                dailyLedger(b, bundle, math: math)
            case .weeklyDigest:
                for week in bundle.digestWeeks.prefix(1) { digest(b, week, math: math) }
                triggers(b, bundle)
            case .evidenceLedger:
                triggers(b, bundle)
                dailyLedger(b, bundle, math: math)
            }
        }
    }

    private static func overview(_ b: PDFDocumentBuilder, _ bundle: LedgerBundle) {
        b.subheading("Overview")
        b.keyValue("Period", "\(bundle.range.from) – \(bundle.range.to)")
        b.keyValue("Meals logged", "\(bundle.totals.meals)")
        b.keyValue("Symptoms logged", "\(bundle.totals.symptoms)")
        b.keyValue("Days with entries", "\(bundle.totals.days)")
        b.keyValue("Correlation window", "\(bundle.settings.correlationWindowHours) hours")
        if let tags = bundle.profile?.sensitivityTags, !tags.isEmpty { b.keyValue("Self-reported sensitivities", tags.joined(separator: ", ")) }
        if let purpose = bundle.profile?.discoveryPurpose, !purpose.isEmpty { b.keyValue("Discovery purpose", purpose) }
    }

    private static func triggers(_ b: PDFDocumentBuilder, _ bundle: LedgerBundle) {
        b.subheading("Observed associations (≥ \(bundle.settings.minConfidence)% confidence)")
        if bundle.triggers.isEmpty { b.paragraph("No associations above the confidence floor yet."); return }
        for t in bundle.triggers.prefix(25) {
            let onset = t.avgOnsetHours.map { String(format: ", avg onset %.1f h", $0) } ?? ""
            b.bullet("\(t.foodName.capitalizedFirst) → \(t.symptomName): \(t.confidence)% (\(t.tier)), followed by the symptom \(t.flareExposures) of \(t.exposures) times\(onset) [\(t.dimension.replacingOccurrences(of: "_", with: " "))]")
        }
    }

    private static func digest(_ b: PDFDocumentBuilder, _ week: WeeklyDigest, math: DateMath) {
        b.subheading("Week \(week.weekStart) – \(week.weekEnd)")
        b.keyValue("Weekly discomfort index", String(format: "%.1f / 10 (baseline %.1f)", week.trends.index, week.trends.baselineIndex))
        b.keyValue("Symptom occurrences", "\(week.trends.occurrences) in \(week.trends.flares) flare(s)")
        b.keyValue("Discomfort-free days", "\(week.trends.discomfortFreeDays)")
        b.keyValue("Meal log depth", "\(Int((week.trends.mealLogDepth * 100).rounded()))% of breakfast/lunch/dinner slots")
        for day in week.trends.days { b.bullet("\(day.weekday) \(day.date): index \(Int(day.index)), \(day.occurrences) occurrence(s)") }
        for card in week.symptoms.cards {
            b.bullet("\(card.name): \(card.occurrences)× , avg severity \(String(format: "%.1f", card.avgSeverity10))/10\(card.avgDurationMinutes.map { ", avg \($0) min" } ?? "")\(card.topTriggers.isEmpty ? "" : ", top triggers: " + card.topTriggers.joined(separator: ", "))")
        }
        let w = week.symptoms.onsetWindows
        b.keyValue("Onset after last meal", "<1 h: \(w.under1h), 1–3 h: \(w.from1to3h), 3 h+: \(w.over3h), no meal in window: \(w.unmatched)")
    }

    private static func dailyLedger(_ b: PDFDocumentBuilder, _ bundle: LedgerBundle, math: DateMath) {
        b.subheading("Daily ledger")
        for day in bundle.days {
            b.spacer(4)
            b.keyValue(day.date, "\(day.meals.count) meal(s), \(day.symptoms.count) symptom(s), \(day.flares) flare(s)")
            let items: [(Date, String)] = day.meals.map { m in
                let details = m.ingredientDetails ?? m.ingredientNames.map { IngredientDetail(name: $0) }
                let ingredients = details.map { detail -> String in
                    guard let method = detail.cookMethod else { return detail.name }
                    return "\(detail.name) (\(method.replacingOccurrences(of: "_", with: " ")))"
                }
                let flag = (m.suspiciousFor ?? []).isEmpty ? "" : " — followed by \((m.suspiciousFor ?? []).joined(separator: ", "))"
                return (m.timestamp, "\(Formatting.time(m.timestamp, math: math)) \(m.mealType): \(m.name)\(ingredients.isEmpty ? "" : " — " + ingredients.joined(separator: ", "))\(flag)")
            } + day.symptoms.map { s in
                (s.timestamp, "\(Formatting.time(s.timestamp, math: math)) Symptom: \(s.name), level \(s.resolvedIntensity)/5 (\(s.severity))\(s.durationMinutes.map { ", \($0) min" } ?? "")\(s.notes.map { $0.isEmpty ? "" : " — \($0)" } ?? "")")
            }
            for (_, line) in items.sorted(by: { $0.0 < $1.0 }) { b.bullet(line) }
        }
    }
}
#endif
