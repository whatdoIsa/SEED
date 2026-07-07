import XCTest
@testable import JurinKit

final class ScenarioTests: XCTestCase {

    // MARK: 키프레임 보간

    func testAnchorInterpolation() {
        let preset = ScenarioPreset(
            id: "test", seed: 1, initialPrice: 1_000, durationTicks: 100,
            anchorPull: 0.1,
            keyframes: [
                ScenarioPreset.Keyframe(tick: 0, value: 1_000),
                ScenarioPreset.Keyframe(tick: 100, value: 2_000)
            ]
        )
        XCTAssertEqual(preset.anchorValue(at: 0), 1_000)
        XCTAssertEqual(preset.anchorValue(at: 50), 1_500)
        XCTAssertEqual(preset.anchorValue(at: 100), 2_000)
        // 범위 밖은 양 끝값 고정
        XCTAssertEqual(preset.anchorValue(at: -10), 1_000)
        XCTAssertEqual(preset.anchorValue(at: 500), 2_000)
    }

    // MARK: 재현성 — 같은 프리셋이면 같은 시장 (AC)

    func testScenarioDeterminism() {
        let a = MarketEngine(scenario: .chaseRally())
        let b = MarketEngine(scenario: .chaseRally())
        a.advance(ticks: 600)
        b.advance(ticks: 600)
        XCTAssertEqual(a.candles, b.candles)
        XCTAssertEqual(a.lastPrice, b.lastPrice)
    }

    // MARK: 5단계 경로 — 급등 후 평균회귀가 실제로 형성되는가

    func testRallyThenMeanReversionShape() {
        let engine = MarketEngine(scenario: .chaseRally())
        engine.advance(ticks: 600)
        XCTAssertTrue(engine.isScenarioFinished)

        let closes = engine.candles.map(\.close)
        // 캔들 = 20틱. 오버슛 구간(틱 240~340) ≈ 캔들 12~16
        let overshootWindow = closes[12...16]
        let peak = overshootWindow.max() ?? 0
        let end = closes.suffix(3).max() ?? 0

        XCTAssertGreaterThan(peak, 55_500, "오버슛 구간이 충분히 과열되어야 한다")
        XCTAssertLessThan(end, 54_000, "종반에는 평균회귀가 완료되어야 한다")
        XCTAssertGreaterThan(peak - end, 3_000, "고점과 안정화 가격의 낙차가 학습에 충분해야 한다")
    }

    // MARK: 핵심 AC — 오버슛 추격 매수는 손실로 끝난다

    func testChaseBuyAtOvershootLoses() throws {
        let engine = MarketEngine(scenario: .chaseRally())
        engine.advance(ticks: 295) // 결정 지점(290) 직후, 오버슛 한복판
        let fill = try engine.placeMarketOrder(side: .buy, qty: 100)
        engine.advance(ticks: 600 - engine.tick)

        let unrealized = engine.portfolio.unrealizedPnL(at: engine.lastPrice)
        XCTAssertLessThan(unrealized, 0, "추격 매수는 평균회귀 후 손실이어야 한다 (평단 \(fill.avgFillPrice), 종가 \(engine.lastPrice))")
    }

    // MARK: 핵심 AC — 첫 눌림을 기다린 매수가 추격보다 낫다

    func testDipBuyBeatsChaseBuy() throws {
        let chase = MarketEngine(scenario: .chaseRally())
        chase.advance(ticks: 295)
        let chaseFill = try chase.placeMarketOrder(side: .buy, qty: 100)
        chase.advance(ticks: 600 - chase.tick)

        let dip = MarketEngine(scenario: .chaseRally())
        dip.advance(ticks: 470) // 평균회귀가 진행된 눌림 구간
        let dipFill = try dip.placeMarketOrder(side: .buy, qty: 100)
        dip.advance(ticks: 600 - dip.tick)

        XCTAssertLessThan(dipFill.avgFillPrice, chaseFill.avgFillPrice - 2_000,
                          "눌림 매수 평단이 추격 평단보다 확실히 낮아야 한다")
        let chasePnL = chase.portfolio.unrealizedPnL(at: chase.lastPrice)
        let dipPnL = dip.portfolio.unrealizedPnL(at: dip.lastPrice)
        XCTAssertGreaterThan(dipPnL, chasePnL, "같은 수량이면 눌림 매수의 성적이 나아야 한다")
    }

    // MARK: 결정 지점 노출

    func testDecisionPromptAppearsOnceAndResolves() {
        let engine = MarketEngine(scenario: .chaseRally())
        engine.advance(ticks: 289)
        XCTAssertNil(engine.pendingDecision)

        engine.advance(ticks: 1) // tick 290 도달
        XCTAssertNotNil(engine.pendingDecision)
        XCTAssertEqual(engine.pendingDecision?.options.map(\.tagRaw), ["chase", "dip"])

        engine.resolveDecision()
        XCTAssertNil(engine.pendingDecision)

        engine.advance(ticks: 50) // 같은 결정이 다시 나타나지 않는다
        XCTAssertNil(engine.pendingDecision)
    }

    // MARK: 급락 시나리오 (⑥) — 패닉 매도는 버티기보다 나쁘다

