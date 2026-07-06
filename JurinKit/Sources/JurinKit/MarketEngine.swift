import Foundation
import Observation

// MARK: - 포트폴리오

public struct Portfolio {
    public private(set) var cash: Int
    public private(set) var qty: Int = 0
    public private(set) var avgCost: Double = 0
    public private(set) var realizedPnL: Double = 0

    public init(cash: Int) {
        self.cash = cash
    }

    public func marketValue(at price: Int) -> Int { qty * price }
    public func equity(at price: Int) -> Int { cash + marketValue(at: price) }

    public func unrealizedPnL(at price: Int) -> Double {
        Double(qty) * (Double(price) - avgCost)
    }

    mutating func applyBuy(_ result: FillResult) {
        let cost = result.notional
        let newQty = qty + result.filledQty
        if newQty > 0 {
            avgCost = (avgCost * Double(qty) + Double(cost)) / Double(newQty)
        }
        qty = newQty
        cash -= cost
    }

    mutating func applySell(_ result: FillResult) {
        let proceeds = result.notional
        realizedPnL += Double(proceeds) - avgCost * Double(result.filledQty)
        qty -= result.filledQty
        if qty == 0 { avgCost = 0 }
        cash += proceeds
    }
}

// MARK: - 주문 오류

public enum OrderError: Error, Equatable {
    case insufficientCash(needed: Int, available: Int)
    case insufficientHoldings(requested: Int, held: Int)
    case noLiquidity
    case invalidQuantity
}

// MARK: - 엔진 설정

public struct EngineConfig {
    public var tickSize: Int
    public var ticksPerCandle: Int
    /// fairValue 랜덤워크 변동성 (틱당 로그수익률 표준편차 근사)
    public var fairVolatility: Double
    /// fairValue가 앵커로 되돌아가는 힘 0...1 (0이면 순수 랜덤워크)
    public var meanReversion: Double
    public var initialCash: Int

    public init(tickSize: Int = 50,
                ticksPerCandle: Int = 20,
                fairVolatility: Double = 0.0009,
                meanReversion: Double = 0.002,
                initialCash: Int = 10_000_000) {
        self.tickSize = tickSize
        self.ticksPerCandle = ticksPerCandle
        self.fairVolatility = fairVolatility
        self.meanReversion = meanReversion
        self.initialCash = initialCash
    }
}

// MARK: - 시장 엔진

/// 틱 루프의 심장. 가격은 그려지지 않는다 — 에이전트들의 체결 결과로 발생한다.
/// Timer를 갖지 않는다: UI 레이어가 배속에 맞춰 step()/advance()를 호출한다.
@Observable
public final class MarketEngine {
    public let config: EngineConfig
    public private(set) var book = OrderBook()
    public private(set) var candles: [Candle] = []
    public private(set) var currentCandle: Candle
    public private(set) var lastPrice: Int
    public private(set) var fairValue: Double
    /// meanReversion이 끌어당기는 기준점. 시나리오(ScenarioPreset)가 이 값을 조작한다.
    public var fairAnchor: Double
    public private(set) var tick: Int = 0
    public private(set) var tape: [Trade] = []
    public private(set) var portfolio: Portfolio

    private var agents: [MarketAgent]
    private var rng: SeededRNG
    private let tapeLimit = 60
    public static let userAgentId = "USER"

    public init(seed: UInt64,
                initialPrice: Int = 52_300,
                config: EngineConfig = EngineConfig(),
                agents: [MarketAgent]? = nil) {
        self.config = config
        self.lastPrice = initialPrice
        self.fairValue = Double(initialPrice)
        self.fairAnchor = Double(initialPrice)
        self.portfolio = Portfolio(cash: config.initialCash)
        self.rng = SeededRNG(seed: seed)
        self.currentCandle = Candle(open: initialPrice, index: 0)
        self.agents = agents ?? [
            MarketMakerAgent(),
            NoiseAgent(),
            TrendFollowerAgent(),
            ValueInvestorAgent()
        ]
        seedInitialBook()
    }

    /// 시작 시 빈 호가창을 마켓메이커 스타일로 채워 첫 주문부터 체결이 가능하게 한다.
    private func seedInitialBook() {
        for level in 1...5 {
            let offset = level * config.tickSize
            book.submitLimit(agentId: "SEED", side: .buy,
                             price: lastPrice - offset, qty: 150 + level * 30, tick: 0)
            book.submitLimit(agentId: "SEED", side: .sell,
                             price: lastPrice + offset, qty: 150 + level * 30, tick: 0)
        }
    }

    // MARK: 틱 루프

