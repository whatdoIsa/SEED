import XCTest
@testable import JurinKit

/// 동시호가 (장 시작 단일가) — 주문 수집 → 단일 청산가 일괄 체결 → 연속 매매 재개.
final class AuctionTests: XCTestCase {

    private func makeEngine(seed: UInt64 = 7) -> MarketEngine {
        var config = EngineConfig()
        config.candlesPerDay = 2 // 2캔들마다 거래일 전환 → 빨리 동시호가에 도달
        return MarketEngine(seed: seed, config: config)
    }

    func testAuctionCollectsThenClears() {
        let engine = makeEngine()
        let ticksPerDay = engine.config.ticksPerCandle * engine.config.candlesPerDay

        // 1거래일 종료 직후 → 동시호가 개시
        engine.advance(ticks: ticksPerDay)
        XCTAssertTrue(engine.isInAuction, "거래일이 열리면 동시호가가 시작된다")
        XCTAssertEqual(engine.tradingDay, 2)

        // 수집 구간: 체결(테이프)이 늘지 않는다
        let tapeBefore = engine.tape.count
        engine.advance(ticks: engine.config.auctionTicks - 1)
        XCTAssertEqual(engine.tape.count, tapeBefore, "수집 구간엔 체결이 없다")
        XCTAssertTrue(engine.isInAuction)

        // 마지막 틱: 단일가 일괄 체결
        engine.step()
        XCTAssertFalse(engine.isInAuction, "청산 후 연속 매매로 복귀")
        XCTAssertGreaterThan(engine.tape.count, tapeBefore, "청산 체결이 테이프에 찍힌다")

        // 청산가는 상·하한 밴드 안
        XCTAssertLessThanOrEqual(engine.lastPrice, engine.upperLimitPrice)
        XCTAssertGreaterThanOrEqual(engine.lastPrice, engine.lowerLimitPrice)
    }

    func testMarketOrderRejectedDuringAuction() {
        let engine = makeEngine()
        engine.advance(ticks: engine.config.ticksPerCandle * engine.config.candlesPerDay + 1)
        XCTAssertTrue(engine.isInAuction)
        XCTAssertThrowsError(try engine.placeMarketOrder(side: .buy, qty: 10)) { error in
            XCTAssertEqual(error as? OrderError, .auctionInProgress)
        }
    }

    func testLimitOrderAcceptedDuringAuctionAndFillsAfter() throws {
        let engine = makeEngine()
        engine.advance(ticks: engine.config.ticksPerCandle * engine.config.candlesPerDay + 1)
        XCTAssertTrue(engine.isInAuction)

        // 동시호가 중에도 지정가는 접수된다 — 넉넉히 높은 매수가로 걸어두면
        let result = try engine.placeLimitOrder(side: .buy,
                                                price: engine.upperLimitPrice,
                                                qty: 10)
        XCTAssertNil(result.immediateFill, "수집 구간엔 즉시 체결이 없다")

        // 청산 후 연속 매매가 재개되면 체결된다
        engine.advance(ticks: engine.config.auctionTicks + 40)
        _ = engine.drainUserFillEvents()
        XCTAssertEqual(engine.portfolio.qty, 10, "청산 뒤 대기 지정가가 체결된다")
    }

    func testAuctionIsDeterministic() {
        let ticks = 200
        let a = makeEngine(seed: 99)
        let b = makeEngine(seed: 99)
        a.advance(ticks: ticks)
        b.advance(ticks: ticks)
        XCTAssertEqual(a.lastPrice, b.lastPrice, "동시호가 포함 전 경로가 결정론적이다")
        XCTAssertEqual(a.tape.map(\.price), b.tape.map(\.price))
    }

    func testScenarioAndCryptoSkipAuction() {
        // 시나리오는 프리셋 경로 보호를 위해 동시호가 없음
        let scenarioEngine = MarketEngine(scenario: .chaseRally())
        scenarioEngine.advance(ticks: 100)
        XCTAssertFalse(scenarioEngine.isInAuction)

        // 크립토(candlesPerDay = 0)는 거래일 자체가 없어 발동 불가
        var config = EngineConfig()
        config.candlesPerDay = 0
        let crypto = MarketEngine(seed: 3, config: config)
        crypto.advance(ticks: 300)
        XCTAssertFalse(crypto.isInAuction)
    }
}
