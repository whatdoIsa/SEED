import Foundation
import Observation

/// 공유 계좌 원장 (다종목) — 현금은 하나, 보유는 종목별.
/// 여러 MarketEngine이 같은 원장을 참조해 "A를 팔아 B를 산다"가 자연히 성립한다.
@Observable
public final class AccountLedger {

    public struct Holding: Equatable {
        public var qty: Int = 0
        public var avgCost: Double = 0
        public var reservedShares: Int = 0
        public var availableShares: Int { qty - reservedShares }
    }

    public private(set) var cash: Int
    public private(set) var reservedCash: Int = 0
    public private(set) var holdings: [String: Holding] = [:]
    public private(set) var realizedPnL: Double = 0
    public private(set) var feesPaid: Int = 0

    public init(cash: Int) {
        self.cash = cash
    }

    public var availableCash: Int { cash - reservedCash }

    /// 스냅샷 복원 — 아주 긴 시즌에서 전체 리플레이 대신 계좌만 되살릴 때 (앱 전용).
    /// 예약(미체결)은 복원하지 않는다 — 호출 측에서 대기 주문을 비운 상태를 전제.
    public func restore(cash: Int,
                        realizedPnL: Double,
                        feesPaid: Int,
                        holdings: [String: (qty: Int, avgCost: Double)]) {
        self.cash = cash
        self.realizedPnL = realizedPnL
        self.feesPaid = feesPaid
        self.reservedCash = 0
        self.holdings = holdings.mapValues { Holding(qty: $0.qty, avgCost: $0.avgCost) }
    }

    public func holding(of symbol: String) -> Holding {
        holdings[symbol] ?? Holding()
    }

    public func qty(of symbol: String) -> Int { holding(of: symbol).qty }
    public func avgCost(of symbol: String) -> Double { holding(of: symbol).avgCost }
    public func availableShares(of symbol: String) -> Int { holding(of: symbol).availableShares }

    /// 총평가: 종목별 현재가를 받아 현금 + 전체 보유 가치를 계산.
    public func totalEquity(prices: [String: Int]) -> Int {
        cash + holdings.reduce(0) { sum, entry in
            // 보유 종목의 가격 누락은 호출 측 버그 — 총자산이 조용히 줄어 보인다
            assert(entry.value.qty == 0 || prices[entry.key] != nil,
                   "totalEquity: '\(entry.key)' 가격 누락")
            return sum + entry.value.qty * (prices[entry.key] ?? 0)
        }
    }

    // MARK: 체결 반영 (엔진 전용)

    func applyBuy(symbol: String, _ result: FillResult, fee: Int) {
        var holding = holding(of: symbol)
        let cost = result.notional
        let newQty = holding.qty + result.filledQty
        if newQty > 0 {
            // 취득원가에 매수 수수료 산입 (증권사 관행) — 평단이 '본전가'가 되고,
            // 매도 시 실현손익이 양쪽 수수료를 모두 반영해 Σ실현손익 = 현금 변화가 성립한다.
            holding.avgCost = (holding.avgCost * Double(holding.qty) + Double(cost + fee)) / Double(newQty)
        }
        holding.qty = newQty
        holdings[symbol] = holding
        cash -= cost + fee
        feesPaid += fee
    }

    func applySell(symbol: String, _ result: FillResult, fee: Int) {
        var holding = holding(of: symbol)
        let proceeds = result.notional
        realizedPnL += Double(proceeds - fee) - holding.avgCost * Double(result.filledQty)
        holding.qty -= result.filledQty
        if holding.qty == 0 { holding.avgCost = 0 }
        holdings[symbol] = holding
        cash += proceeds - fee
        feesPaid += fee
    }

    // MARK: 지정가 예약·정산 (엔진 전용)

    func reserveCash(_ amount: Int) { reservedCash += amount }
    func releaseCash(_ amount: Int) { reservedCash = max(reservedCash - amount, 0) }

    func reserveShares(symbol: String, _ amount: Int) {
        var holding = holding(of: symbol)
        holding.reservedShares += amount
        holdings[symbol] = holding
    }

    func releaseShares(symbol: String, _ amount: Int) {
        var holding = holding(of: symbol)
        holding.reservedShares = max(holding.reservedShares - amount, 0)
        holdings[symbol] = holding
    }

    /// release: 전역 예약 풀에서 해제할 금액 — 호출 측(엔진)이 이 주문의 잔여 예약 한도로
    /// 캡을 씌워 넘긴다. 청크별 수수료 반올림 합이 예약분을 넘어 다른 주문의 예약금을
    /// 갉아먹는 것을 막는다.
    func settleRestingBuy(symbol: String, price: Int, qty fillQty: Int, fee: Int, release: Int) {
        let cost = price * fillQty
        releaseCash(release)
        var holding = holding(of: symbol)
        let newQty = holding.qty + fillQty
        if newQty > 0 {
            // 매수 수수료 취득원가 산입 — applyBuy와 동일 정책
            holding.avgCost = (holding.avgCost * Double(holding.qty) + Double(cost + fee)) / Double(newQty)
        }
        holding.qty = newQty
        holdings[symbol] = holding
        cash -= cost + fee
        feesPaid += fee
    }

    func settleRestingSell(symbol: String, price: Int, qty fillQty: Int, fee: Int) {
        var holding = holding(of: symbol)
        holding.reservedShares = max(holding.reservedShares - fillQty, 0)
        realizedPnL += Double(price * fillQty - fee) - holding.avgCost * Double(fillQty)
        holding.qty -= fillQty
        if holding.qty == 0 { holding.avgCost = 0 }
        holdings[symbol] = holding
        cash += price * fillQty - fee
        feesPaid += fee
    }
}

// MARK: - 단일 종목 관점 스냅샷 (기존 API 호환)

/// 한 종목의 시선으로 본 계좌 — engine.portfolio가 돌려주는 값.
/// equity/unrealized는 이 종목만 계산한다 (전체 자산은 AccountLedger.totalEquity).
public struct PortfolioSnapshot {
    public let cash: Int
    public let reservedCash: Int
    public let availableCash: Int
    public let qty: Int
    public let reservedShares: Int
    public let availableShares: Int
    public let avgCost: Double
    public let realizedPnL: Double
    public let feesPaid: Int

    public func marketValue(at price: Int) -> Int { qty * price }
    public func equity(at price: Int) -> Int { cash + marketValue(at: price) }
    public func unrealizedPnL(at price: Int) -> Double {
        Double(qty) * (Double(price) - avgCost)
    }
}

public extension AccountLedger {
    func snapshot(for symbol: String) -> PortfolioSnapshot {
        let holding = holding(of: symbol)
        return PortfolioSnapshot(
            cash: cash,
            reservedCash: reservedCash,
            availableCash: availableCash,
            qty: holding.qty,
            reservedShares: holding.reservedShares,
            availableShares: holding.availableShares,
            avgCost: holding.avgCost,
            realizedPnL: realizedPnL,
            feesPaid: feesPaid
        )
    }
}
