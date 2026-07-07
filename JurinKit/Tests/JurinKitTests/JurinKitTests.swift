import XCTest
@testable import JurinKit

final class OrderBookTests: XCTestCase {

    func testPriceTimePriorityMatching() {
        let book = OrderBook()
        // 같은 가격에 두 매도 주문 — 먼저 낸 주문이 먼저 체결되어야 한다
        book.submitLimit(agentId: "A", side: .sell, price: 52_300, qty: 100, tick: 1)
        book.submitLimit(agentId: "B", side: .sell, price: 52_300, qty: 100, tick: 2)
        book.submitLimit(agentId: "C", side: .sell, price: 52_350, qty: 100, tick: 3)

        let trades = book.submitLimit(agentId: "X", side: .buy, price: 52_350, qty: 250, tick: 4)

        XCTAssertEqual(trades.count, 3)
        // 낮은 가격부터, 같은 가격은 시간순
        XCTAssertEqual(trades[0].price, 52_300)
        XCTAssertEqual(trades[0].qty, 100)
        XCTAssertEqual(trades[1].price, 52_300)
        XCTAssertEqual(trades[1].qty, 100)
        XCTAssertEqual(trades[2].price, 52_350)
        XCTAssertEqual(trades[2].qty, 50)
        // C의 잔량 50이 남아 있어야 한다
        XCTAssertEqual(book.quotedQty(side: .sell, price: 52_350), 50)
    }

    func testRestingOrderAfterPartialCross() {
        let book = OrderBook()
        book.submitLimit(agentId: "A", side: .sell, price: 52_300, qty: 50, tick: 1)
        // 매수 100 중 50만 체결, 나머지 50은 매수호가로 앉는다
        let trades = book.submitLimit(agentId: "X", side: .buy, price: 52_300, qty: 100, tick: 2)
        XCTAssertEqual(trades.reduce(0) { $0 + $1.qty }, 50)
        XCTAssertEqual(book.bestBid, 52_300)
        XCTAssertEqual(book.quotedQty(side: .buy, price: 52_300), 50)
        XCTAssertNil(book.bestAsk)
    }

    /// 슬리피지 튜토리얼의 정본 케이스 — 부록 A-3 산수 검증.
    func testSlippageTutorialCanonicalCase() {
        let book = OrderBook()
        book.submitLimit(agentId: "S", side: .sell, price: 52_300, qty: 150, tick: 1)
        book.submitLimit(agentId: "S", side: .sell, price: 52_400, qty: 250, tick: 1)
        book.submitLimit(agentId: "S", side: .sell, price: 52_500, qty: 300, tick: 1)
        book.submitLimit(agentId: "S", side: .sell, price: 52_550, qty: 300, tick: 1)

        let displayed = book.bestAsk!
        XCTAssertEqual(displayed, 52_300)

        let (fills, _) = book.executeMarket(agentId: "USER", side: .buy, qty: 1_000, tick: 2)
        let result = FillResult(side: .buy, requestedQty: 1_000, fills: fills, displayedPrice: displayed)

        XCTAssertEqual(result.filledQty, 1_000)
        XCTAssertEqual(result.fills, [
            Fill(price: 52_300, qty: 150),
            Fill(price: 52_400, qty: 250),
            Fill(price: 52_500, qty: 300),
            Fill(price: 52_550, qty: 300)
        ])
        XCTAssertEqual(result.avgFillPrice, 52_460, accuracy: 0.001)
        XCTAssertEqual(result.slippage, 160, accuracy: 0.001)
        XCTAssertEqual(result.slippagePercent, 0.3059, accuracy: 0.001)
    }

    func testPreviewMatchesExecution() {
        let book = OrderBook()
        book.submitLimit(agentId: "S", side: .sell, price: 52_300, qty: 150, tick: 1)
        book.submitLimit(agentId: "S", side: .sell, price: 52_400, qty: 250, tick: 1)

        let preview = book.previewMarket(side: .buy, qty: 300)
        let (fills, _) = book.executeMarket(agentId: "U", side: .buy, qty: 300, tick: 2)
        XCTAssertEqual(preview, fills)
    }

    func testDepthSnapshot() {
        let book = OrderBook()
        book.submitLimit(agentId: "S", side: .sell, price: 52_400, qty: 100, tick: 1)
        book.submitLimit(agentId: "S", side: .sell, price: 52_350, qty: 200, tick: 1)
        book.submitLimit(agentId: "B", side: .buy, price: 52_300, qty: 300, tick: 1)

        let asks = book.depth(side: .sell, levels: 2)
        XCTAssertEqual(asks[0].price, 52_350) // 매도는 싼 것부터
        XCTAssertEqual(asks[0].qty, 200)
        let bids = book.depth(side: .buy, levels: 2)
        XCTAssertEqual(bids[0].price, 52_300)
    }

    func testCancelAllRemovesOnlyThatAgent() {
        let book = OrderBook()
        book.submitLimit(agentId: "MM", side: .buy, price: 52_250, qty: 100, tick: 1)
        book.submitLimit(agentId: "OTHER", side: .buy, price: 52_250, qty: 50, tick: 1)
        book.cancelAll(agentId: "MM")
        XCTAssertEqual(book.quotedQty(side: .buy, price: 52_250), 50)
    }
}

