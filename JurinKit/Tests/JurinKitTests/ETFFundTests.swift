import XCTest
@testable import JurinKit

final class ETFFundTests: XCTestCase {

    private func makeFund(ledger: AccountLedger = AccountLedger(cash: 10_000_000),
                          ter: Double = 0.0015) -> ETFFund {
        ETFFund(symbol: "TEST",
                name: "테스트 ETF",
                inceptionNAV: 10_000,
                weights: [("A", 0.6), ("B", 0.4)],
                inceptionPrices: ["A": 50_000, "B": 20_000],
                expenseRatioAnnual: ter,
                ledger: ledger)
    }

    // MARK: NAV 산술

    func testInceptionNAVMatchesWeights() {
        let fund = makeFund()
        // 상장 시점 가격 그대로면 NAV = 상장 기준가
        let nav = fund.nav(prices: ["A": 50_000, "B": 20_000], daysElapsed: 0)
        XCTAssertEqual(nav, 10_000)
        // 좌수 검증: A = 10000*0.6/50000 = 0.12좌, B = 10000*0.4/20000 = 0.2좌
        XCTAssertEqual(fund.components[0].unitsPerShare, 0.12, accuracy: 1e-12)
        XCTAssertEqual(fund.components[1].unitsPerShare, 0.2, accuracy: 1e-12)
    }

    func testNAVTracksBasket() {
        let fund = makeFund()
        // A +10%, B 불변 → NAV는 가중치 60%의 10% = +6%
        let nav = fund.navExact(prices: ["A": 55_000, "B": 20_000], daysElapsed: 0)
        XCTAssertEqual(nav, 10_600, accuracy: 0.001)
    }

    func testMissingMemberPriceCountsAsZero() {
        let fund = makeFund()
        let nav = fund.navExact(prices: ["A": 50_000], daysElapsed: 0)
        XCTAssertEqual(nav, 6_000, accuracy: 0.001)
    }

    // MARK: 운용보수

    func testFeeFactorDecaysDaily() {
        let fund = makeFund(ter: 0.0015)
        XCTAssertEqual(fund.feeFactor(daysElapsed: 0), 1)
        // 1년(252거래일) 뒤 누적 차감 ≈ TER (복리라 아주 약간 작다)
        let yearFactor = fund.feeFactor(daysElapsed: 252)
        XCTAssertEqual(yearFactor, 1 - 0.0015, accuracy: 0.00001)
        // 단조 감소
        XCTAssertLessThan(fund.feeFactor(daysElapsed: 10), fund.feeFactor(daysElapsed: 5))
    }

    func testHigherTERDragsNAVMore() {
        let cheap = makeFund(ter: 0.0015)
        let pricey = makeFund(ter: 0.0099)
        let prices = ["A": 50_000, "B": 20_000]
        // 같은 바스켓, 같은 시장 — 보수만 다르면 1년 뒤 NAV가 갈린다
        let navCheap = cheap.navExact(prices: prices, daysElapsed: 252)
        let navPricey = pricey.navExact(prices: prices, daysElapsed: 252)
        XCTAssertGreaterThan(navCheap, navPricey)
        XCTAssertEqual(navCheap - navPricey, 10_000 * (0.0099 - 0.0015), accuracy: 1.0)
    }

    func testAccruedFeePerShare() {
        let fund = makeFund(ter: 0.0015)
        let prices = ["A": 50_000, "B": 20_000]
        let accrued = fund.accruedFeePerShare(prices: prices, daysElapsed: 252)
        XCTAssertEqual(accrued, 15.0, accuracy: 0.05) // 1좌 10,000원의 0.15%
    }

    // MARK: 매매 — 원장 반영

    func testBuyDebitsLedgerAndHolds() throws {
        let ledger = AccountLedger(cash: 10_000_000)
        let fund = makeFund(ledger: ledger)
        let prices = ["A": 50_000, "B": 20_000]

        let result = try fund.buy(qty: 10, prices: prices, daysElapsed: 0)
        XCTAssertEqual(result.avgFillPrice, 10_000, accuracy: 0.001)
        XCTAssertEqual(ledger.qty(of: "TEST"), 10)
        let cost = 100_000
        let fee = fund.fee(on: cost)
        XCTAssertEqual(ledger.cash, 10_000_000 - cost - fee)
        XCTAssertEqual(ledger.feesPaid, fee)
    }

