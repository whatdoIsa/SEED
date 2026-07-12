import Foundation
import StoreKit
import Observation

/// 결제 (StoreKit 2) — 확정된 가격 구조:
/// - SEED Pro: 월 ₩3,300 / 연 ₩22,000 (전 트랙 + AI 코멘트 + 튜터 월 40문)
/// - 튜터 리필: 10문 ₩1,100 / 30문 ₩2,900 (소모성, 영구 크레딧)
/// - 트랙 단품: ₩5,000 일회성 영구 소장 (AI 미포함) — 트랙 2(ETF·분산투자)부터
@MainActor
@Observable
final class PurchaseStore {

    // ASC에서 초기 ID(seed.pro.monthly/yearly)를 삭제해 영구 잠김 → .v2로 재등록
    static let proMonthlyID = "seed.pro.monthly.v2"
    static let proYearlyID = "seed.pro.yearly.v2"
    static let refill10ID = "seed.tutor.refill10"
    static let refill30ID = "seed.tutor.refill30"
    static let trackETFID = "seed.track.etf"

    private static let allIDs = [proMonthlyID, proYearlyID, refill10ID, refill30ID, trackETFID]

    private(set) var products: [Product] = []
    private(set) var isPro = false
    /// 영구 소장한 트랙 단품 (비소모성)
    private(set) var ownedTrackIDs: Set<String> = []
    private(set) var isLoading = false

    /// 트랙 2(ETF·분산투자) 접근권 — Pro 구독 또는 단품 소장.
    var ownsETFTrack: Bool { isPro || ownedTrackIDs.contains(Self.trackETFID) }

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

    /// 상품 로드 실패 원인 — 페이월이 DEBUG에서 노출해 진단을 돕는다
    private(set) var lastLoadError: String?

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: Self.allIDs)
            lastLoadError = products.isEmpty
                ? "상품 0개 로드 — StoreKit Configuration이 이 실행에 주입되지 않았을 가능성 (Xcode ▶︎ Run으로 실행했는지, Edit Scheme > Run > Options > StoreKit Configuration 확인)"
                : nil
        } catch {
            products = []
            lastLoadError = "\(error)"
        }
        #if DEBUG
        print("[StoreKit] products=\(products.count) error=\(lastLoadError ?? "none")")
        #endif
    }

    func product(_ id: String) -> Product? {
        products.first { $0.id == id }
    }

    // MARK: 구매

    func purchase(_ product: Product) async {
        guard let result = try? await product.purchase() else { return }
        if case .success(let verification) = result {
            await handle(verification)
            if case .verified = verification {
                Analytics.log(.purchaseCompleted, ["product": product.id])
            }
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
        var tracks: Set<String> = []
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.productID == Self.proMonthlyID
                || transaction.productID == Self.proYearlyID {
                pro = true
            }
            if transaction.productType == .nonConsumable {
                tracks.insert(transaction.productID)
            }
        }
        isPro = pro
        ownedTrackIDs = tracks
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
