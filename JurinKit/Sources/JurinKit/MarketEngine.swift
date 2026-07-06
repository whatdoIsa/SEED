import Foundation
import Observation

// MARK: - 포트폴리오

public struct Portfolio {
    public private(set) var cash: Int
    public private(set) var qty: Int = 0
    public private(set) var avgCost: Double = 0
    public private(set) var realizedPnL: Double = 0
    /// 미체결 지정가 매수에 묶인 돈 (증거금 개념 — 이중 지출 방지)
    public private(set) var reservedCash: Int = 0
    /// 미체결 지정가 매도에 묶인 주식
    public private(set) var reservedShares: Int = 0

    public var availableCash: Int { cash - reservedCash }
    public var availableShares: Int { qty - reservedShares }

    public init(cash: Int) {
        self.cash = cash
    }

    /// 영속 저장에서 복원할 때 사용.
    public init(cash: Int, qty: Int, avgCost: Double, realizedPnL: Double) {
        self.cash = cash
        self.qty = qty
        self.avgCost = avgCost
        self.realizedPnL = realizedPnL
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

    // MARK: 지정가 예약·정산

    mutating func reserveCash(_ amount: Int) { reservedCash += amount }
    mutating func releaseCash(_ amount: Int) { reservedCash = max(reservedCash - amount, 0) }
    mutating func reserveShares(_ amount: Int) { reservedShares += amount }
    mutating func releaseShares(_ amount: Int) { reservedShares = max(reservedShares - amount, 0) }

    /// 대기 중이던 지정가 매수가 체결됨 — 예약금으로 정산.
    mutating func settleRestingBuy(price: Int, qty fillQty: Int) {
        let cost = price * fillQty
        releaseCash(cost)
        let newQty = qty + fillQty
        if newQty > 0 {
            avgCost = (avgCost * Double(qty) + Double(cost)) / Double(newQty)
        }
        qty = newQty
        cash -= cost
    }

    /// 대기 중이던 지정가 매도가 체결됨 — 예약 주식으로 정산.
    mutating func settleRestingSell(price: Int, qty fillQty: Int) {
        releaseShares(fillQty)
        realizedPnL += (Double(price) - avgCost) * Double(fillQty)
        qty -= fillQty
        if qty == 0 { avgCost = 0 }
        cash += price * fillQty
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
    /// 변동성 군집 강도 (③): 최근 변동이 클수록 다음 변동도 커진다. 0이면 비활성.
    public var volClusterGain: Double
    /// 틱당 뉴스 이벤트 확률 (③). 시나리오 중에는 자동 비활성.
    public var newsTickProbability: Double
    /// 뉴스 한 방이 fairAnchor를 움직이는 크기 (비율)
    public var newsMagnitudeRange: ClosedRange<Double>

    public init(tickSize: Int = 50,
                ticksPerCandle: Int = 20,
                fairVolatility: Double = 0.0009,
                meanReversion: Double = 0.002,
                initialCash: Int = 10_000_000,
                volClusterGain: Double = 40,
                newsTickProbability: Double = 1.0 / 900,
                newsMagnitudeRange: ClosedRange<Double> = 0.02...0.07) {
        self.tickSize = tickSize
        self.ticksPerCandle = ticksPerCandle
        self.fairVolatility = fairVolatility
        self.meanReversion = meanReversion
        self.initialCash = initialCash
        self.volClusterGain = volClusterGain
        self.newsTickProbability = newsTickProbability
        self.newsMagnitudeRange = newsMagnitudeRange
    }
}

/// 뉴스 이벤트 (③) — fairAnchor를 점프시켜 갭·급변을 만든다.
/// 헤드라인 문구는 앱이 headlineIndex로 매핑한다 (코어는 카피를 모른다).
public struct NewsEvent: Equatable {
    public let tick: Int
    public let isPositive: Bool
    public let magnitudePct: Double
    public let headlineIndex: Int
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

    // MARK: 사용자 지정가 상태 (①)

    public private(set) var openOrders: [UserOrder] = []
    private var userFillEvents: [UserFillEvent] = []

    // MARK: 리얼리즘 상태 (③)

    /// 최근 캔들 변동의 EMA — 변동성 군집의 기억.
    public private(set) var volatilityMomentum: Double = 0
    public private(set) var newsFeed: [NewsEvent] = []
    public var latestNews: NewsEvent? { newsFeed.last }
    private let newsFeedLimit = 20

    // MARK: 시나리오 상태 (M1-3)

    public private(set) var scenario: ScenarioPreset?
    /// 시나리오가 던진, 아직 응답되지 않은 결정 지점. UI가 관찰한다.
    public private(set) var pendingDecision: ScenarioPreset.DecisionPrompt?
    /// 시나리오 시작 시점의 에이전트 기본 파라미터 (구간이 끝나면 복원).
    private var baselineParams: [String: AgentParams] = [:]
    private var deliveredDecisionTicks: Set<Int> = []

    public init(seed: UInt64,
                initialPrice: Int = 52_300,
                config: EngineConfig = EngineConfig(),
                agents: [MarketAgent]? = nil,
                portfolio: Portfolio? = nil) {
        self.config = config
        self.lastPrice = initialPrice
        self.fairValue = Double(initialPrice)
        self.fairAnchor = Double(initialPrice)
        self.portfolio = portfolio ?? Portfolio(cash: config.initialCash)
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

    /// 시나리오 엔진: 프리셋의 시드·시작가로 만들어져 항상 같은 시장을 재현한다.
    public convenience init(scenario: ScenarioPreset,
                            config: EngineConfig = EngineConfig(),
                            agents: [MarketAgent]? = nil) {
        self.init(seed: scenario.seed, initialPrice: scenario.initialPrice,
                  config: config, agents: agents)
        self.scenario = scenario
        self.fairAnchor = scenario.anchorValue(at: 0)
        self.baselineParams = Dictionary(
            uniqueKeysWithValues: self.agents.map { ($0.id, $0.params) }
        )
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

    /// 1틱: (시나리오 훅) → fairValue 진화 → 에이전트 행동 → 체결 반영 → 분봉 마감 판정.
    public func step() {
        tick += 1
        applyScenarioIfActive()
        maybeFireNews()
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

        settleUserFills()

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
        // Box-Muller 가우시안 랜덤워크 + 앵커로의 평균회귀.
        // 시나리오 중에는 앵커 추종력을 프리셋 값으로 높여 경로를 따라가게 한다.
        let u1 = max(rng.double(in: 0...1), 1e-9)
        let u2 = rng.double(in: 0...1)
        let gaussian = (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        // 변동성 군집 (③): 방금까지 거칠던 시장은 계속 거칠다
        let clusteredVol = config.fairVolatility * (1 + volatilityMomentum * config.volClusterGain)
        let shock = gaussian * clusteredVol
        let pullStrength = scenario?.anchorPull ?? config.meanReversion
        let pull = (fairAnchor - fairValue) / fairValue * pullStrength
        fairValue *= exp(shock + pull)
        fairValue = max(fairValue, Double(config.tickSize))
    }

    /// 뉴스 이벤트 (③): 낮은 확률로 fairAnchor가 점프한다 — 갭과 급변의 근원.
    /// 시나리오 중에는 발동하지 않는다 (프리셋 경로 보호 + 결정론 유지).
    private func maybeFireNews() {
        guard scenario == nil, config.newsTickProbability > 0 else { return }
        guard rng.chance(config.newsTickProbability) else { return }
        let isPositive = rng.chance(0.5)
        let magnitude = rng.double(in: config.newsMagnitudeRange)
        fairAnchor *= isPositive ? (1 + magnitude) : (1 - magnitude)
        newsFeed.append(NewsEvent(tick: tick, isPositive: isPositive,
                                  magnitudePct: magnitude * 100,
                                  headlineIndex: rng.int(in: 0...9)))
        if newsFeed.count > newsFeedLimit {
            newsFeed.removeFirst(newsFeed.count - newsFeedLimit)
        }
    }

    // MARK: 시나리오 훅 (M1-3)

    /// 시나리오 종료 여부 (durationTicks 도달).
    public var isScenarioFinished: Bool {
        guard let scenario else { return false }
        return tick >= scenario.durationTicks
    }

    /// UI가 결정 지점에 응답했음을 알린다.
    public func resolveDecision() {
        pendingDecision = nil
    }

    private func applyScenarioIfActive() {
        guard let scenario, tick <= scenario.durationTicks else { return }

        // 1. fairValue 앵커가 키프레임 경로를 따라간다
        fairAnchor = scenario.anchorValue(at: tick)

        // 2. 에이전트 파라미터: 기본값에서 시작해 현재 틱에 걸린 오버라이드를 적용
        for agent in agents {
            var effective = baselineParams[agent.id] ?? agent.params
            for override in scenario.overrides
            where override.agentId == agent.id && override.contains(tick) {
                effective = override.params
            }
            agent.params = effective
        }

        // 3. 결정 지점 도달 → UI에 노출 (한 번만)
        for decision in scenario.decisions
        where tick >= decision.tick && !deliveredDecisionTicks.contains(decision.tick) {
            deliveredDecisionTicks.insert(decision.tick)
            pendingDecision = decision
        }
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
        // 변동성 군집: 이 캔들의 변동폭을 기억에 반영 (EMA)
        if currentCandle.open > 0 {
            let candleReturn = abs(log(Double(currentCandle.close) / Double(currentCandle.open)))
            volatilityMomentum = volatilityMomentum * 0.85 + candleReturn * 0.15
        }
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
            guard cost <= portfolio.availableCash else {
                throw OrderError.insufficientCash(needed: cost, available: portfolio.availableCash)
            }
        case .sell:
            guard qty <= portfolio.availableShares else {
                throw OrderError.insufficientHoldings(requested: qty, held: portfolio.availableShares)
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

    // MARK: 사용자 주문 (지정가 — ① 미체결 관리)

    public struct UserOrder: Identifiable, Equatable {
        public let id: UInt64
        public let side: Side
        public let price: Int
        public let restingQty: Int
        public var filledQty: Int = 0
        public var remainingQty: Int { restingQty - filledQty }
    }

    /// 대기 주문이 나중에 체결됐을 때 UI로 흘러가는 이벤트.
    public struct UserFillEvent: Equatable {
        public let orderId: UInt64
        public let side: Side
        public let price: Int
        public let qty: Int
        /// 정산 직전의 평단 — 매도 확정 수익률 계산용.
        public let avgCostBefore: Double
    }

    public struct LimitOrderResult {
        /// 접수 즉시 교차 체결된 부분 (시장가처럼)
        public let immediateFill: FillResult?
        /// 호가창에 앉은 대기 주문 (전량 즉시 체결이면 nil)
        public let restingOrder: UserOrder?
    }

    /// 지정가 주문. 교차분은 즉시 체결, 잔여는 호가창에 앉아 기다린다.
    /// 매수는 잔여 × 지정가만큼 현금을, 매도는 잔여 주식을 예약한다.
    public func placeLimitOrder(side: Side, price: Int, qty: Int) throws -> LimitOrderResult {
        guard qty > 0, price > 0 else { throw OrderError.invalidQuantity }
        let displayed = displayedPrice(for: side) ?? price

        // 즉시 교차분 비용 미리 계산 (지정가 이하/이상만 먹는다)
        let crossable = book.previewMarket(side: side, qty: qty)
            .filter { side == .buy ? $0.price <= price : $0.price >= price }
        let immediateQty = crossable.reduce(0) { $0 + $1.qty }
        let immediateCost = crossable.reduce(0) { $0 + $1.price * $1.qty }
        let restingQty = qty - immediateQty

        switch side {
        case .buy:
            let needed = immediateCost + restingQty * price
            guard needed <= portfolio.availableCash else {
                throw OrderError.insufficientCash(needed: needed, available: portfolio.availableCash)
            }
        case .sell:
            guard qty <= portfolio.availableShares else {
                throw OrderError.insufficientHoldings(requested: qty, held: portfolio.availableShares)
            }
        }

        let (trades, restingId, actualResting) = book.submitLimitTracked(
            agentId: Self.userAgentId, side: side, price: price, qty: qty, tick: tick)
        record(trades)

        var immediate: FillResult?
        if !trades.isEmpty {
            let fills = trades.map { Fill(price: $0.price, qty: $0.qty) }
            let result = FillResult(side: side, requestedQty: qty - actualResting,
                                    fills: fills, displayedPrice: displayed)
            switch side {
            case .buy: portfolio.applyBuy(result)
            case .sell: portfolio.applySell(result)
            }
            immediate = result
        }

        var resting: UserOrder?
        if let restingId, actualResting > 0 {
            switch side {
            case .buy: portfolio.reserveCash(actualResting * price)
            case .sell: portfolio.reserveShares(actualResting)
            }
            let order = UserOrder(id: restingId, side: side, price: price, restingQty: actualResting)
            openOrders.append(order)
            resting = order
        }
        return LimitOrderResult(immediateFill: immediate, restingOrder: resting)
    }

    /// 대기 주문 취소 — 예약 자금·주식을 돌려준다.
    public func cancelOrder(id: UInt64) {
        guard let index = openOrders.firstIndex(where: { $0.id == id }) else { return }
        let order = openOrders[index]
        let released = book.cancel(orderId: id, side: order.side, price: order.price)
        switch order.side {
        case .buy: portfolio.releaseCash(released * order.price)
        case .sell: portfolio.releaseShares(released)
        }
        openOrders.remove(at: index)
    }

    /// UI가 대기 체결 이벤트를 소비한다 (기록·알림용).
    public func drainUserFillEvents() -> [UserFillEvent] {
        let events = userFillEvents
        userFillEvents.removeAll()
        return events
    }

    /// 매 틱 끝에 호출: 대기 주문의 잔량 변화를 감지해 포트폴리오를 정산한다.
    private func settleUserFills() {
        guard !openOrders.isEmpty else { return }
        var stillOpen: [UserOrder] = []
        for var order in openOrders {
            let remaining = book.remainingQty(orderId: order.id, side: order.side, price: order.price)
            let newlyFilled = order.remainingQty - remaining
            if newlyFilled > 0 {
                let avgCostBefore = portfolio.avgCost
                switch order.side {
                case .buy: portfolio.settleRestingBuy(price: order.price, qty: newlyFilled)
                case .sell: portfolio.settleRestingSell(price: order.price, qty: newlyFilled)
                }
                order.filledQty += newlyFilled
                userFillEvents.append(UserFillEvent(
                    orderId: order.id, side: order.side, price: order.price,
                    qty: newlyFilled, avgCostBefore: avgCostBefore))
            }
            if remaining > 0 { stillOpen.append(order) }
        }
        openOrders = stillOpen
    }

    /// 리플레이 폴백: 과거 지정가 체결을 호가창 개입 없이 포트폴리오에만 반영한다.
    /// (대기 체결은 정산 틱이 기록되지 않으므로 완전 재현 대신 근사 복원을 택한다.)
    public func restoreFill(side: Side, price: Int, qty: Int) {
        let result = FillResult(side: side, requestedQty: qty,
                                fills: [Fill(price: price, qty: qty)], displayedPrice: price)
        switch side {
        case .buy: portfolio.applyBuy(result)
        case .sell: portfolio.applySell(result)
        }
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