    func testSellCreditsLedgerWithoutSellTax() throws {
        let ledger = AccountLedger(cash: 10_000_000)
        let fund = makeFund(ledger: ledger)
        let prices = ["A": 50_000, "B": 20_000]
        try fund.buy(qty: 10, prices: prices, daysElapsed: 0)

        let cashBefore = ledger.cash
        try fund.sell(qty: 10, prices: prices, daysElapsed: 0)
        XCTAssertEqual(ledger.qty(of: "TEST"), 0)
        // 매도 비용 = 수수료만 (거래세 없음) — 같은 요율로 대칭
        let proceeds = 100_000
        XCTAssertEqual(ledger.cash, cashBefore + proceeds - fund.fee(on: proceeds))
    }

    func testBuyRejectsInsufficientCash() {
        let ledger = AccountLedger(cash: 5_000)
        let fund = makeFund(ledger: ledger)
        XCTAssertThrowsError(try fund.buy(qty: 1,
                                          prices: ["A": 50_000, "B": 20_000],
                                          daysElapsed: 0)) { error in
            guard case OrderError.insufficientCash = error else {
                return XCTFail("잘못된 오류: \(error)")
            }
        }
    }

    func testSellRejectsInsufficientHoldings() {
        let fund = makeFund()
        XCTAssertThrowsError(try fund.sell(qty: 1,
                                           prices: ["A": 50_000, "B": 20_000],
                                           daysElapsed: 0)) { error in
            guard case OrderError.insufficientHoldings = error else {
                return XCTFail("잘못된 오류: \(error)")
            }
        }
    }

    func testInvalidQuantityRejected() {
        let fund = makeFund()
        XCTAssertThrowsError(try fund.buy(qty: 0, prices: [:], daysElapsed: 0))
        XCTAssertThrowsError(try fund.sell(qty: -1, prices: [:], daysElapsed: 0))
    }

    // MARK: 복원

    func testRestoreFillReproducesLedgerState() throws {
        // 라이브 매매와 restoreFill이 같은 원장 상태를 만든다 — 리플레이 정합성
        let liveLedger = AccountLedger(cash: 10_000_000)
        let liveFund = makeFund(ledger: liveLedger)
        let prices = ["A": 52_000, "B": 21_000]
        let fill = try liveFund.buy(qty: 7, prices: prices, daysElapsed: 3)
        try liveFund.sell(qty: 3, prices: prices, daysElapsed: 3)

        let replayLedger = AccountLedger(cash: 10_000_000)
        let replayFund = makeFund(ledger: replayLedger)
        let navAtTrade = Int(fill.avgFillPrice.rounded())
        replayFund.restoreFill(side: .buy, price: navAtTrade, qty: 7)
        replayFund.restoreFill(side: .sell, price: navAtTrade, qty: 3)

        XCTAssertEqual(replayLedger.cash, liveLedger.cash)
        XCTAssertEqual(replayLedger.qty(of: "TEST"), liveLedger.qty(of: "TEST"))
        XCTAssertEqual(replayLedger.avgCost(of: "TEST"), liveLedger.avgCost(of: "TEST"),
                       accuracy: 0.001)
        XCTAssertEqual(replayLedger.realizedPnL, liveLedger.realizedPnL, accuracy: 0.001)
    }

    // MARK: 통합 — 살아있는 시장 위의 ETF

    func testNAVMovesWithLiveEngines() throws {
        let ledger = AccountLedger(cash: 10_000_000)
        let climate = MarketClimate(seed: 42)
        let engineA = MarketEngine(seed: 1, initialPrice: 50_000, symbol: "A",
                                   ledger: ledger, climate: climate)
        let engineB = MarketEngine(seed: 2, initialPrice: 20_000, symbol: "B",
                                   ledger: ledger, climate: climate)
        let fund = makeFund(ledger: ledger)

        // 410틱 = 1거래일(400틱) + 동시호가(6틱) 이후 — 연속 매매 구간
        engineA.advance(ticks: 410)
        engineB.advance(ticks: 410)
        let prices = ["A": engineA.lastPrice, "B": engineB.lastPrice]
        let nav = fund.nav(prices: prices, daysElapsed: engineA.tradingDay - 1)
        XCTAssertGreaterThan(nav, 0)

        // ETF 매수가 주식 매수와 같은 현금 풀에서 나간다
        try fund.buy(qty: 5, prices: prices, daysElapsed: 0)
        _ = try engineA.placeMarketOrder(side: .buy, qty: 10)
        let equity = ledger.totalEquity(prices: prices.merging(["TEST": nav]) { a, _ in a })
        XCTAssertGreaterThan(equity, 9_000_000) // 수수료 말곤 자산이 보존된다
    }
}
