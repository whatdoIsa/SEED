import XCTest
@testable import JurinKit

final class MultiSymbolTests: XCTestCase {

    func testSharedLedgerAcrossEngines() throws {
        let ledger = AccountLedger(cash: 10_000_000)
        let engineA = MarketEngine(seed: 1, initialPrice: 50_000, symbol: "A", ledger: ledger)
        let engineB = MarketEngine(seed: 2, initialPrice: 8_000, symbol: "B", ledger: ledger)
        engineA.advance(ticks: 20)
        engineB.advance(ticks: 20)

        _ = try engineA.placeMarketOrder(side: .buy, qty: 100)
        _ = try engineB.placeMarketOrder(side: .buy, qty: 200)

        // 하나의 현금에서 둘 다 나갔다
        XCTAssertLessThan(ledger.cash, 10_000_000)
        XCTAssertEqual(ledger.qty(of: "A"), 100)
        XCTAssertEqual(ledger.qty(of: "B"), 200)
        // 서로의 보유는 섞이지 않는다
        XCTAssertEqual(engineA.portfolio.qty, 100)
        XCTAssertEqual(engineB.portfolio.qty, 200)

        // A를 팔면 그 돈으로 B를 더 살 수 있다 — 공유 현금의 증명
        _ = try engineA.placeMarketOrder(side: .sell, qty: 100)
        XCTAssertEqual(ledger.qty(of: "A"), 0)
        XCTAssertGreaterThan(ledger.availableCash, 0)
    }

    func testCashExhaustionOnOneSymbolBlocksOther() throws {
        let ledger = AccountLedger(cash: 6_000_000)
        let engineA = MarketEngine(seed: 1, initialPrice: 50_000, symbol: "A", ledger: ledger)
        let engineB = MarketEngine(seed: 2, initialPrice: 50_000, symbol: "B", ledger: ledger)
        engineA.advance(ticks: 20)
        engineB.advance(ticks: 20)

        _ = try engineA.placeMarketOrder(side: .buy, qty: 100) // ~500만 소진

        XCTAssertThrowsError(try engineB.placeMarketOrder(side: .buy, qty: 100)) { error in
            guard case OrderError.insufficientCash = error else {
                return XCTFail("한 종목이 쓴 현금은 다른 종목에서도 없어야 한다: \(error)")
            }
        }
    }

    func testSellRestrictedToOwnSymbolHolding() throws {
        let ledger = AccountLedger(cash: 10_000_000)
        let engineA = MarketEngine(seed: 1, symbol: "A", ledger: ledger)
        let engineB = MarketEngine(seed: 2, symbol: "B", ledger: ledger)
        engineA.advance(ticks: 20)
        engineB.advance(ticks: 20)

        _ = try engineA.placeMarketOrder(side: .buy, qty: 50)

        // A를 들고 있어도 B 시장에서는 팔 수 없다
        XCTAssertThrowsError(try engineB.placeMarketOrder(side: .sell, qty: 50)) { error in
            guard case OrderError.insufficientHoldings = error else {
                return XCTFail("보유는 종목별로 분리되어야 한다: \(error)")
            }
        }
    }

    func testTotalEquityAcrossSymbols() throws {
        let ledger = AccountLedger(cash: 10_000_000)
        let engineA = MarketEngine(seed: 1, initialPrice: 50_000, symbol: "A", ledger: ledger)
        engineA.advance(ticks: 20)
        _ = try engineA.placeMarketOrder(side: .buy, qty: 10)

        let equity = ledger.totalEquity(prices: ["A": engineA.lastPrice])
        let expected = ledger.cash + 10 * engineA.lastPrice
        XCTAssertEqual(equity, expected)
    }
}
