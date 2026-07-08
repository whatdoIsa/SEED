import XCTest
@testable import JurinKit

final class MarketRulesTests: XCTestCase {

    func testKRXTickSizeBrackets() {
        XCTAssertEqual(EngineConfig.krxTickSize(for: 1_500), 1)
        XCTAssertEqual(EngineConfig.krxTickSize(for: 3_000), 5)
        XCTAssertEqual(EngineConfig.krxTickSize(for: 15_000), 10)
        XCTAssertEqual(EngineConfig.krxTickSize(for: 45_000), 50)
        XCTAssertEqual(EngineConfig.krxTickSize(for: 120_000), 100)
        XCTAssertEqual(EngineConfig.krxTickSize(for: 350_000), 250)
        XCTAssertEqual(EngineConfig.krxTickSize(for: 700_000), 1_000)
    }

    func testFeesChargedOnMarketOrders() throws {
        let engine = MarketEngine(seed: 5)
        engine.advance(ticks: 20)
        let cashBefore = engine.portfolio.cash

        let buy = try engine.placeMarketOrder(side: .buy, qty: 10)
        let buyFee = engine.config.buyFee(on: buy.notional)
        XCTAssertGreaterThan(buyFee, 0)
        XCTAssertEqual(engine.portfolio.cash, cashBefore - buy.notional - buyFee)
        XCTAssertEqual(engine.portfolio.feesPaid, buyFee)

        let sell = try engine.placeMarketOrder(side: .sell, qty: 10)
        let sellFee = engine.config.sellFee(on: sell.notional)
        XCTAssertGreaterThan(sellFee, buyFee, "매도는 거래세가 붙어 수수료가 더 크다")
        XCTAssertEqual(engine.portfolio.cash,
                       cashBefore - buy.notional - buyFee + sell.notional - sellFee)
        XCTAssertEqual(engine.portfolio.feesPaid, buyFee + sellFee)
    }

    func testPriceBandCapsRally() {
        // 앵커를 밴드 밖으로 밀어도 가격은 상한가에 갇힌다 (상한가 잔량이 쌓인다)
        let engine = MarketEngine(seed: 9, config: EngineConfig(newsTickProbability: 0))
        engine.advance(ticks: 20)
        let upper = engine.upperLimitPrice
        engine.fairAnchor *= 1.6

        // 기준가가 갱신되기 전(같은 거래일 안)까지만 관찰
        let ticksLeftInDay = engine.config.ticksPerCandle * engine.config.candlesPerDay - engine.tick
        engine.advance(ticks: max(ticksLeftInDay - 1, 1))

        XCTAssertLessThanOrEqual(engine.lastPrice, upper, "상한가를 뚫을 수 없다")
        if let bestAsk = engine.book.bestAsk {
            XCTAssertLessThanOrEqual(bestAsk, upper)
        }
    }

    func testTradingDayRollover() {
        let engine = MarketEngine(seed: 3, config: EngineConfig(newsTickProbability: 0))
        XCTAssertEqual(engine.tradingDay, 1)
        let ticksPerDay = engine.config.ticksPerCandle * engine.config.candlesPerDay

        engine.advance(ticks: ticksPerDay)
        XCTAssertEqual(engine.tradingDay, 2, "거래일이 넘어가야 한다")
        XCTAssertEqual(engine.referencePrice, engine.candles.last!.close,
                       "기준가는 전일 종가")
        XCTAssertTrue(engine.isInAuction, "장 개시 직후엔 동시호가가 돈다")
        engine.advance(ticks: engine.auctionTicksRemaining)
        XCTAssertNotNil(engine.book.bestBid, "동시호가 청산 후 호가가 살아난다")
    }

    func testUserLimitOutsideBandRejected() {
        let engine = MarketEngine(seed: 5)
        engine.advance(ticks: 20)
        let upper = engine.upperLimitPrice
        XCTAssertThrowsError(try engine.placeLimitOrder(side: .buy, price: upper + 10_000, qty: 1)) { error in
            guard case OrderError.priceOutOfBand = error else {
                return XCTFail("상한가 밖 지정가는 거부되어야 한다: \(error)")
            }
        }
    }

    func testUserRestingOrderSurvivesDayRollover() throws {
        let engine = MarketEngine(seed: 7, config: EngineConfig(newsTickProbability: 0))
        engine.advance(ticks: 20)
        // 체결되지 않게 하한가 바로 위에 깔아둔다
        let price = engine.lowerLimitPrice
        let result = try engine.placeLimitOrder(side: .buy, price: price, qty: 10)
        let orderId = try XCTUnwrap(result.restingOrder?.id)

        let ticksPerDay = engine.config.ticksPerCandle * engine.config.candlesPerDay
        engine.advance(ticks: ticksPerDay)

        XCTAssertTrue(engine.openOrders.contains { $0.id == orderId },
                      "사용자 대기 주문은 거래일이 바뀌어도 살아남는다 (GTC)")
        XCTAssertGreaterThan(engine.book.remainingQty(orderId: orderId, side: .buy, price: price), 0)
    }

    func testFeeIncludedInLimitReserve() throws {
        let engine = MarketEngine(seed: 42)
        engine.advance(ticks: 20)
        let price = engine.book.bestBid!
        _ = try engine.placeLimitOrder(side: .buy, price: price, qty: 100)

        let expectedReserve = price * 100 + engine.config.buyFee(on: price * 100)
        XCTAssertEqual(engine.portfolio.reservedCash, expectedReserve,
                       "예약금에는 수수료도 포함된다")
    }
}
