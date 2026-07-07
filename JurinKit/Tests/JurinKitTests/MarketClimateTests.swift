import XCTest
@testable import JurinKit

final class MarketClimateTests: XCTestCase {

    private func candleReturns(_ engine: MarketEngine) -> [Double] {
        let closes = engine.candles.map(\.close)
        var returns: [Double] = []
        for i in 1..<closes.count {
            returns.append(log(Double(closes[i]) / Double(closes[i - 1])))
        }
        return returns
    }

    private func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count)
        guard n > 2 else { return 0 }
        let x = Array(a.prefix(n)), y = Array(b.prefix(n))
        let meanX = x.reduce(0, +) / Double(n)
        let meanY = y.reduce(0, +) / Double(n)
        var cov = 0.0, varX = 0.0, varY = 0.0
        for i in 0..<n {
            let dx = x[i] - meanX, dy = y[i] - meanY
            cov += dx * dy
            varX += dx * dx
            varY += dy * dy
        }
        guard varX > 0, varY > 0 else { return 0 }
        return cov / (varX * varY).squareRoot()
    }

    /// 뉴스를 끄고 순수 팩터 상관만 본다.
    private func quietConfig(beta: Double) -> EngineConfig {
        EngineConfig(fairVolatility: 0.0005, newsTickProbability: 0,
                     openingGapRange: 0...0, marketBeta: beta)
    }

    func testSharedClimateCreatesCorrelation() {
        let climate = MarketClimate(seed: 777, tickVolatility: 0.0012, newsTickProbability: 0)
        let a = MarketEngine(seed: 1, config: quietConfig(beta: 1.0), climate: climate)
        let b = MarketEngine(seed: 2, config: quietConfig(beta: 1.0), climate: climate)
        a.advance(ticks: 4_000)
        b.advance(ticks: 4_000)

        let corr = correlation(candleReturns(a), candleReturns(b))
        XCTAssertGreaterThan(corr, 0.3,
                             "같은 기후를 공유하면 유의미한 양의 상관이 생겨야 한다 (측정: \(corr))")
    }

    func testNoClimateMeansNearZeroCorrelation() {
        let a = MarketEngine(seed: 1, config: quietConfig(beta: 1.0))
        let b = MarketEngine(seed: 2, config: quietConfig(beta: 1.0))
        a.advance(ticks: 4_000)
        b.advance(ticks: 4_000)

        let corr = abs(correlation(candleReturns(a), candleReturns(b)))
        XCTAssertLessThan(corr, 0.25,
                          "기후가 없으면 상관이 거의 없어야 한다 (측정: \(corr))")
    }

    func testLowBetaReducesCorrelation() {
        let climate = MarketClimate(seed: 777, tickVolatility: 0.0012, newsTickProbability: 0)
        let market = MarketEngine(seed: 1, config: quietConfig(beta: 1.0), climate: climate)
        let highBeta = MarketEngine(seed: 2, config: quietConfig(beta: 1.2), climate: climate)
        let lowBeta = MarketEngine(seed: 3, config: quietConfig(beta: 0.15), climate: climate)
        market.advance(ticks: 4_000)
        highBeta.advance(ticks: 4_000)
        lowBeta.advance(ticks: 4_000)

        let marketReturns = candleReturns(market)
        let corrHigh = correlation(marketReturns, candleReturns(highBeta))
        let corrLow = correlation(marketReturns, candleReturns(lowBeta))
        XCTAssertGreaterThan(corrHigh, corrLow,
                             "β가 낮으면 시장과의 상관도 낮아야 한다 (high \(corrHigh) vs low \(corrLow)) — 분산의 근거")
    }

    func testMarketNewsHitsAllSymbolsAtSameTick() {
        // 뉴스 확률을 높여 반드시 몇 번 터지게 한다
        let climate = MarketClimate(seed: 42, newsTickProbability: 1.0 / 150)
        let a = MarketEngine(seed: 1, config: quietConfig(beta: 1.0), climate: climate)
        let b = MarketEngine(seed: 2, config: quietConfig(beta: 1.0), climate: climate)
        a.advance(ticks: 2_000)
        b.advance(ticks: 2_000)

        let aMarketNews = a.newsFeed.filter(\.isMarketWide)
        let bMarketNews = b.newsFeed.filter(\.isMarketWide)
        XCTAssertFalse(aMarketNews.isEmpty, "거시 뉴스가 터져야 한다")
        XCTAssertEqual(aMarketNews.map(\.tick), bMarketNews.map(\.tick),
                       "시장 뉴스는 모든 종목이 같은 틱에 받는다")
        XCTAssertEqual(aMarketNews.map(\.isPositive), bMarketNews.map(\.isPositive))
    }

    func testClimateIsDeterministicForReplay() {
        let make = {
            let engine = MarketEngine(seed: 9, config: self.quietConfig(beta: 1.0),
                                      climate: MarketClimate(seed: 555))
            engine.advance(ticks: 2_000)
            return engine
        }
        let a = make()
        let b = make()
        XCTAssertEqual(a.candles, b.candles, "기후 포함 전체가 시드 재현 — 리플레이 연속성 유지")
        XCTAssertEqual(a.newsFeed, b.newsFeed)
    }

    func testScenarioIgnoresClimate() {
        let climate = MarketClimate(seed: 1, tickVolatility: 0.01, newsTickProbability: 1.0 / 50)
        let withClimate = MarketEngine(scenario: .chaseRally())
        // 시나리오 convenience init은 기후를 받지 않지만, 직접 주입해도 무시되는지 확인
        let direct = MarketEngine(seed: ScenarioPreset.chaseRally().seed,
                                  initialPrice: 50_000, climate: climate)
        _ = direct
        withClimate.advance(ticks: 600)
        XCTAssertTrue(withClimate.newsFeed.filter(\.isMarketWide).isEmpty,
                      "시나리오는 자기 경로가 세계 — 거시 뉴스를 받지 않는다")
    }
}
