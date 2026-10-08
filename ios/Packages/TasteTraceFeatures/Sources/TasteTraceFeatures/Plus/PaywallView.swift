import SwiftUI
import StoreKit
import TasteTraceUI

/// What the user tried to open when the paywall appeared; picks the headline.
public enum PaywallReason: String, Hashable, Sendable {
    case upgrade, history, freeWindowEnded, insights, charts, export, reminders

    var emoji: String {
        switch self {
        case .upgrade: return "🔎"
        case .history: return "📅"
        case .freeWindowEnded: return "🗂️"
        case .insights: return "🕵️"
        case .charts: return "📈"
        case .export: return "📄"
        case .reminders: return "🔔"
        }
    }

    var title: String {
        switch self {
        case .upgrade: return "Solve the case with TasteTrace Plus"
        case .history: return "See your full history"
        case .freeWindowEnded: return "You've logged for 14 days"
        case .insights: return "Unlock every suspect"
        case .charts: return "Full charts and timelines"
        case .export: return "Share a PDF report"
        case .reminders: return "Custom reminders"
        }
    }

    var message: String {
        switch self {
        case .upgrade:
            return "Logging stays free. Plus does the detective work: every pattern TasteTrace finds between your food and your symptoms."
        case .history:
            return "Free accounts see the last \(PlusStore.freeHistoryDays) days. Plus keeps every day you've logged."
        case .freeWindowEnded:
            return "Your clues are piling up. Plus keeps your full history and shows every suspect TasteTrace finds."
        case .insights:
            return "Free accounts get one preview insight. Plus shows all of them, updated weekly."
        case .charts:
            return "Symptom breakdowns, the food suspect digest and every week's timeline."
        case .export:
            return "A clean PDF of your logs and patterns for your doctor or dietitian."
        case .reminders:
            return "Pick your own nudge time and get check-ins after breakfast, lunch and dinner."
        }
    }
}

extension Router {
    /// Runs `action` for Plus members; everyone else sees the paywall.
    func requirePlus(_ plus: PlusStore, _ reason: PaywallReason, _ action: () -> Void) {
        if plus.isPlus { action() } else { sheet = .paywall(reason) }
    }
}

