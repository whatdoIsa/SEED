import Foundation

// MARK: - 에이전트 공통

/// 에이전트가 매 틱마다 보는 시장 스냅샷.
public struct MarketContext {
    public let tick: Int
    public let lastPrice: Int
    public let fairValue: Double
    public let bestBid: Int?
    public let bestAsk: Int?
    public let candles: [Candle]
    public let tickSize: Int

    public init(tick: Int, lastPrice: Int, fairValue: Double,
                bestBid: Int?, bestAsk: Int?, candles: [Candle], tickSize: Int) {
        self.tick = tick
        self.lastPrice = lastPrice
        self.fairValue = fairValue
        self.bestBid = bestBid
        self.bestAsk = bestAsk
        self.candles = candles
        self.tickSize = tickSize
    }

    /// 가격을 호가 단위로 스냅.
    public func snap(_ price: Double) -> Int {
        max(tickSize, Int((price / Double(tickSize)).rounded()) * tickSize)
    }
}

public struct OrderIntent {
    public enum Kind {
        case market(qty: Int)
        case limit(price: Int, qty: Int)
    }
    public let side: Side
    public let kind: Kind

    public init(side: Side, kind: Kind) {
        self.side = side
        self.kind = kind
    }
}

/// 시장 참여자. 거장 봇(P1)도 이 프로토콜의 새 구현일 뿐이다 — 엔진 구조 불변.
public protocol MarketAgent: AnyObject {
    var id: String { get }
    /// true면 매 행동 전에 자신의 기존 호가를 걷는다 (마켓메이커의 호가 갱신).
    var refreshesQuotes: Bool { get }
    func act(_ ctx: MarketContext, rng: inout SeededRNG) -> [OrderIntent]
}

// MARK: - 파라미터 (시나리오가 단계별로 오버라이드)

public struct AgentParams {
    /// 이번 틱에 행동할 확률 0...1
    public var activity: Double
    /// 주문 수량 범위
    public var minQty: Int
    public var maxQty: Int

    public init(activity: Double, minQty: Int, maxQty: Int) {
        self.activity = activity
        self.minQty = minQty
        self.maxQty = maxQty
    }
}

// MARK: - 1. 마켓메이커: 스프레드를 대고 유동성을 공급한다

public final class MarketMakerAgent: MarketAgent {
    public let id: String
    public let refreshesQuotes = true
    public var params: AgentParams
    /// 스프레드 절반 (틱 수)
    public var halfSpreadTicks: Int
    /// 양쪽에 까는 호가 레벨 수
    public var depthLevels: Int

    public init(id: String = "MM",
                params: AgentParams = AgentParams(activity: 1.0, minQty: 80, maxQty: 300),
                halfSpreadTicks: Int = 1, depthLevels: Int = 4) {
        self.id = id
        self.params = params
        self.halfSpreadTicks = halfSpreadTicks
        self.depthLevels = depthLevels
    }

    public func act(_ ctx: MarketContext, rng: inout SeededRNG) -> [OrderIntent] {
        guard rng.chance(params.activity) else { return [] }
        // 현재가와 적정가 사이에 살짝 기운 미드를 잡는다 → 가격이 fairValue를 느슨하게 따라간다.
        let mid = Double(ctx.lastPrice) * 0.7 + ctx.fairValue * 0.3
        var intents: [OrderIntent] = []
        for level in 0..<depthLevels {
            let offset = Double((halfSpreadTicks + level) * ctx.tickSize)
            let bidPrice = ctx.snap(mid - offset)
            let askPrice = ctx.snap(mid + offset)
            guard askPrice > bidPrice else { continue }
            let bidQty = rng.int(in: params.minQty...params.maxQty)
            let askQty = rng.int(in: params.minQty...params.maxQty)
            intents.append(OrderIntent(side: .buy, kind: .limit(price: bidPrice, qty: bidQty)))
            intents.append(OrderIntent(side: .sell, kind: .limit(price: askPrice, qty: askQty)))
        }
        return intents
    }
}

// MARK: - 2. 노이즈 트레이더: 잔파도를 만든다

public final class NoiseAgent: MarketAgent {
    public let id: String
    public let refreshesQuotes = false
    public var params: AgentParams
    /// 시장가로 지를 확률 (나머지는 터치 근처 지정가)
    public var marketOrderRatio: Double

