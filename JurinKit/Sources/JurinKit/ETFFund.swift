import Foundation

/// 합성 ETF — 기존 종목들의 고정 좌수 바스켓 + 운용보수 엔진.
///
/// 설계 원칙:
/// - **고정 좌수**: 상장 시점(스펙 초기가) 기준으로 1좌당 구성 좌수를 확정한다.
///   좌수가 상수이므로 세션 복원·리플레이에서 결정론이 그대로 유지된다.
/// - **NAV = 보수차감계수 × Σ(구성 좌수 × 현재가)**: 가격은 구성 종목 시장이 만들고,
///   운용보수는 매 거래일 연보수/252 만큼 계수를 갉아먹는다 — "보이지 않는 월세".
/// - **호가창 없음**: 학습 단순화를 위해 NAV에 즉시 체결한다 (LP가 괴리를 좁혀주는
///   실제 ETF의 이상적 근사). 수수료는 위탁 수수료만 — 국내 주식형 ETF처럼
///   매도 거래세가 없다는 것 자체가 트랙 2의 교육 포인트다.
public final class ETFFund {

    /// 1좌를 구성하는 종목별 좌수 (상장 시 고정).
    public struct Component: Equatable {
        public let symbol: String
        public let unitsPerShare: Double
        public init(symbol: String, unitsPerShare: Double) {
            self.symbol = symbol
            self.unitsPerShare = unitsPerShare
        }
    }

    public let symbol: String
    public let name: String
    /// 연 운용보수 (TER) — 예: 0.0015 = 0.15%
    public let expenseRatioAnnual: Double
    public let commissionRate: Double
    public let components: [Component]
    public let tradingDaysPerYear: Int
    public let ledger: AccountLedger

    /// 상장 기준가 (설계 목표 NAV — 구성 좌수 산출의 기준)
    public let inceptionNAV: Int

    public init(symbol: String,
                name: String,
                inceptionNAV: Int,
                weights: [(symbol: String, weight: Double)],
                inceptionPrices: [String: Int],
                expenseRatioAnnual: Double,
                commissionRate: Double = 0.00015,
                tradingDaysPerYear: Int = 252,
                ledger: AccountLedger) {
        self.symbol = symbol
        self.name = name
        self.inceptionNAV = inceptionNAV
        self.expenseRatioAnnual = expenseRatioAnnual
        self.commissionRate = commissionRate
        self.tradingDaysPerYear = tradingDaysPerYear
        self.ledger = ledger
        self.components = weights.compactMap { entry in
            guard let price = inceptionPrices[entry.symbol], price > 0 else { return nil }
            return Component(symbol: entry.symbol,
                             unitsPerShare: Double(inceptionNAV) * entry.weight / Double(price))
        }
    }

    // MARK: NAV

    /// 보수 차감 계수 — 경과 거래일만큼 매일 연보수/거래일수 비율로 감소한다.
    public func feeFactor(daysElapsed: Int) -> Double {
        guard daysElapsed > 0 else { return 1 }
        return pow(1 - expenseRatioAnnual / Double(tradingDaysPerYear), Double(daysElapsed))
    }

    /// 보수 차감 전 순수 바스켓 가치.
    public func basketValue(prices: [String: Int]) -> Double {
        components.reduce(0) { sum, component in
            sum + component.unitsPerShare * Double(prices[component.symbol] ?? 0)
        }
    }

    public func navExact(prices: [String: Int], daysElapsed: Int) -> Double {
        basketValue(prices: prices) * feeFactor(daysElapsed: daysElapsed)
    }

    /// 표시·체결용 NAV (원 단위 반올림, 최소 1원).
    public func nav(prices: [String: Int], daysElapsed: Int) -> Int {
        max(Int(navExact(prices: prices, daysElapsed: daysElapsed).rounded()), 1)
    }

    /// 지금까지 보수로 차감된 누적 금액 (1좌 기준, 원) — "월세 고지서".
    public func accruedFeePerShare(prices: [String: Int], daysElapsed: Int) -> Double {
        basketValue(prices: prices) * (1 - feeFactor(daysElapsed: daysElapsed))
    }

    // MARK: 매매 (NAV 즉시 체결)

    public func fee(on notional: Int) -> Int {
        Int((Double(notional) * commissionRate).rounded())
    }

    @discardableResult
    public func buy(qty: Int, prices: [String: Int], daysElapsed: Int) throws -> FillResult {
        guard qty > 0 else { throw OrderError.invalidQuantity }
        let price = nav(prices: prices, daysElapsed: daysElapsed)
        let cost = price * qty
        let needed = cost + fee(on: cost)
        guard needed <= ledger.availableCash else {
            throw OrderError.insufficientCash(needed: needed, available: ledger.availableCash)
        }
        let result = FillResult(side: .buy, requestedQty: qty,
                                fills: [Fill(price: price, qty: qty)], displayedPrice: price)
        ledger.applyBuy(symbol: symbol, result, fee: fee(on: cost))
        return result
    }

    @discardableResult
    public func sell(qty: Int, prices: [String: Int], daysElapsed: Int) throws -> FillResult {
        guard qty > 0 else { throw OrderError.invalidQuantity }
        guard qty <= ledger.availableShares(of: symbol) else {
            throw OrderError.insufficientHoldings(requested: qty,
                                                  held: ledger.availableShares(of: symbol))
        }
        let price = nav(prices: prices, daysElapsed: daysElapsed)
        let result = FillResult(side: .sell, requestedQty: qty,
                                fills: [Fill(price: price, qty: qty)], displayedPrice: price)
        ledger.applySell(symbol: symbol, result, fee: fee(on: price * qty))
        return result
    }

    /// 세션 복원 리플레이: 과거 체결을 기록된 가격 그대로 원장에만 반영한다.
    public func restoreFill(side: Side, price: Int, qty: Int) {
        let result = FillResult(side: side, requestedQty: qty,
                                fills: [Fill(price: price, qty: qty)], displayedPrice: price)
        switch side {
        case .buy: ledger.applyBuy(symbol: symbol, result, fee: fee(on: price * qty))
        case .sell: ledger.applySell(symbol: symbol, result, fee: fee(on: price * qty))
        }
    }
}
