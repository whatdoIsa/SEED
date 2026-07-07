import XCTest
@testable import JurinKit

final class QuantTests: XCTestCase {

    private func candle(open: Int, close: Int, index: Int) -> Candle {
        var candle = Candle(open: open, index: index)
        candle.apply(Trade(price: close, qty: 1, tick: index, aggressor: .buy))
        return candle
    }

    func testRSIBounds() {
        // 연속 상승 → RSI 100, 연속 하락 → RSI 0
        var rising: [Candle] = []
        var falling: [Candle] = []
        for i in 0..<16 {
            rising.append(candle(open: 100 + i * 2, close: 102 + i * 2, index: i))
            falling.append(candle(open: 200 - i * 2, close: 198 - i * 2, index: i))
        }
        XCTAssertEqual(rising.rsi(period: 14), 100)
        XCTAssertEqual(falling.rsi(period: 14) ?? -1, 0, accuracy: 0.001)
        XCTAssertNil(rising.prefix(5).map { $0 }.rsi(period: 14), "데이터 부족이면 nil")
    }

    func testGoldenCrossDetection() {
        // 하락하다 반등해 단기선이 장기선을 뚫는 손수 시계열
        var candles: [Candle] = []
        let closes = [110, 108, 106, 104, 102, 100, 98, 101, 106, 112]
        for (i, close) in closes.enumerated() {
            candles.append(candle(open: close, close: close, index: i))
        }
        var crossedAt: Int?
        for end in 5...closes.count {
            let window = Array(candles.prefix(end))
            if QuantCondition.goldenCross(short: 2, long: 4).isMet(candles: window) {
                crossedAt = end
                break
            }
        }
        XCTAssertNotNil(crossedAt, "반등 구간에서 골든크로스가 감지되어야 한다")
    }

    func testRSIReversalStrategyOnCrash() {
        // 급락장에서 과매도 매수 → 회복에서 과매수/청산
        let strategy = QuantStrategy(
            name: "RSI 역추세",
            entry: .rsiBelow(threshold: 30, period: 6),
            exit: .rsiAbove(threshold: 60, period: 6)
        )
        let run = BotComparison.run(strategy: strategy, scenario: .panicCrash())

        XCTAssertGreaterThanOrEqual(run.tradeCount, 1, "급락에서 과매도 진입이 발생해야 한다")
        XCTAssertEqual(run.equityCurve.count, run.candles.count)
        let firstBuy = run.actions.first { $0.side == .buy }
        XCTAssertNotNil(firstBuy)
    }

    func testBreakoutStrategyOnRally() {
        let strategy = QuantStrategy(
            name: "돌파 추세",
            entry: .breakoutHigh(lookback: 5),
            exit: .breakdownLow(lookback: 3)
        )
        let run = BotComparison.run(strategy: strategy, scenario: .chaseRally())
        XCTAssertGreaterThanOrEqual(run.tradeCount, 2, "급등 돌파 진입과 회귀 청산이 있어야 한다")
    }

    func testQuantRunDeterminism() {
        let strategy = QuantStrategy(
            name: "이평 교차",
            entry: .goldenCross(short: 3, long: 8),
            exit: .deadCross(short: 3, long: 8)
        )
        let a = BotComparison.run(strategy: strategy, scenario: .chaseRally())
        let b = BotComparison.run(strategy: strategy, scenario: .chaseRally())
        XCTAssertEqual(a.finalEquity, b.finalEquity)
        XCTAssertEqual(a.actions.map(\.candleIndex), b.actions.map(\.candleIndex))
    }

    func testTurtleStillWorksAfterHarnessRefactor() {
        let run = BotComparison.runTurtle(scenario: .chaseRally())
        XCTAssertGreaterThanOrEqual(run.tradeCount, 2)
        XCTAssertEqual(run.botName, "터틀 봇")
    }
}
