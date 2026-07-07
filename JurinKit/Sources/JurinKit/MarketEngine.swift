import Foundation
import Observation

// MARK: - 주문 오류

public enum OrderError: Error, Equatable {
    case insufficientCash(needed: Int, available: Int)
    case insufficientHoldings(requested: Int, held: Int)
    case noLiquidity
    case invalidQuantity
    /// 상·하한가 밖의 지정가 (제도 팩)
    case priceOutOfBand(lower: Int, upper: Int)
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

    // MARK: 시장 제도 (제도 팩)

    /// 매수·매도 공통 위탁 수수료율
    public var commissionRate: Double
    /// 매도 시 거래세율 (수수료와 별도)
    public var sellTaxRate: Double
    /// 거래일 = 이 캔들 수. 경계에서 기준가 갱신·시가 갭·봇 호가 리셋.
    public var candlesPerDay: Int
    /// 상·하한가 폭 (기준가 대비 비율). 0이면 비활성 (크립토 등).
    public var priceBandRate: Double
    /// 거래일 시작 시 fairAnchor에 적용되는 시가 갭 범위 (시나리오 중 비활성)
    public var openingGapRange: ClosedRange<Double>
    /// KRX 가격대별 호가단위 사용 여부. false면 tickSize 고정.
    public var usesKRXTickSize: Bool
    /// 시장 기후(공통 팩터)에 대한 민감도. 1이면 시장과 같이, 0이면 무관하게 움직인다.
    public var marketBeta: Double

    public init(tickSize: Int = 50,
                ticksPerCandle: Int = 20,
                fairVolatility: Double = 0.0009,
                meanReversion: Double = 0.002,
                initialCash: Int = 10_000_000,
                volClusterGain: Double = 40,
                newsTickProbability: Double = 1.0 / 900,
                newsMagnitudeRange: ClosedRange<Double> = 0.02...0.07,
                commissionRate: Double = 0.00015,
                sellTaxRate: Double = 0.0018,
                candlesPerDay: Int = 20,
                priceBandRate: Double = 0.30,
                openingGapRange: ClosedRange<Double> = -0.02...0.02,
                usesKRXTickSize: Bool = true,
                marketBeta: Double = 1.0) {
        self.tickSize = tickSize
        self.ticksPerCandle = ticksPerCandle
        self.fairVolatility = fairVolatility
        self.meanReversion = meanReversion
        self.initialCash = initialCash
        self.volClusterGain = volClusterGain
        self.newsTickProbability = newsTickProbability
        self.newsMagnitudeRange = newsMagnitudeRange
        self.commissionRate = commissionRate
        self.sellTaxRate = sellTaxRate
        self.candlesPerDay = candlesPerDay
        self.priceBandRate = priceBandRate
        self.openingGapRange = openingGapRange
        self.usesKRXTickSize = usesKRXTickSize
        self.marketBeta = marketBeta
    }

    // MARK: 수수료·호가단위 계산

    public func buyFee(on notional: Int) -> Int {
        Int((Double(notional) * commissionRate).rounded())
    }

    public func sellFee(on notional: Int) -> Int {
        Int((Double(notional) * (commissionRate + sellTaxRate)).rounded())
    }

    /// KRX 가격대별 호가단위 (2023 개편 기준).
    public static func krxTickSize(for price: Int) -> Int {
        switch price {
        case ..<2_000: return 1
        case ..<5_000: return 5
        case ..<20_000: return 10
        case ..<50_000: return 50
        case ..<200_000: return 100
        case ..<500_000: return 250
        default: return 1_000
        }
    }

    public func tickSize(at price: Int) -> Int {
        usesKRXTickSize ? Self.krxTickSize(for: price) : tickSize
    }
}

/// 뉴스 이벤트 (③) — fairAnchor를 점프시켜 갭·급변을 만든다.
/// 헤드라인 문구는 앱이 headlineIndex로 매핑한다 (코어는 카피를 모른다).
public struct NewsEvent: Equatable {
    public let tick: Int
    public let isPositive: Bool
    public let magnitudePct: Double
    public let headlineIndex: Int
    /// 시장 전체 뉴스(거시 이벤트) 여부 — 전 종목이 같은 틱에 함께 받는다.
    public var isMarketWide: Bool = false
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
    /// 이 시장의 종목 코드 (다종목: 공유 원장의 보유 키)
    public let symbol: String
    /// 계좌 원장 — 여러 엔진이 공유할 수 있다 (현금은 하나)
    public let ledger: AccountLedger
    /// 시장 기후 (공통 팩터) — 같은 기후를 공유하는 종목들은 상관되어 움직인다.
    public let climate: MarketClimate?
    /// 이 종목 관점의 계좌 스냅샷 (기존 API 호환)
    public var portfolio: PortfolioSnapshot { ledger.snapshot(for: symbol) }

    private var agents: [MarketAgent]
    private var rng: SeededRNG
    private let tapeLimit = 60
    public static let userAgentId = "USER"

    // MARK: 사용자 지정가 상태 (①)

    public private(set) var openOrders: [UserOrder] = []
    private var userFillEvents: [UserFillEvent] = []