    public init(id: String = "NOISE",
                params: AgentParams = AgentParams(activity: 0.7, minQty: 5, maxQty: 60),
                marketOrderRatio: Double = 0.35) {
        self.id = id
        self.params = params
        self.marketOrderRatio = marketOrderRatio
    }

    public func act(_ ctx: MarketContext, rng: inout SeededRNG) -> [OrderIntent] {
        guard rng.chance(params.activity) else { return [] }
        let side: Side = rng.chance(0.5) ? .buy : .sell
        let qty = rng.int(in: params.minQty...params.maxQty)
        if rng.chance(marketOrderRatio) {
            return [OrderIntent(side: side, kind: .market(qty: qty))]
        }
        // 터치에서 0~2틱 물러난 지정가
        let reference = side == .buy ? (ctx.bestBid ?? ctx.lastPrice) : (ctx.bestAsk ?? ctx.lastPrice)
        let backoff = rng.int(in: 0...2) * ctx.tickSize
        let price = side == .buy ? reference - backoff : reference + backoff
        return [OrderIntent(side: side, kind: .limit(price: max(ctx.tickSize, price), qty: qty))]
    }
}

// MARK: - 3. 추세추종: 모멘텀에 올라타 급등락을 증폭시킨다

public final class TrendFollowerAgent: MarketAgent {
    public let id: String
    public let refreshesQuotes = false
    public var params: AgentParams
    /// 모멘텀 판정에 쓰는 캔들 수
    public var lookback: Int
    /// 반응 임계 (틱 수)
    public var thresholdTicks: Int

    public init(id: String = "TREND",
                params: AgentParams = AgentParams(activity: 0.35, minQty: 20, maxQty: 120),
                lookback: Int = 5, thresholdTicks: Int = 2) {
        self.id = id
        self.params = params
        self.lookback = lookback
        self.thresholdTicks = thresholdTicks
    }

    public func act(_ ctx: MarketContext, rng: inout SeededRNG) -> [OrderIntent] {
        guard rng.chance(params.activity), ctx.candles.count >= lookback else { return [] }
        let recent = ctx.candles.suffix(lookback)
        guard let first = recent.first, let last = recent.last else { return [] }
        let momentum = last.close - first.close
        let threshold = thresholdTicks * ctx.tickSize
        let qty = rng.int(in: params.minQty...params.maxQty)
        if momentum >= threshold {
            return [OrderIntent(side: .buy, kind: .market(qty: qty))]
        } else if momentum <= -threshold {
            return [OrderIntent(side: .sell, kind: .market(qty: qty))]
        }
        return []
    }
}

// MARK: - 4. 가치투자: fairValue 대비 싸면 사고 비싸면 판다 (평균회귀의 원천)

public final class ValueInvestorAgent: MarketAgent {
    public let id: String
    public let refreshesQuotes = false
    public var params: AgentParams
    /// 안전마진: fair 대비 이만큼 싸야 산다
    public var marginOfSafety: Double
    /// 프리미엄: fair 대비 이만큼 비싸면 판다
    public var premium: Double

    public init(id: String = "VALUE",
                params: AgentParams = AgentParams(activity: 0.25, minQty: 30, maxQty: 150),
                marginOfSafety: Double = 0.015, premium: Double = 0.02) {
        self.id = id
        self.params = params
        self.marginOfSafety = marginOfSafety
        self.premium = premium
    }

    public func act(_ ctx: MarketContext, rng: inout SeededRNG) -> [OrderIntent] {
        guard rng.chance(params.activity) else { return [] }
        let price = Double(ctx.lastPrice)
        let qty = rng.int(in: params.minQty...params.maxQty)
        if price <= ctx.fairValue * (1 - marginOfSafety) {
            // 저평가 → 최우선 매수호가에 조용히 깐다
            let bid = ctx.bestBid ?? ctx.lastPrice
            return [OrderIntent(side: .buy, kind: .limit(price: bid, qty: qty))]
        }
        if price >= ctx.fairValue * (1 + premium) {
            // 고평가 → 시장가 매도로 과열을 식힌다
            return [OrderIntent(side: .sell, kind: .market(qty: qty))]
        }
        return []
    }
}