struct PaywallView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    let reason: PaywallReason

    @State private var plan: PlusPlan = .annual
    @State private var codeInput = ""
    @State private var promo: PromoCode?
    @State private var codeError: String?
    @State private var showRedeemSheet = false

    private var plus: PlusStore { env.plus }

    var body: some View {
        TTScreen {
            hero
            if plus.isPlus {
                InfoBanner(emoji: "✅", title: "You're a Plus member", message: "Everything is unlocked. Thanks for supporting TasteTrace!", tone: .success)
            } else {
                comparison
                planPicker
                promoCard
                ErrorText(plus.purchaseError)
                legal
            }
        } bottom: {
            PinnedBottomBar {
                if plus.isPlus {
                    PrimaryButton("Done") { router.sheet = nil }
                } else {
                    PrimaryButton(subscribeTitle, systemImage: "sparkles", isLoading: plus.isPurchasing) { subscribe() }
                    Button("Restore Purchases") { Task { await plus.restore() } }
                        .font(TTFont.bodySemibold).foregroundStyle(TTColor.primary)
                }
            }
        }
        .navigationTitle("TasteTrace Plus")
        .task { if plus.products.isEmpty { await plus.start() } }
        .onChange(of: plus.isPlus) { _, isPlus in if isPlus { router.sheet = nil } }
        #if os(iOS)
        .offerCodeRedemption(isPresented: $showRedeemSheet) { _ in
            Task { await plus.refreshEntitlements() }
        }
        #endif
    }

    private var hero: some View {
        HeroGradientCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("THE CLUES ARE FREE. SOLVING THE CASE IS PLUS.")
                    .font(TTFont.captionSemibold).tracking(1).foregroundStyle(TTColor.successTint)
                HStack(alignment: .top, spacing: 10) {
                    Text(reason.emoji).font(.system(size: 34))
                    Text(reason.title).font(.system(size: 26, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                }
                Text(reason.message).font(TTFont.body).opacity(0.9)
            }
        }
    }

    private var comparison: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Free").font(TTFont.captionSemibold).foregroundStyle(TTColor.textSecondary).frame(width: 84)
                    Text("Plus").font(TTFont.captionSemibold).foregroundStyle(TTColor.primary).frame(width: 84)
                }
                row("Food & symptom logging", "Unlimited", "Unlimited")
                row("History", "Last \(PlusStore.freeHistoryDays) days", "Full history")
                row("Pattern insights", "1 preview", "All, weekly")
                row("Trend charts", "Basic", "Full + timelines")
                row("PDF report for your doctor", "—", "✓")
                row("Reminders", "Basic", "Custom")
            }
        }
    }

    private func row(_ feature: String, _ free: String, _ paid: String) -> some View {
        HStack(alignment: .top) {
            Text(feature).font(TTFont.body).foregroundStyle(TTColor.navy).frame(maxWidth: .infinity, alignment: .leading)
            Text(free).font(TTFont.caption).foregroundStyle(TTColor.textSecondary).frame(width: 84).multilineTextAlignment(.center)
            Text(paid).font(TTFont.captionSemibold).foregroundStyle(TTColor.primary).frame(width: 84).multilineTextAlignment(.center)
        }
    }

    private var planPicker: some View {
        VStack(spacing: 10) {
            planOption(.annual, title: "Annual",
                       price: "\(plus.price(.annual, percentOff: percentOff(.annual))) / year",
                       detail: "About \(plus.monthlyEquivalent(percentOff: percentOff(.annual))) a month",
                       badge: "Best value")
            planOption(.monthly, title: "Monthly",
                       price: "\(plus.price(.monthly, percentOff: percentOff(.monthly))) / month",
                       detail: "Cancel anytime", badge: nil)
        }
    }

    private func planOption(_ option: PlusPlan, title: String, price: String, detail: String, badge: String?) -> some View {
        let selected = plan == option
        return Button { plan = option } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3).foregroundStyle(selected ? TTColor.primary : TTColor.dot)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title).font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                        if let badge { StatusBadge(badge, tone: .success) }
                    }
                    Text(detail).font(TTFont.caption).foregroundStyle(TTColor.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if percentOff(option) > 0 {
                        Text(plus.price(option)).font(TTFont.caption).strikethrough().foregroundStyle(TTColor.textSecondary)
                    }
                    Text(price).font(TTFont.bodySemibold).foregroundStyle(TTColor.navy)
                }
            }
            .padding(14)
            .background(selected ? TTColor.infoTint : TTColor.card, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(selected ? TTColor.primary : TTColor.cardBorder, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private var promoCard: some View {
        TTCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("PROMO CODE").font(TTFont.captionSemibold).tracking(0.8).foregroundStyle(TTColor.textSecondary)
                HStack(spacing: 8) {
                    TextField("Enter code", text: $codeInput)
                        .promoCodeKeyboard()
                        .font(TTFont.body).foregroundStyle(TTColor.inputText)
                        .padding(12)
                        .background(TTColor.background, in: RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: TTRadius.tile, style: .continuous).stroke(TTColor.cardBorder, lineWidth: 1))
                        .onSubmit(applyCode)
                    Button(promo == nil ? "Apply" : "Remove") { if promo == nil { applyCode() } else { removeCode() } }
                        .font(TTFont.bodySemibold).foregroundStyle(TTColor.primary)
                        .padding(.horizontal, 8)
                }
                if let promo {
                    Text("✓ \(promo.code): \(promo.percentOff)% off your first year of the annual plan (\(promo.audience.lowercased())).")
                        .font(TTFont.caption).foregroundStyle(TTColor.success)
                }
                if let codeError {
                    Text(codeError).font(TTFont.caption).foregroundStyle(TTColor.danger)
                }
            }
        }
    }

    private var legal: some View {
        VStack(spacing: 6) {
            Text("Payment is charged to your Apple ID. Plus renews automatically at the regular price unless cancelled at least 24 hours before the end of the period; manage or cancel anytime in your App Store account settings.")
                .font(.system(size: 11)).foregroundStyle(TTColor.textSecondary).multilineTextAlignment(.center)
            Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                .font(TTFont.captionSemibold)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private var subscribeTitle: String {
        if let promo, plan == PromoCode.plan { return "Redeem \(promo.code)" }
        return plan == .annual ? "Start Plus · \(plus.price(.annual)) / year" : "Start Plus · \(plus.price(.monthly)) / month"
    }

    private func percentOff(_ option: PlusPlan) -> Int {
        option == PromoCode.plan ? (promo?.percentOff ?? 0) : 0
    }

    private func applyCode() {
        guard let match = PromoCode.match(codeInput) else {
            promo = nil
            codeError = codeInput.trimmingCharacters(in: .whitespaces).isEmpty ? nil : "That code isn't valid."
            return
        }
        promo = match
        codeInput = match.code
        codeError = nil
        plan = PromoCode.plan
    }

    private func removeCode() {
        promo = nil
        codeInput = ""
    }

    private func subscribe() {
        // A promo code is an App Store offer code, so Apple's sheet applies the discount
        if let promo, plan == PromoCode.plan {
            if let url = plus.offerCodeURL(promo.code) {
                openURL(url)
            } else {
                showRedeemSheet = true
            }
            return
        }
        Task { _ = await plus.purchase(plan) }
    }
}

private extension View {
    @ViewBuilder
    func promoCodeKeyboard() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.characters).autocorrectionDisabled()
        #else
        self
        #endif
    }
}

/// Stand-in for a locked screen or section, with a button to the paywall.
struct PlusLockedCard: View {
    @Environment(Router.self) private var router
    let reason: PaywallReason
    var title: String? = nil
    var message: String? = nil

    var body: some View {
        TTCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").foregroundStyle(TTColor.primary)
                    Text(title ?? reason.title).font(TTFont.cardTitle).foregroundStyle(TTColor.navy)
                    Spacer()
                    StatusBadge("Plus", tone: .primary)
                }
                Text(message ?? reason.message).font(TTFont.body).foregroundStyle(TTColor.textSecondary)
                PrimaryButton("Unlock with TasteTrace Plus", systemImage: "sparkles") { router.sheet = .paywall(reason) }
            }
        }
    }
}