    func testPanicCrashShape() {
        let engine = MarketEngine(scenario: .panicCrash())
        engine.advance(ticks: 600)
        let closes = engine.candles.map(\.close)
        // 캔들 = 20틱. 급락 바닥 구간(틱 200~300) ≈ 캔들 10~15
        let bottom = closes[10...15].min() ?? 0
        let end = closes.suffix(3).max() ?? 0
        XCTAssertLessThan(bottom, 45_000, "급락이 충분히 깊어야 공포가 진짜가 된다")
        XCTAssertGreaterThan(end, bottom + 2_000, "종반에는 부분 회복이 있어야 한다")
    }

    func testPanicSellIsWorseThanHolding() throws {
        // A: 보유 시작 → 공포 구간에서 전량 매도
        let panic = MarketEngine(scenario: .panicCrash())
        panic.advance(ticks: 80)
        _ = try panic.placeMarketOrder(side: .buy, qty: 100)
        panic.advance(ticks: 200 - panic.tick)
        _ = try panic.placeMarketOrder(side: .sell, qty: 100)
        panic.advance(ticks: 600 - panic.tick)

        // B: 같은 시점 매수 → 끝까지 버티기
        let hold = MarketEngine(scenario: .panicCrash())
        hold.advance(ticks: 80)
        _ = try hold.placeMarketOrder(side: .buy, qty: 100)
        hold.advance(ticks: 600 - hold.tick)

        let panicEquity = panic.portfolio.equity(at: panic.lastPrice)
        let holdEquity = hold.portfolio.equity(at: hold.lastPrice)
        XCTAssertGreaterThan(holdEquity, panicEquity,
                             "부분 회복 시나리오에서 버티기가 패닉 매도보다 나아야 한다")
    }

    // MARK: 오버라이드 복원 — 구간이 끝나면 기본 파라미터로 돌아간다

    func testAgentOverrideRestoredAfterPhase() {
        let trend = TrendFollowerAgent()
        let baselineActivity = trend.params.activity
        let engine = MarketEngine(
            scenario: .chaseRally(),
            agents: [MarketMakerAgent(), NoiseAgent(), trend, ValueInvestorAgent()]
        )
        engine.advance(ticks: 250) // 급등 구간 (180..<330): 오버라이드 적용 중
        XCTAssertEqual(trend.params.activity, 0.9, accuracy: 0.0001)

        engine.advance(ticks: 150) // tick 400: 구간 종료 후 복원
        XCTAssertEqual(trend.params.activity, baselineActivity, accuracy: 0.0001)
    }


    // MARK: 데드캣 바운스

    func testDeadCatBounceShape() {
        let engine = MarketEngine(scenario: .deadCatBounce())
        engine.advance(ticks: 640)
        let closes = engine.candles.map(\.close)
        // 캔들=20틱. 반등 고점(틱 240 ≈ 캔들 12)이 진짜 바닥(틱 520 ≈ 캔들 26)보다 확실히 높다
        let bouncePeak = closes[10...14].max() ?? 0
        let realBottom = closes[24...28].min() ?? 0
        XCTAssertGreaterThan(bouncePeak, realBottom + 4_000,
                             "반짝 반등 뒤 진짜 하락이 더 깊어야 함정이 성립한다")
    }

    func testDeadCatBounceChaseLosesVsWaiting() throws {
        // 반등에 속아 산 사람 vs 기다린 사람
        let chase = MarketEngine(scenario: .deadCatBounce())
        chase.advance(ticks: 290) // 반등 결정 지점 직후
        _ = try chase.placeMarketOrder(side: .buy, qty: 100)
        chase.advance(ticks: 640 - chase.tick)

        let wait = MarketEngine(scenario: .deadCatBounce())
        wait.advance(ticks: 520) // 진짜 바닥
        _ = try wait.placeMarketOrder(side: .buy, qty: 100)
        wait.advance(ticks: 640 - wait.tick)

        XCTAssertGreaterThan(wait.portfolio.avgCost - chase.portfolio.avgCost, 0 - 100_000) // sanity
        XCTAssertLessThan(wait.portfolio.avgCost, chase.portfolio.avgCost,
                          "진짜 바닥 매수 평단이 반등 추격 평단보다 낮아야 한다")
    }

    // MARK: 횡보

    func testSidewaysStaysInBox() {
        let engine = MarketEngine(scenario: .sideways())
        engine.advance(ticks: 600)
        let closes = engine.candles.map { Double($0.close) }
        let high = closes.max() ?? 0
        let low = closes.min() ?? 1
        // 박스권: 고점/저점 폭이 시작가의 8% 이내
        XCTAssertLessThan((high - low) / 50_000, 0.08,
                          "횡보는 좁은 박스권을 유지해야 한다 (폭 \((high-low)/50_000))")
    }

    func testSidewaysFrequentTradingBleedsToFees() throws {
        // 지루함에 자주 사고팔면 수수료로 손실이 쌓인다
        let engine = MarketEngine(scenario: .sideways())
        engine.advance(ticks: 40)
        let startEquity = engine.portfolio.equity(at: engine.lastPrice)
        for _ in 0..<8 {
            _ = try? engine.placeMarketOrder(side: .buy, qty: 50)
            engine.advance(ticks: 30)
            _ = try? engine.placeMarketOrder(side: .sell, qty: 50)
            engine.advance(ticks: 30)
        }
        let endEquity = engine.portfolio.equity(at: engine.lastPrice)
        XCTAssertGreaterThan(engine.portfolio.feesPaid, 0)
        XCTAssertLessThan(endEquity, startEquity,
                          "방향 없는 장에서 잦은 매매는 수수료로 계좌를 갉는다")
    }
}
