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
            if let decision = strategy.onCandleClose(candles: candles, avgCost: 100) {
                actions.append(decision.action)
                XCTAssertFalse(decision.reason.isEmpty, "모든 매매엔 이유가 붙는다")
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

    func testBotActionsCarryReasons() {
        for run in [BotComparison.runTurtle(scenario: .chaseRally()),
                    BotComparison.runValue(scenario: .panicCrash())] {
            for action in run.actions {
                XCTAssertFalse(action.reason.isEmpty,
                               "\(run.botName)의 매매 일지엔 이유가 있어야 한다")
            }
        }
    }

    func testValueAndTrendDifferOnSameScenario() {
        // 두 철학은 같은 시나리오에서 다르게 움직여야 의미가 있다
        let turtle = BotComparison.runTurtle(scenario: .chaseRally())
        let value = BotComparison.runValue(scenario: .chaseRally())
        XCTAssertNotEqual(turtle.actions.map(\.candleIndex),
                          value.actions.map(\.candleIndex),
                          "추세추종과 가치투자는 진입 시점이 달라야 한다")
    }

    // MARK: 거장 봇 3인 (오닐·코스톨라니·템플턴)

    func testKostolanyBuysOnceAndSleeps() {
        let run = BotComparison.runKostolany(scenario: .chaseRally())
        let buys = run.actions.filter { $0.side == .buy }
        let sells = run.actions.filter { $0.side == .sell }
        XCTAssertEqual(buys.count, 1, "코스톨라니는 딱 한 번 산다")
        XCTAssertTrue(sells.isEmpty, "그리고 끝까지 잔다")
        XCTAssertLessThanOrEqual(buys[0].candleIndex, 3, "초반에 산다")
    }

    func testONeilStopLossRespected() throws {
        // 데드캣: 반등 돌파에 속아 타더라도 -8%에서 반드시 잘린다
        let run = BotComparison.runONeil(scenario: .deadCatBounce())
        for (index, action) in run.actions.enumerated() where action.side == .sell {
            // 직전 매수가 대비 -8%보다 깊게 물린 채 판 적이 없어야 한다 (슬리피지 여유 1.5%)
            let lastBuy = run.actions[..<index].last { $0.side == .buy }
            if let buy = lastBuy {
                let lossPct = (buy.price - action.price) / buy.price * 100
                XCTAssertLessThan(lossPct, 8 + 1.5,
                                  "오닐 봇의 손실은 -8% 부근에서 잘려야 한다: \(lossPct)%")
            }
        }
    }

    func testTempletonBuysPanicSellsCalm() throws {
        let run = BotComparison.runTempleton(scenario: .panicCrash())
        let firstBuy = try XCTUnwrap(run.actions.first { $0.side == .buy },
                                     "급락(비관)에서 템플턴은 반드시 산다")
        XCTAssertTrue(firstBuy.reason.contains("비관"),
                      "매매 일지에 역발상 이유가 실린다")
        // 꾸준한 상승만 있는 장에선 살 기회가 없어야 정체성이 산다 — 급등 초반 확인
        let chase = BotComparison.runTempleton(scenario: .chaseRally())
        let earlyBuys = chase.actions.filter { $0.side == .buy && $0.candleIndex < 12 }
        XCTAssertTrue(earlyBuys.isEmpty, "상승 구간에서 템플턴은 사지 않는다")
    }

    func testAllMastersAreDeterministic() {
        let runs1 = [BotComparison.runONeil(scenario: .deadCatBounce()),
                     BotComparison.runKostolany(scenario: .deadCatBounce()),
                     BotComparison.runTempleton(scenario: .deadCatBounce())]
        let runs2 = [BotComparison.runONeil(scenario: .deadCatBounce()),
                     BotComparison.runKostolany(scenario: .deadCatBounce()),
                     BotComparison.runTempleton(scenario: .deadCatBounce())]
        for (a, b) in zip(runs1, runs2) {
            XCTAssertEqual(a.finalEquity, b.finalEquity, "\(a.botName) 결정론")
        }
    }

    func testBotsSizeByPriceOnExpensiveMarkets() throws {
        // 9만원대 시장: 고정 수량이면 매수가 조용히 실패하던 버그의 회귀 가드
        let expensive = ScenarioPreset(
            id: "test.expensive", seed: 11, initialPrice: 92_000,
            durationTicks: 600, anchorPull: 0.12,
            keyframes: [
                .init(tick: 0, value: 92_000),
                .init(tick: 150, value: 93_000),
                .init(tick: 300, value: 80_000),   // 급락 (템플턴·가치 진입 유도)
                .init(tick: 450, value: 91_000),   // 회복
                .init(tick: 600, value: 92_500)
            ]
        )
        let kostolany = BotComparison.runKostolany(scenario: expensive)
        XCTAssertFalse(kostolany.actions.filter { $0.side == .buy }.isEmpty,
                       "코스톨라니는 비싼 장에서도 산다")
        let templeton = BotComparison.runTempleton(scenario: expensive)
        XCTAssertFalse(templeton.actions.filter { $0.side == .buy }.isEmpty,
                       "템플턴은 비싼 장의 급락에서도 산다")
    }
}