    /// 1틱: fairValue 진화 → 에이전트 행동 → 체결 반영 → 분봉 마감 판정.
    public func step() {
        tick += 1
        evolveFairValue()

        let ctx = MarketContext(tick: tick, lastPrice: lastPrice, fairValue: fairValue,
                                bestBid: book.bestBid, bestAsk: book.bestAsk,
                                candles: candles, tickSize: config.tickSize)

        for agent in agents.shuffled(using: &rng) {
            if agent.refreshesQuotes { book.cancelAll(agentId: agent.id) }
            for intent in agent.act(ctx, rng: &rng) {
                apply(intent, from: agent.id)
            }
        }

        if tick % config.ticksPerCandle == 0 {
            closeCandle()
        }
    }

    /// 배속·스킵·백그라운드 복귀가 모두 이 한 줄로 수렴한다.
    public func advance(ticks: Int) {
        guard ticks > 0 else { return }
        for _ in 0..<ticks { step() }
    }

    /// 다음 분봉 경계까지 스킵.
    public func advanceToNextCandle() {
        let remaining = config.ticksPerCandle - (tick % config.ticksPerCandle)
        advance(ticks: remaining)
    }

    private func evolveFairValue() {
        // Box-Muller 가우시안 랜덤워크 + 앵커로의 평균회귀
        let u1 = max(rng.double(in: 0...1), 1e-9)
        let u2 = rng.double(in: 0...1)
        let gaussian = (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        let shock = gaussian * config.fairVolatility
        let pull = (fairAnchor - fairValue) / fairValue * config.meanReversion
        fairValue *= exp(shock + pull)
        fairValue = max(fairValue, Double(config.tickSize))
    }

    private func apply(_ intent: OrderIntent, from agentId: String) {
        let trades: [Trade]
        switch intent.kind {
        case .market(let qty):
            guard qty > 0 else { return }
            let (_, executed) = book.executeMarket(agentId: agentId, side: intent.side, qty: qty, tick: tick)
            trades = executed
        case .limit(let price, let qty):
            guard qty > 0, price > 0 else { return }
            trades = book.submitLimit(agentId: agentId, side: intent.side, price: price, qty: qty, tick: tick)
        }
        record(trades)
    }

    private func record(_ trades: [Trade]) {
        guard !trades.isEmpty else { return }
        for trade in trades {
            lastPrice = trade.price
            currentCandle.apply(trade)
        }
        tape.append(contentsOf: trades)
        if tape.count > tapeLimit {
            tape.removeFirst(tape.count - tapeLimit)
        }
    }

    private func closeCandle() {
        candles.append(currentCandle)
        currentCandle = Candle(open: lastPrice, index: candles.count)
    }

    // MARK: 사용자 주문 (시장가)

    /// 화면에 보이는 가격 — 최우선 반대 호가. 슬리피지의 기준점.
    public func displayedPrice(for side: Side) -> Int? {
        side == .buy ? book.bestAsk : book.bestBid
    }

    /// 시장가 주문. 다단계 체결 내역과 슬리피지가 담긴 FillResult를 돌려준다.
    /// 이 반환값이 슬리피지 튜토리얼(레슨 2)의 원료다.
    public func placeMarketOrder(side: Side, qty: Int) throws -> FillResult {
        guard qty > 0 else { throw OrderError.invalidQuantity }
        guard let displayed = displayedPrice(for: side) else { throw OrderError.noLiquidity }

        // 실행 전에 정확한 비용을 미리 계산해 잔고를 검증한다 (드라이런).
        let preview = book.previewMarket(side: side, qty: qty)
        guard !preview.isEmpty else { throw OrderError.noLiquidity }

        switch side {
        case .buy:
            let cost = preview.reduce(0) { $0 + $1.price * $1.qty }
            guard cost <= portfolio.cash else {
                throw OrderError.insufficientCash(needed: cost, available: portfolio.cash)
            }
        case .sell:
            guard qty <= portfolio.qty else {
                throw OrderError.insufficientHoldings(requested: qty, held: portfolio.qty)
            }
        }

        let (fills, trades) = book.executeMarket(agentId: Self.userAgentId, side: side, qty: qty, tick: tick)
        record(trades)

        let result = FillResult(side: side, requestedQty: qty, fills: fills, displayedPrice: displayed)
        switch side {
        case .buy: portfolio.applyBuy(result)
        case .sell: portfolio.applySell(result)
        }
        return result
    }
}

// MARK: - 이동평균 (차트 오버레이 원료, Lv2 해금)

public extension Array where Element == Candle {
    /// 단순이동평균. 캔들 수가 부족한 앞부분은 nil.
    func movingAverage(period: Int) -> [Double?] {
        guard period > 0 else { return map { _ in nil } }
        var result: [Double?] = []
        var windowSum = 0
        for (i, candle) in enumerated() {
            windowSum += candle.close
            if i >= period {
                windowSum -= self[i - period].close
            }
            result.append(i >= period - 1 ? Double(windowSum) / Double(period) : nil)
        }
        return result
    }
}
