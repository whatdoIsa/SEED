import XCTest
@testable import JurinKit

final class TurtleTests: XCTestCase {

    func testRollingIndicators() {
        var candles: [Candle] = []
        for (i, values) in [(100, 110, 95, 105), (105, 120, 100, 115), (115, 125, 110, 112)].enumerated() {
            var candle = Candle(open: values.0, index: i)
            candle.apply(Trade(price: values.2, qty: 1, tick: i, aggressor: .sell)) // low
            candle.apply(Trade(price: values.1, qty: 1, tick: i, aggressor: .buy))  // high
            candle.apply(Trade(price: values.3, qty: 1, tick: i, aggressor: .buy))  // close
            candles.append(candle)
        }
        XCTAssertEqual(candles.highestHigh(period: 2), 125)
        XCTAssertEqual(candles.lowestLow(period: 2), 100)
        XCTAssertNotNil(candles.atr(period: 2))
        XCTAssertNil(candles.atr(period: 5), "데이터 부족이면 nil")
    }

    func testTurtleEntersOnBreakoutAndExits() throws {
        let run = BotComparison.runTurtle(scenario: .chaseRally())

        XCTAssertGreaterThanOrEqual(run.tradeCount, 2, "급등 돌파에 진입하고, 회귀에서 청산해야 한다")
        XCTAssertEqual(run.equityCurve.count, run.candles.count)
        XCTAssertTrue((0...100).contains(run.maxDrawdownPct))

        let firstBuy = try XCTUnwrap(run.actions.first { $0.side == .buy },
                                     "돌파 진입이 있어야 한다")
        let firstSell = try XCTUnwrap(run.actions.first { $0.side == .sell },
                                      "채널 하단 이탈 또는 손절 청산이 있어야 한다")
        XCTAssertLessThan(firstBuy.candleIndex, firstSell.candleIndex,
                          "진입이 청산보다 앞선다")
    }

    func testTurtleRunIsDeterministic() {
        let a = BotComparison.runTurtle(scenario: .chaseRally())
        let b = BotComparison.runTurtle(scenario: .chaseRally())
        XCTAssertEqual(a.finalEquity, b.finalEquity)
        XCTAssertEqual(a.equityCurve, b.equityCurve)
        XCTAssertEqual(a.actions.map(\.candleIndex), b.actions.map(\.candleIndex))
    }

    func testMaxDrawdown() {
        XCTAssertEqual(BotComparison.maxDrawdown(of: [100, 120, 90, 110]), 25, accuracy: 0.001)
        XCTAssertEqual(BotComparison.maxDrawdown(of: [100, 110, 120]), 0, accuracy: 0.001)
    }

    func testStrategyPyramidsUpToMaxUnits() {
        var strategy = TurtleStrategy(entryLookback: 3, exitLookback: 3, atrPeriod: 2,
                                      maxUnits: 2, unitQty: 10)
        // 꾸준히 오르는 손수 캔들: 돌파 → 추가 → 상한 도달
        var candles: [Candle] = []
        var actions: [TurtleStrategy.Action] = []
        for i in 0..<12 {
            let base = 100 + i * 8
            var candle = Candle(open: base, index: i)
            candle.apply(Trade(price: base - 2, qty: 1, tick: i, aggressor: .sell))
            candle.apply(Trade(price: base + 6, qty: 1, tick: i, aggressor: .buy))
            candles.append(candle)
            if let action = strategy.onCandleClose(candles: candles, avgCost: 100) {
                actions.append(action)
            }
        }
        let buyCount = actions.filter { if case .buyUnit = $0 { return true }; return false }.count
        XCTAssertEqual(buyCount, 2, "maxUnits를 넘겨 피라미딩하지 않는다")
    }

    // MARK: 가치투자 봇

    func testValueBotBuysTheDip() {
        // 급락 시나리오: 공포에 가격이 내재가치 밑으로 빠질 때 가치봇이 줍는다
        let run = BotComparison.runValue(scenario: .panicCrash())
        XCTAssertEqual(run.equityCurve.count, run.candles.count)
        XCTAssertTrue((0...100).contains(run.maxDrawdownPct))
        XCTAssertEqual(run.botName, "가치투자 봇")
        XCTAssertFalse(run.actions.filter { $0.side == .buy }.isEmpty,
                       "저평가되면 가치봇이 진입해야 한다")
    }

    func testValueBotIsDeterministic() {
        let a = BotComparison.runValue(scenario: .chaseRally())
        let b = BotComparison.runValue(scenario: .chaseRally())
        XCTAssertEqual(a.finalEquity, b.finalEquity)
        XCTAssertEqual(a.actions.map(\.candleIndex), b.actions.map(\.candleIndex))
    }

    func testValueAndTrendDifferOnSameScenario() {
        // 두 철학은 같은 시나리오에서 다르게 움직여야 의미가 있다
        let turtle = BotComparison.runTurtle(scenario: .chaseRally())
        let value = BotComparison.runValue(scenario: .chaseRally())
        XCTAssertNotEqual(turtle.actions.map(\.candleIndex),
                          value.actions.map(\.candleIndex),
                          "추세추종과 가치투자는 진입 시점이 달라야 한다")
    }
}