    // MARK: 거래일·가격제한 상태 (제도 팩)

    public private(set) var tradingDay: Int = 1
    /// 기준가 (전일 종가) — 상·하한가의 기준.
    public private(set) var referencePrice: Int

    public var hasPriceBand: Bool { config.priceBandRate > 0 }

    public var upperLimitPrice: Int {
        guard hasPriceBand else { return Int.max }
        let raw = Int(Double(referencePrice) * (1 + config.priceBandRate))
        let tick = config.tickSize(at: raw)
        return raw / tick * tick
    }

    public var lowerLimitPrice: Int {
        guard hasPriceBand else { return config.tickSize }
        let raw = Int(Double(referencePrice) * (1 - config.priceBandRate))
        let tick = config.tickSize(at: raw)
        return (raw + tick - 1) / tick * tick
    }

    private func clampToBand(_ price: Int) -> Int {
        guard hasPriceBand else { return price }
        return min(max(price, lowerLimitPrice), upperLimitPrice)
    }

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
                symbol: String = "MAIN",
                ledger: AccountLedger? = nil,
                climate: MarketClimate? = nil) {
        self.config = config
        self.lastPrice = initialPrice
        self.referencePrice = initialPrice
        self.fairValue = Double(initialPrice)
        self.fairAnchor = Double(initialPrice)
        self.symbol = symbol
        self.ledger = ledger ?? AccountLedger(cash: config.initialCash)
        self.climate = climate
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

    /// 시작·장 개시 시 빈 호가창을 마켓메이커 스타일로 채워 첫 주문부터 체결이 가능하게 한다.
    private func seedInitialBook() {
        let tick = config.tickSize(at: lastPrice)
        for level in 1...5 {
            let offset = level * tick
            book.submitLimit(agentId: "SEED", side: .buy,
                             price: clampToBand(lastPrice - offset), qty: 150 + level * 30, tick: 0)
            book.submitLimit(agentId: "SEED", side: .sell,
                             price: clampToBand(lastPrice + offset), qty: 150 + level * 30, tick: 0)
        }
    }

    /// 거래일 경계 (제도 팩): 기준가 갱신 → 시가 갭 → 봇 호가 리셋 (동시호가 근사).
    /// 사용자의 대기 주문은 실제 시장의 GTC처럼 살아남는다.
    private func startNewTradingDay() {
        tradingDay += 1
        referencePrice = lastPrice
        if scenario == nil {
            fairAnchor *= (1 + rng.double(in: config.openingGapRange))
        }
        book.cancelAllExcept(agentId: Self.userAgentId)
        seedInitialBook()
    }

    // MARK: 틱 루프

    /// 1틱: (시나리오 훅) → fairValue 진화 → 에이전트 행동 → 체결 반영 → 분봉 마감 판정.
    public func step() {
        tick += 1
        applyScenarioIfActive()
        applyMarketClimateNews()
        maybeFireNews()
        evolveFairValue()

        let ctx = MarketContext(tick: tick, lastPrice: lastPrice, fairValue: fairValue,
                                bestBid: book.bestBid, bestAsk: book.bestAsk,
                                candles: candles, tickSize: config.tickSize(at: lastPrice))

        for agent in agents.shuffled(using: &rng) {
            if agent.refreshesQuotes { book.cancelAll(agentId: agent.id) }
            for intent in agent.act(ctx, rng: &rng) {
                apply(intent, from: agent.id)
            }
        }

        settleUserFills()

        if tick % config.ticksPerCandle == 0 {
            closeCandle()
            if config.candlesPerDay > 0 && candles.count % config.candlesPerDay == 0 {
                startNewTradingDay()
            }
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
        // 시장 기후 (상관관계): 같은 틱의 시장 충격을 β만큼 함께 받는다.
        // 시나리오는 자기 경로가 곧 세계라 기후를 받지 않는다.
        let marketShock = scenario == nil
            ? (climate?.shock(at: tick) ?? 0) * config.marketBeta
            : 0
        let pullStrength = scenario?.anchorPull ?? config.meanReversion
        let pull = (fairAnchor - fairValue) / fairValue * pullStrength
        fairValue *= exp(shock + marketShock + pull)
        fairValue = max(fairValue, Double(config.tickSize))
    }

    /// 시장 전체 뉴스 (상관관계): 기후가 터뜨리면 모든 종목이 같은 틱에 β만큼 받는다.
    private func applyMarketClimateNews() {
        guard scenario == nil, let climate,
              let event = climate.news(at: tick) else { return }
        let scaled = event.magnitude * config.marketBeta
        fairAnchor *= event.isPositive ? (1 + scaled) : (1 - scaled)
        newsFeed.append(NewsEvent(tick: tick, isPositive: event.isPositive,
                                  magnitudePct: scaled * 100,
                                  headlineIndex: event.headlineIndex,
                                  isMarketWide: true))
        if newsFeed.count > newsFeedLimit {
            newsFeed.removeFirst(newsFeed.count - newsFeedLimit)
        }
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
            // 봇 호가는 상·하한가 안으로 클램프 — 호가창의 모든 가격이 밴드 안에 있게 된다
            trades = book.submitLimit(agentId: agentId, side: intent.side,
                                      price: clampToBand(price), qty: qty, tick: tick)
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
            let needed = cost + config.buyFee(on: cost)
            guard needed <= ledger.availableCash else {
                throw OrderError.insufficientCash(needed: needed, available: ledger.availableCash)
            }
        case .sell:
            guard qty <= ledger.availableShares(of: symbol) else {
                throw OrderError.insufficientHoldings(requested: qty, held: ledger.availableShares(of: symbol))
            }
        }

        let (fills, trades) = book.executeMarket(agentId: Self.userAgentId, side: side, qty: qty, tick: tick)
        record(trades)

        let result = FillResult(side: side, requestedQty: qty, fills: fills, displayedPrice: displayed)
        switch side {
        case .buy: ledger.applyBuy(symbol: symbol, result, fee: config.buyFee(on: result.notional))
        case .sell: ledger.applySell(symbol: symbol, result, fee: config.sellFee(on: result.notional))
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
        /// 매수 대기에 묶어둔 예약금 잔액 (수수료 포함) — 정산·취소 시 정확히 해제
        public var reservedCashLeft: Int = 0
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
        if hasPriceBand && (price > upperLimitPrice || price < lowerLimitPrice) {
            throw OrderError.priceOutOfBand(lower: lowerLimitPrice, upper: upperLimitPrice)
        }
        let displayed = displayedPrice(for: side) ?? price

        // 즉시 교차분 비용 미리 계산 (지정가 이하/이상만 먹는다)
        let crossable = book.previewMarket(side: side, qty: qty)
            .filter { side == .buy ? $0.price <= price : $0.price >= price }
        let immediateQty = crossable.reduce(0) { $0 + $1.qty }
        let immediateCost = crossable.reduce(0) { $0 + $1.price * $1.qty }
        let restingQty = qty - immediateQty
        let restingReserve = restingQty * price + config.buyFee(on: restingQty * price)

        switch side {
        case .buy:
            let needed = immediateCost + config.buyFee(on: immediateCost) + restingReserve
            guard needed <= ledger.availableCash else {
                throw OrderError.insufficientCash(needed: needed, available: ledger.availableCash)
            }
        case .sell:
            guard qty <= ledger.availableShares(of: symbol) else {
                throw OrderError.insufficientHoldings(requested: qty, held: ledger.availableShares(of: symbol))
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
            case .buy: ledger.applyBuy(symbol: symbol, result, fee: config.buyFee(on: result.notional))
            case .sell: ledger.applySell(symbol: symbol, result, fee: config.sellFee(on: result.notional))
            }
            immediate = result
        }

        var resting: UserOrder?
        if let restingId, actualResting > 0 {
            var order = UserOrder(id: restingId, side: side, price: price, restingQty: actualResting)
            switch side {
            case .buy:
                let reserve = actualResting * price + config.buyFee(on: actualResting * price)
                ledger.reserveCash(reserve)
                order.reservedCashLeft = reserve
            case .sell:
                ledger.reserveShares(symbol: symbol, actualResting)
            }
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
        case .buy: ledger.releaseCash(order.reservedCashLeft)
        case .sell: ledger.releaseShares(symbol: symbol, released)
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
                let avgCostBefore = ledger.avgCost(of: symbol)
                switch order.side {
                case .buy:
                    let cost = order.price * newlyFilled
                    let fee = config.buyFee(on: cost)
                    ledger.settleRestingBuy(symbol: symbol, price: order.price, qty: newlyFilled, fee: fee)
                    order.reservedCashLeft = max(order.reservedCashLeft - cost - fee, 0)
                case .sell:
                    let fee = config.sellFee(on: order.price * newlyFilled)
                    ledger.settleRestingSell(symbol: symbol, price: order.price, qty: newlyFilled, fee: fee)
                }
                order.filledQty += newlyFilled
                userFillEvents.append(UserFillEvent(
                    orderId: order.id, side: order.side, price: order.price,
                    qty: newlyFilled, avgCostBefore: avgCostBefore))
            }
            if remaining > 0 {
                stillOpen.append(order)
            } else if order.side == .buy && order.reservedCashLeft > 0 {
                // 부분 체결 수수료 반올림 잔액 — 전량 체결 시 정확히 해제
                ledger.releaseCash(order.reservedCashLeft)
            }
        }
        openOrders = stillOpen
    }

    /// 리플레이 폴백: 과거 지정가 체결을 호가창 개입 없이 포트폴리오에만 반영한다.
    /// (대기 체결은 정산 틱이 기록되지 않으므로 완전 재현 대신 근사 복원을 택한다.)
    public func restoreFill(side: Side, price: Int, qty: Int) {
        let result = FillResult(side: side, requestedQty: qty,
                                fills: [Fill(price: price, qty: qty)], displayedPrice: price)
        switch side {
        case .buy: ledger.applyBuy(symbol: symbol, result, fee: config.buyFee(on: result.notional))
        case .sell: ledger.applySell(symbol: symbol, result, fee: config.sellFee(on: result.notional))
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
