import XCTest
@testable import JurinKit

/// 다종목 부하 측정 — 앱과 같은 구성(공유 원장 + 상관관계 + 6엔진)으로
/// 30배속 사용 시의 스텝 비용을 잰다.
/// 앱의 30배속: 초당 30틱 × 6엔진 = 180스텝/초. 이 테스트는 그 100초 분량(18,000틱×6)을 돌린다.
final class PerformanceTests: XCTestCase {

    private func makeFleet() -> [MarketEngine] {
        let ledger = AccountLedger(cash: 10_000_000)
        let climate = MarketClimate(seed: 42)
        let betas: [Double] = [0.85, 1.0, 1.4, 0.45, -0.5, 0.2]
        return betas.enumerated().map { index, beta in
            var config = EngineConfig()
            config.marketBeta = beta
            return MarketEngine(seed: UInt64(1_000 + index), config: config,
                                ledger: ledger, climate: climate)
        }
    }

    func testSixEngines30xLoad() {
        let engines = makeFleet()
        let ticks = 18_000 // 30배속 100초 분량

        let start = Date()
        for _ in 0..<ticks {
            for engine in engines { engine.step() }
        }
        let elapsed = Date().timeIntervalSince(start)
        let stepsPerSecond = Double(ticks * engines.count) / elapsed
        let cpuShareAt30x = 180.0 / stepsPerSecond * 100 // 실사용 대비 CPU 점유율 추정

        print("PERF: \(ticks)틱 × 6엔진 = \(ticks*6)스텝, \(String(format: "%.2f", elapsed))초")
        print("PERF: \(String(format: "%.0f", stepsPerSecond)) 스텝/초 처리 가능")
        print("PERF: 30배속 실사용(180스텝/초)의 CPU 점유 추정 \(String(format: "%.2f", cpuShareAt30x))%")

        // 실사용 부하가 한 코어의 5%를 넘으면 최적화 필요 신호
        XCTAssertLessThan(cpuShareAt30x, 5.0,
                          "6엔진 30배속이 코어의 5%를 초과 — 스텝 경로 최적화 필요")
    }

    func testCandleMemoryFootprint() {
        // 긴 시즌: 6엔진이 각각 캔들 3,000개(≈100거래일)를 쌓았을 때의 대략적 메모리
        let engines = makeFleet()
        for _ in 0..<(3_000 * 20) { // 캔들당 20틱
            for engine in engines { engine.step() }
        }
        let totalCandles = engines.map(\.candles.count).reduce(0, +)
        let approxBytes = totalCandles * MemoryLayout<Candle>.stride
        print("PERF: 총 캔들 \(totalCandles)개, 대략 \(approxBytes / 1024)KB")
        XCTAssertLessThan(approxBytes, 50 * 1024 * 1024, "캔들 메모리가 50MB 초과")
    }
}
