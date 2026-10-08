import Foundation
import Observation
import StoreKit
import TasteTraceCore

/// TasteTrace Plus plans. Prices live in App Store Connect; the fallbacks are
/// only shown until the App Store answers.
public enum PlusPlan: String, CaseIterable, Identifiable, Sendable {
    case annual, monthly

    public var id: String { rawValue }

    public var productID: String {
        switch self {
        case .annual: return "app.tastetrace.ios.plus.annual"
        case .monthly: return "app.tastetrace.ios.plus.monthly"
        }
    }

    var fallbackPrice: Decimal { self == .annual ? 30 : 5 }
    var periodLabel: String { self == .annual ? "year" : "month" }
}

/// Promo codes for Plus. Each is also an App Store offer code with the same
/// name and discount (set up in App Store Connect); this list is what the
/// paywall uses to recognise a code and show the discounted price.
public struct PromoCode: Equatable, Sendable {
    public let code: String
    public let percentOff: Int
    public let audience: String

    public static let all = [
        PromoCode(code: "TASTETRACE20", percentOff: 20, audience: "Friends, family & beta testers"),
        PromoCode(code: "TTWAITLIST", percentOff: 10, audience: "Waitlist members"),
    ]

    /// The plan App Store offer codes are attached to (a code belongs to one subscription).
    public static let plan: PlusPlan = .annual

    public static func match(_ text: String) -> PromoCode? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return all.first { $0.code == typed }
    }
}

/// Logging is free; insights are paid. Tracks the Plus entitlement with StoreKit 2.
@Observable
@MainActor
public final class PlusStore {
    /// Free accounts see this many days of history (today included).
    public static let freeHistoryDays = 14
    /// Days of logging before a free account gets its one preview insight.
    public static let insightPreviewDays = 7

    public private(set) var isPlus = false
    public private(set) var activePlan: PlusPlan?
    public private(set) var products: [PlusPlan: Product] = [:]
    public private(set) var isPurchasing = false
    public var purchaseError: String?

    private let appStoreID: String?
    private var updatesTask: Task<Void, Never>?

    public init(appStoreID: String? = nil) {
        self.appStoreID = appStoreID
    }

    /// Listens for renewals, refunds and redeemed offer codes, then loads prices and the entitlement.
    public func start() async {
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                for await update in Transaction.updates {
                    if case .verified(let transaction) = update { await transaction.finish() }
                    await self?.refreshEntitlements()
                }
            }
        }
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        guard let loaded = try? await Product.products(for: PlusPlan.allCases.map(\.productID)) else { return }
        for product in loaded {
            if let plan = PlusPlan.allCases.first(where: { $0.productID == product.id }) { products[plan] = product }
        }
    }

    public func refreshEntitlements() async {
        var plan: PlusPlan?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            if let match = PlusPlan.allCases.first(where: { $0.productID == transaction.productID }) { plan = match }
        }
        activePlan = plan
        isPlus = plan != nil
    }

    /// True once the purchase went through and Plus is active.
    public func purchase(_ plan: PlusPlan) async -> Bool {
        purchaseError = nil
        if products[plan] == nil { await loadProducts() }
        guard let product = products[plan] else {
            purchaseError = "The App Store isn't reachable right now. Try again in a moment."
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseError = "The App Store couldn't verify that purchase."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return isPlus
            case .pending:
                purchaseError = "Your purchase is waiting for approval."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    public func restore() async {
        purchaseError = nil
        do { try await AppStore.sync() } catch { purchaseError = error.localizedDescription }
        await refreshEntitlements()
        if !isPlus && purchaseError == nil { purchaseError = "No TasteTrace Plus subscription was found for this Apple ID." }
    }

    // MARK: Prices

    /// "$30.00", or the price after a promo code's discount.
    public func price(_ plan: PlusPlan, percentOff: Int = 0) -> String {
        format(basePrice(plan) * Decimal(100 - percentOff) / 100, plan)
    }

    /// The annual price spread over 12 months: "$2.50".
    public func monthlyEquivalent(percentOff: Int = 0) -> String {
        format(basePrice(.annual) * Decimal(100 - percentOff) / 100 / 12, .annual)
    }

    private func basePrice(_ plan: PlusPlan) -> Decimal { products[plan]?.price ?? plan.fallbackPrice }

    private func format(_ value: Decimal, _ plan: PlusPlan) -> String {
        if let product = products[plan] { return value.formatted(product.priceFormatStyle) }
        return value.formatted(.currency(code: "USD"))
    }

    // MARK: Offer codes

    /// App Store link that opens the redemption sheet with the code filled in;
    /// nil until APP_STORE_ID is set, when the app shows Apple's blank sheet instead.
    public func offerCodeURL(_ code: String) -> URL? {
        guard let appStoreID, !appStoreID.isEmpty else { return nil }
        var components = URLComponents(string: "https://apps.apple.com/redeem")!
        components.queryItems = [
            URLQueryItem(name: "ctx", value: "offercodes"),
            URLQueryItem(name: "id", value: appStoreID),
            URLQueryItem(name: "code", value: code),
        ]
        return components.url
    }

    // MARK: Free tier

    /// The oldest day a free account can open.
    public func earliestFreeDay(math: DateMath) -> Date {
        math.addingDays(-(Self.freeHistoryDays - 1), to: math.startOfDay(Date()))
    }

    public func canOpen(day: Date, math: DateMath) -> Bool {
        isPlus || math.startOfDay(day) >= earliestFreeDay(math: math)
    }
}
