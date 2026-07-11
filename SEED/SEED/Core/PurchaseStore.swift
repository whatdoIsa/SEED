import Foundation
import StoreKit
import Observation

/// 결제 (StoreKit 2) — 확정된 가격 구조:
/// - SEED Pro: 월 ₩3,300 / 연 ₩22,000 (전 트랙[예정] + AI 코멘트 + 튜터 월 40문)
/// - 튜터 리필: 10문 ₩1,100 / 30문 ₩2,900 (소모성, 영구 크레딧)
/// - 트랙 단품(₩5,000, 영구 소장)은 트랙 2 출시와 함께 추가 예정
@MainActor
@Observable
final class PurchaseStore {

    static let proMonthlyID = "seed.pro.monthly"
    static let proYearlyID = "seed.pro.yearly"
    static let refill10ID = "seed.tutor.refill10"
    static let refill30ID = "seed.tutor.refill30"

    private static let allIDs = [proMonthlyID, proYearlyID, refill10ID, refill30ID]

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var isLoading = false

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = Task { [weak self] in
            // 앱 밖 결제(가족 공유·환불·갱신)도 이 스트림으로 들어온다
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    // MARK: 상품

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        products = (try? await Product.products(for: Self.allIDs)) ?? []
    }

    func product(_ id: String) -> Product? {
        products.first { $0.id == id }
    }

    // MARK: 구매

    func purchase(_ product: Product) async {
        guard let result = try? await product.purchase() else { return }
        if case .success(let verification) = result {
            await handle(verification)
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    // MARK: 트랜잭션 처리

    private func handle(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else { return }

        switch transaction.productType {
        case .consumable:
            grantConsumableOnce(transaction)
        default:
            await refreshEntitlements()
        }
        await transaction.finish()
    }

    /// 소모성 크레딧은 정확히 한 번만 지급 (재시도·중복 전달 방어)
    private func grantConsumableOnce(_ transaction: Transaction) {
        let grantedKey = "seed.iap.granted"
        var granted = Set(UserDefaults.standard.stringArray(forKey: grantedKey) ?? [])
        let txID = String(transaction.id)
        guard !granted.contains(txID) else { return }
        granted.insert(txID)
        UserDefaults.standard.set(Array(granted), forKey: grantedKey)

        switch transaction.productID {
        case Self.refill10ID: TutorQuota.addCredits(10)
        case Self.refill30ID: TutorQuota.addCredits(30)
        default: break
        }
    }

    func refreshEntitlements() async {
        var pro = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.productID == Self.proMonthlyID
                || transaction.productID == Self.proYearlyID {
                pro = true
            }
        }
        isPro = pro
        if pro { grantMonthlyProCreditsIfNeeded() }
    }

    /// Pro: 매월 튜터 40문 지급 (달이 바뀌면 1회)
    private func grantMonthlyProCreditsIfNeeded() {
        let key = "seed.pro.creditMonth"
        let parts = Calendar.current.dateComponents([.year, .month], from: .now)
        let month = (parts.year ?? 0) * 100 + (parts.month ?? 0)
        guard UserDefaults.standard.integer(forKey: key) != month else { return }
        UserDefaults.standard.set(month, forKey: key)
        TutorQuota.addCredits(40)
    }
}
