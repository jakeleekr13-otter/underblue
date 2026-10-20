import Foundation
import Observation
import StoreKit
import os

@MainActor @Observable
final class PurchaseStore {
    #if os(macOS)
    static let productID = "com.underblue.mac.pro"
    #else
    static let productID = "com.underblue.pro"
    #endif
    private(set) var product: Product?
    private(set) var isPro = false
    private(set) var busy = false
    private var entitlementGeneration = 0
    /// Set when a verified, non-revoked purchase arrives in this session. Keeps Pro on if a later
    /// entitlement refresh comes back empty. A revoked transaction clears it.
    private var unlockedBySession = false
    #if DEBUG
    /// Debug builds log how each purchase record was judged. Filter the Xcode console by "purchase".
    private static let logger = Logger(subsystem: "com.underblue.app", category: "purchase")
    #endif
    var message: String?
    @ObservationIgnored private var updates: Task<Void, Never>?
    private let diagnostics: DiagnosticRecorder?
    init(diagnostics: DiagnosticRecorder? = nil) {
        self.diagnostics = diagnostics
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                if case .verified(let transaction) = result, transaction.productID == Self.productID {
                    self.accept(transaction)
                    await transaction.finish()
                }
            }
        }
    }
    isolated deinit { updates?.cancel() }
    func load() async {
        await refreshEntitlement()
        do {
            let found = try await SafeReadRetry().run(operation: .productLoading) { try await Product.products(for: [Self.productID]) }
            #if DEBUG
            Self.logger.notice("purchase: product request returned \(found.count) products: \(found.map(\.id).joined(separator: ","), privacy: .public) wanted=\(Self.productID, privacy: .public)")
            #endif
            product = found.first { $0.type == .nonConsumable }
            if product == nil { message = String(localized: "The purchase is currently unavailable. Please try again later.") }
        } catch { report(error, operation: .productLoading) }
    }
    func refreshEntitlement() async {
        entitlementGeneration += 1
        let generation = entitlementGeneration
        var owned = false
        #if DEBUG
        var seen = 0
        #endif
        for await result in Transaction.currentEntitlements {
            #if DEBUG
            seen += 1
            switch result {
            case .verified(let t):
                Self.logger.notice("purchase: entitlement VERIFIED product=\(t.productID, privacy: .public) type=\(t.productType.rawValue, privacy: .public) environment=\(t.environment.rawValue, privacy: .public) revoked=\(t.revocationDate != nil) wanted=\(Self.productID, privacy: .public)")
            case .unverified(let t, let error):
                Self.logger.notice("purchase: entitlement UNVERIFIED product=\(t.productID, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
            #endif
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.productType == .nonConsumable,
               transaction.revocationDate == nil { owned = true }
        }
        if !owned, case .verified(let latest)? = await Transaction.latest(for: Self.productID),
           latest.productType == .nonConsumable, latest.revocationDate == nil {
            // Sandbox can leave currentEntitlements empty after a purchase. The latest record still shows it.
            owned = true
            #if DEBUG
            Self.logger.notice("purchase: owned from Transaction.latest environment=\(latest.environment.rawValue, privacy: .public)")
            #endif
        }
        #if DEBUG
        Self.logger.notice("purchase: refresh done entitlements=\(seen) owned=\(owned) session=\(self.unlockedBySession) applied=\(generation == self.entitlementGeneration) wanted=\(Self.productID, privacy: .public)")
        #endif
        if generation == entitlementGeneration { isPro = owned || unlockedBySession }
    }
    private func accept(_ transaction: Transaction) {
        #if DEBUG
        Self.logger.notice("purchase: accept product=\(transaction.productID, privacy: .public) environment=\(transaction.environment.rawValue, privacy: .public) revoked=\(transaction.revocationDate != nil)")
        #endif
        entitlementGeneration += 1
        let unlocked = transaction.productType == .nonConsumable && transaction.revocationDate == nil
        unlockedBySession = unlocked
        isPro = unlocked
    }
    func purchase() async {
        guard let product, !busy else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result, transaction.productID == Self.productID else {
                    message = String(localized: "Your purchase couldn’t be verified. Please try Restore Purchase."); return
                }
                accept(transaction)
                await transaction.finish()
                message = isPro ? String(localized: "UnderBlue Pro is unlocked.") : String(localized: "Your purchase is being verified. Try Restore Purchase shortly.")
            case .userCancelled: break
            case .pending: message = String(localized: "Your purchase is pending approval. Pro will unlock when it’s approved.")
            @unknown default: message = String(localized: "The purchase couldn’t finish. Please try again.")
            }
        } catch StoreKitError.userCancelled { message = nil }
        catch { report(error, operation: .purchase) }
    }
    func restore() async {
        guard !busy else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            message = isPro ? String(localized: "Purchase restored.") : String(localized: "No UnderBlue Pro purchase was found for this Apple Account.")
        } catch { report(error, operation: .restore) }
    }
    /// Called when Apple's offer code sheet closes. A redeemed code arrives as a transaction in
    /// Transaction.updates, which the listener above accepts; this only refreshes and reports.
    func redeemFinished(_ result: Result<Void, Error>) async {
        switch result {
        case .success:
            await refreshEntitlement()
            message = isPro ? String(localized: "UnderBlue Pro is unlocked.") : nil
        case .failure(let error): report(error, operation: .purchase)
        }
    }
    private func report(_ error: Error, operation: Operation) {
        #if DEBUG
        let bridged = error as NSError
        Self.logger.notice("purchase: \(operation.rawValue, privacy: .public) FAILED domain=\(bridged.domain, privacy: .public) code=\(bridged.code) \(String(describing: error), privacy: .public)")
        #endif
        let failure = Failure.classify(error, operation: operation)
        Task { await diagnostics?.record(failure, operation: operation) }
        message = failure.kind == .cancelled ? nil : Failure(kind: .storeUnavailable, domain: failure.domain, code: failure.code).message
    }
}
