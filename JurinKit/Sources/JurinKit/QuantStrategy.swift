import Foundation

// MARK: - RSI (퀀트 빌더 지표)

public extension Array where Element == Candle {
    /// RSI — 최근 period 캔들의 상승/하락 비율. 데이터 부족이면 nil.
    func rsi(period: Int = 14) -> Double? {
        guard count >= period + 1, period > 0 else { return nil }
        let window = Array(suffix(period + 1))
        var gains = 0.0
        var losses = 0.0
        for i in 1..<window.count {
            let change = Double(window[i].close - window[i - 1].close)
            if change > 0 { gains += change } else { losses -= change }
        }
        guard losses > 0 else { return 100 }
        let rs = gains / losses
        return 100 - 100 / (1 + rs)
    }
}

// MARK: - 퀀트 규칙 (조건 → 행동)

/// 사용자가 조립하는 조건 블록. 출력은 §11.1 원칙에 따라
/// 백테스트 통계(수익률·MDD·매매 횟수)로만 표현된다 — 점 가격 예측은 없다.
public enum QuantCondition: Equatable {
    /// RSI가 임계 아래 (과매도 — 역추세 매수의 재료)
    case rsiBelow(threshold: Double, period: Int)
    /// RSI가 임계 위 (과매수)
    case rsiAbove(threshold: Double, period: Int)
    /// 단기 이평선이 장기 이평선을 상향 돌파 (골든크로스)
    case goldenCross(short: Int, long: Int)
    /// 하향 돌파 (데드크로스)
    case deadCross(short: Int, long: Int)
    /// 최근 N캔들 최고가 돌파
    case breakoutHigh(lookback: Int)
    /// 최근 N캔들 최저가 이탈
    case breakdownLow(lookback: Int)

    /// 방금 마감된 캔들 기준으로 조건 충족 여부.
    public func isMet(candles: [Candle]) -> Bool {
        guard let closed = candles.last else { return false }
        switch self {
        case .rsiBelow(let threshold, let period):
            guard let value = candles.rsi(period: period) else { return false }
            return value < threshold
        case .rsiAbove(let threshold, let period):
            guard let value = candles.rsi(period: period) else { return false }
            return value > threshold
        case .goldenCross(let short, let long):
            return Self.cross(candles: candles, short: short, long: long, upward: true)
        case .deadCross(let short, let long):
            return Self.cross(candles: candles, short: short, long: long, upward: false)
        case .breakoutHigh(let lookback):
            guard let high = Array(candles.dropLast()).highestHigh(period: lookback) else { return false }
            return closed.close > high
        case .breakdownLow(let lookback):
            guard let low = Array(candles.dropLast()).lowestLow(period: lookback) else { return false }
            return closed.close < low
        }
    }

    private static func cross(candles: [Candle], short: Int, long: Int, upward: Bool) -> Bool {
        let shortMA = candles.movingAverage(period: short)
        let longMA = candles.movingAverage(period: long)
        guard shortMA.count >= 2,
              let prevShort = shortMA[shortMA.count - 2], let nowShort = shortMA.last ?? nil,
              let prevLong = longMA[longMA.count - 2], let nowLong = longMA.last ?? nil
        else { return false }
        if upward {
            return prevShort <= prevLong && nowShort > nowLong
        } else {
            return prevShort >= prevLong && nowShort < nowLong
        }
    }
}

/// 진입·청산 한 쌍으로 이루어진 사용자 전략.
public struct QuantStrategy {
    public var name: String
    public var entry: QuantCondition
    public var exit: QuantCondition
    public var unitQty: Int

    public init(name: String, entry: QuantCondition, exit: QuantCondition, unitQty: Int = 100) {
        self.name = name
        self.entry = entry
        self.exit = exit
        self.unitQty = unitQty
    }
}

// MARK: - 전략 러너 (BotComparison 일반화)

public extension BotComparison {

    /// 사용자 전략을 시나리오에 백테스트. 봇과 같은 조건 — 같은 주문 API, 같은 슬리피지·수수료.
    static func run(strategy: QuantStrategy, scenario: ScenarioPreset) -> BotRun {
        runCustom(name: strategy.name, scenario: scenario) { candles, _, holdingQty in
            if holdingQty == 0 {
                return strategy.entry.isMet(candles: candles) ? .buyUnit(qty: strategy.unitQty) : nil
            } else {
                return strategy.exit.isMet(candles: candles) ? .sellAll(qty: holdingQty) : nil
            }
        }
    }

    /// 캔들 마감마다 결정 클로저를 호출하는 공용 하니스.
    static func runCustom(name: String,
                          scenario: ScenarioPreset,
                          decide: (_ candles: [Candle], _ avgCost: Double, _ holdingQty: Int) -> TurtleStrategy.Action?) -> BotRun {
        let engine = MarketEngine(scenario: scenario)
        var equityCurve: [Int] = []
        var actions: [(candleIndex: Int, price: Double, side: Side)] = []
        var lastCandleCount = 0

        while engine.tick < scenario.durationTicks {
            engine.step()
            if engine.pendingDecision != nil {
                engine.resolveDecision() // 봇은 규칙만 따른다
            }
            if engine.candles.count > lastCandleCount {
                lastCandleCount = engine.candles.count
                equityCurve.append(engine.portfolio.equity(at: engine.lastPrice))

                let action = decide(engine.candles, engine.portfolio.avgCost, engine.portfolio.qty)
                switch action {
                case .buyUnit(let qty):
                    if let fill = try? engine.placeMarketOrder(side: .buy, qty: qty) {
                        actions.append((engine.candles.count, fill.avgFillPrice, .buy))
                    }
                case .sellAll(let qty):
                    let sellable = min(qty, engine.portfolio.qty)
                    if sellable > 0,
                       let fill = try? engine.placeMarketOrder(side: .sell, qty: sellable) {
                        actions.append((engine.candles.count, fill.avgFillPrice, .sell))
                    }
                case nil:
                    break
                }
            }
        }

        let finalEquity = engine.portfolio.equity(at: engine.lastPrice)
        return BotRun(
            botName: name,
            candles: engine.candles,
            equityCurve: equityCurve,
            finalEquity: finalEquity,
            startCash: engine.config.initialCash,
            tradeCount: actions.count,
            maxDrawdownPct: maxDrawdown(of: equityCurve),
            actions: actions
        )
    }
}
