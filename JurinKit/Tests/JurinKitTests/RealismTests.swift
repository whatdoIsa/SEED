import XCTest
@testable import JurinKit

final class RealismTests: XCTestCase {

    func testNewsEventsFireAndMoveAnchor() {
        let engine = MarketEngine(seed: 123)
        let anchorBefore = engine.fairAnchor
        engine.advance(ticks: 10_000)

        XCTAssertFalse(engine.newsFeed.isEmpty, "10,000틱이면 뉴스가 여러 번 터져야 한다")
        for event in engine.newsFeed {
            XCTAssertTrue((2.0...7.0).contains(event.magnitudePct),
                          "뉴스 크기는 설정 범위 안이어야 한다: \(event.magnitudePct)")
            XCTAssertTrue((0...9).contains(event.headlineIndex))
        }
        XCTAssertNotEqual(engine.fairAnchor, anchorBefore, "뉴스가 앵커를 움직여야 한다")
        XCTAssertGreaterThan(engine.lastPrice, 0)
        if engine.isInAuction { engine.advance(ticks: engine.auctionTicksRemaining) }
        XCTAssertNotNil(engine.book.bestBid, "뉴스 폭풍 속에서도 시장은 살아 있어야 한다")
    }

    func testNoNewsDuringScenario() {
        let engine = MarketEngine(scenario: .chaseRally())
        engine.advance(ticks: 600)
        XCTAssertTrue(engine.newsFeed.isEmpty, "시나리오 중에는 뉴스가 꺼져 프리셋 경로를 보호한다")
    }

    func testNewsCanBeDisabled() {
        let engine = MarketEngine(seed: 123, config: EngineConfig(newsTickProbability: 0))
        engine.advance(ticks: 5_000)
        XCTAssertTrue(engine.newsFeed.isEmpty)
    }

    func testVolatilityClusteringBuildsAfterShock() {
        let engine = MarketEngine(seed: 55, config: EngineConfig(newsTickProbability: 0))
        engine.advance(ticks: 400)
        let calmMomentum = engine.volatilityMomentum

        // 인위적 충격: 앵커를 12% 점프시키면 큰 캔들들이 나오고, 군집 기억이 커져야 한다
        engine.fairAnchor *= 1.12
        engine.advance(ticks: 200)

        XCTAssertGreaterThan(engine.volatilityMomentum, calmMomentum,
                             "충격 후 변동성 기억이 커져야 한다 (군집)")
    }

    func testDeterminismStillHoldsWithRealism() {
        let a = MarketEngine(seed: 77)
        let b = MarketEngine(seed: 77)
        a.advance(ticks: 3_000)
        b.advance(ticks: 3_000)
        XCTAssertEqual(a.candles, b.candles)
        XCTAssertEqual(a.newsFeed, b.newsFeed, "뉴스도 시드에 종속 — 리플레이 연속성 유지")
    }
}

/// SeededRNG의 구간 매핑·셔플을 값으로 고정한다.
/// 이 테스트가 깨지는 변경 = 저장된 전 세션의 리플레이가 깨지는 변경 — 절대 알고리즘을 바꾸지 말 것.
final class RNGPinningTests: XCTestCase {
    func testMappingIsPinnedForever() {
        var rng = SeededRNG(seed: 42)
        XCTAssertEqual(rng.int(in: 0...100), 23)
        XCTAssertEqual(rng.double(in: -1...1), -0.6801792142461598, accuracy: 1e-15)
        XCTAssertEqual(rng.double01(), 0.27860113025513866, accuracy: 1e-15)
        XCTAssertEqual(rng.int(in: 1_000...52_000), 21_379)
        XCTAssertEqual(rng.shuffled(Array(1...8)), [1, 7, 8, 6, 4, 2, 5, 3])
    }
}
