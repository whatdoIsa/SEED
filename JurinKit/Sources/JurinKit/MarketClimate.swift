import Foundation

/// 시장 기후 — 종목 간 상관관계의 근원 (1팩터 모델).
///
/// 모든 엔진이 같은 기후를 공유하면, 각 종목의 수익률은
/// `β × 시장 충격 + 개별 충격`이 되어 "시장 전체가 빠지는 날"이 생긴다.
/// 충격과 시장 뉴스는 (시드, 틱)의 순수 함수라 상태가 없다 —
/// 엔진들이 어떤 순서로 물어봐도 같은 답이 나오고, 리플레이 연속성이 보존된다.
public struct MarketClimate {
    public let seed: UInt64
    /// 시장 팩터의 틱당 변동성 (개별 종목보다 잔잔한 게 보통)
    public var tickVolatility: Double
    /// 시장 전체 뉴스(거시 이벤트) 틱당 확률
    public var newsTickProbability: Double
    /// 시장 뉴스 한 방의 크기 (β=1 기준 비율)
    public var newsMagnitudeRange: ClosedRange<Double>

    public init(seed: UInt64,
                tickVolatility: Double = 0.0005,
                newsTickProbability: Double = 1.0 / 2_000,
                newsMagnitudeRange: ClosedRange<Double> = 0.015...0.045) {
        self.seed = seed
        self.tickVolatility = tickVolatility
        self.newsTickProbability = newsTickProbability
        self.newsMagnitudeRange = newsMagnitudeRange
    }

    /// 시장 전체 뉴스 이벤트 — 모든 종목이 같은 틱에 같은 이벤트를 받는다.
    public struct MarketNews: Equatable {
        public let tick: Int
        public let isPositive: Bool
        /// β=1 기준 크기 (비율). 종목별 체감은 β를 곱한 값.
        public let magnitude: Double
        public let headlineIndex: Int
    }

    /// 이 틱의 시장 충격 (로그수익률). 같은 틱이면 항상 같은 값 — 상관의 원천.
    public func shock(at tick: Int) -> Double {
        var rng = tickRNG(tick: tick, stream: 0x51)
        let u1 = max(rng.double(in: 0...1), 1e-9)
        let u2 = rng.double(in: 0...1)
        let gaussian = (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        return gaussian * tickVolatility
    }

    /// 이 틱에 거시 뉴스가 터졌는가. 터졌다면 모든 종목이 동시에 받는다.
    public func news(at tick: Int) -> MarketNews? {
        var rng = tickRNG(tick: tick, stream: 0xB7)
        guard rng.chance(newsTickProbability) else { return nil }
        return MarketNews(
            tick: tick,
            isPositive: rng.chance(0.5),
            magnitude: rng.double(in: newsMagnitudeRange),
            headlineIndex: rng.int(in: 0...9)
        )
    }

    private func tickRNG(tick: Int, stream: UInt64) -> SeededRNG {
        SeededRNG(seed: seed ^ (stream &* 0x9E37_79B9_7F4A_7C15) &+ UInt64(tick) &* 0xBF58_476D_1CE4_E5B9)
    }
}