final class EngineTests: XCTestCase {

    func testDeterminismSameSeedSameMarket() {
        let a = MarketEngine(seed: 42)
        let b = MarketEngine(seed: 42)
        a.advance(ticks: 400)
        b.advance(ticks: 400)
        XCTAssertEqual(a.candles, b.candles)
        XCTAssertEqual(a.lastPrice, b.lastPrice)
    }

    func testDifferentSeedsDiverge() {
        let a = MarketEngine(seed: 1)
        let b = MarketEngine(seed: 2)
        a.advance(ticks: 400)
        b.advance(ticks: 400)
        XCTAssertNotEqual(a.candles, b.candles)
    }

    func testCandleAggregation() {
        let engine = MarketEngine(seed: 7)
        engine.advance(ticks: engine.config.ticksPerCandle * 5)
        XCTAssertEqual(engine.candles.count, 5)
        for candle in engine.candles {
            XCTAssertGreaterThanOrEqual(candle.high, candle.low)
            XCTAssertGreaterThanOrEqual(candle.high, max(candle.open, candle.close))
            XCTAssertLessThanOrEqual(candle.low, min(candle.open, candle.close))
        }
    }

    func testMarketStaysAliveOverLongRun() {
        let engine = MarketEngine(seed: 99)
        engine.advance(ticks: 2_000)
        XCTAssertGreaterThan(engine.lastPrice, 0)
        XCTAssertEqual(engine.candles.count, 100)
        // 마켓메이커 덕에 양쪽 호가가 살아 있어야 한다
        XCTAssertNotNil(engine.book.bestBid)
        XCTAssertNotNil(engine.book.bestAsk)
        XCTAssertFalse(engine.tape.isEmpty)
        // 거래가 실제로 일어났어야 한다 (그려진 차트가 아니라는 증거)
        let totalVolume = engine.candles.reduce(0) { $0 + $1.volume }
        XCTAssertGreaterThan(totalVolume, 0)
    }

    func testUserBuyThenSellAccounting() throws {
        let engine = MarketEngine(seed: 5)
        engine.advance(ticks: 50)
        let cashBefore = engine.portfolio.cash

        let buy = try engine.placeMarketOrder(side: .buy, qty: 10)
        let buyFee = engine.config.buyFee(on: buy.notional)
        XCTAssertEqual(buy.filledQty, 10)
        XCTAssertEqual(engine.portfolio.qty, 10)
        XCTAssertEqual(engine.portfolio.cash, cashBefore - buy.notional - buyFee)
        XCTAssertEqual(engine.portfolio.avgCost, buy.avgFillPrice, accuracy: 0.001)

        let sell = try engine.placeMarketOrder(side: .sell, qty: 10)
        let sellFee = engine.config.sellFee(on: sell.notional)
        XCTAssertEqual(sell.filledQty, 10)
        XCTAssertEqual(engine.portfolio.qty, 0)
        XCTAssertEqual(engine.portfolio.cash,
                       cashBefore - buy.notional - buyFee + sell.notional - sellFee)
    }

    func testBuyRejectedWhenCashInsufficient() {
        let engine = MarketEngine(seed: 5, config: EngineConfig(initialCash: 1_000))
        engine.advance(ticks: 10)
        XCTAssertThrowsError(try engine.placeMarketOrder(side: .buy, qty: 100)) { error in
            guard case OrderError.insufficientCash = error else {
                return XCTFail("잔고 부족 오류가 아님: \(error)")
            }
        }
    }

    func testSellRejectedWithoutHoldings() {
        let engine = MarketEngine(seed: 5)
        engine.advance(ticks: 10)
        XCTAssertThrowsError(try engine.placeMarketOrder(side: .sell, qty: 1)) { error in
            guard case OrderError.insufficientHoldings = error else {
                return XCTFail("보유 부족 오류가 아님: \(error)")
            }
        }
    }

    func testUserTradeAppearsInCandleAndTape() throws {
        let engine = MarketEngine(seed: 11)
        engine.advance(ticks: 3)
        let volumeBefore = engine.currentCandle.volume
        _ = try engine.placeMarketOrder(side: .buy, qty: 20)
        XCTAssertGreaterThanOrEqual(engine.currentCandle.volume, volumeBefore + 20)
        XCTAssertEqual(engine.tape.last?.aggressor, .buy)
    }

    func testAdvanceToNextCandleLandsOnBoundary() {
        let engine = MarketEngine(seed: 3)
        engine.advance(ticks: 7)
        engine.advanceToNextCandle()
        XCTAssertEqual(engine.tick % engine.config.ticksPerCandle, 0)
        XCTAssertEqual(engine.candles.count, 1)
    }

    func testMovingAverage() {
        var candles: [Candle] = []
        for (i, close) in [100, 200, 300, 400].enumerated() {
            var candle = Candle(open: close, index: i)
            candle.apply(Trade(price: close, qty: 1, tick: i, aggressor: .buy))
            candles.append(candle)
        }
        let ma2 = candles.movingAverage(period: 2)
        XCTAssertNil(ma2[0])
        XCTAssertEqual(ma2[1], 150)
        XCTAssertEqual(ma2[2], 250)
        XCTAssertEqual(ma2[3], 350)
    }
}
