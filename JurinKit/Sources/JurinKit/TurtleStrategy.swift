import Foundation

// MARK: - 롤링 지표 (§15.2 선행 작업 — 돈치안 채널 · ATR)

public extension Array where Element == Candle {

    /// 최근 N캔들 최고가 (돈치안 상단)
    func highestHigh(period: Int) -> Int? {
        guard count >= period, period > 0 else { return nil }
        return suffix(period).map(\.high).max()
    }

    /// 최근 N캔들 최저가 (돈치안 하단)
    func lowestLow(period: Int) -> Int? {
        guard count >= period, period > 0 else { return nil }
        return suffix(period).map(\.low).min()
    }

    /// 평균 변동폭 (터틀의 "N") — TR의 단순 평균.
    func atr(period: Int) -> Double? {
        guard count >= period + 1, period > 0 else { return nil }
        let window = Array(suffix(period + 1))
        var trueRanges: [Double] = []
        for i in 1..<window.count {
            let candle = window[i]
            let prevClose = window[i - 1].close
            let tr = Swift.max(
                Double(candle.high - candle.low),
                Double(abs(candle.high - prevClose)),
                Double(abs(candle.low - prevClose))
            )
            trueRanges.append(tr)
        }
        return trueRanges.reduce(0, +) / Double(trueRanges.count)
    }
}

// MARK: - 터틀 전략 (§15.2 — 추세추종 / horizon = 단기)

/// 규칙이 전부인 전략. 감정이 없고, 돌파에 사고, 채널 하단·손절선에 판다.
public struct TurtleStrategy {
    public var entryLookback: Int
    public var exitLookback: Int
    public var atrPeriod: Int
    public var maxUnits: Int
    public var unitQty: Int
    /// 손절: 평단 − stopATRMultiple × ATR
    public var stopATRMultiple: Double
    /// 피라미딩: 마지막 진입가 + addATRMultiple × ATR 위에서 1유닛 추가
    public var addATRMultiple: Double

    public private(set) var units: Int = 0
    public private(set) var lastEntryPrice: Double = 0

    public init(entryLookback: Int = 20, exitLookback: Int = 10, atrPeriod: Int = 14,
                maxUnits: Int = 4, unitQty: Int = 60,
                stopATRMultiple: Double = 2.0, addATRMultiple: Double = 0.5) {
        self.entryLookback = entryLookback
        self.exitLookback = exitLookback
        self.atrPeriod = atrPeriod
        self.maxUnits = maxUnits
        self.unitQty = unitQty
        self.stopATRMultiple = stopATRMultiple
        self.addATRMultiple = addATRMultiple
    }

    public enum Action: Equatable {
        case buyUnit(qty: Int)
        case sellAll(qty: Int)
    }

    /// 캔들이 하나 마감될 때마다 호출. 규칙에 따라 행동을 돌려준다.
    /// - Parameter candles: 방금 마감된 캔들을 포함한 전체 이력
    /// - Parameter avgCost: 현재 평단 (포지션 없으면 0)
    public mutating func onCandleClose(candles: [Candle], avgCost: Double) -> Action? {
        guard let closed = candles.last else { return nil }
        // 채널은 '직전까지'의 캔들로 계산한다 — 자기 자신 돌파 방지
        let history = Array(candles.dropLast())
        guard let atr = history.atr(period: atrPeriod) else { return nil }

        if units == 0 {
            guard let channelHigh = history.highestHigh(period: entryLookback) else { return nil }
            if closed.close > channelHigh {
                units = 1
                lastEntryPrice = Double(closed.close)
                return .buyUnit(qty: unitQty)
            }
            return nil
        }

        // 청산 1: 손절선 (평단 − 2N)
        if Double(closed.close) < avgCost - stopATRMultiple * atr {
            let qty = units * unitQty
            units = 0
            lastEntryPrice = 0
            return .sellAll(qty: qty)
        }
        // 청산 2: 채널 하단 이탈
        if let channelLow = history.lowestLow(period: exitLookback),
           closed.close < channelLow {
            let qty = units * unitQty
            units = 0
            lastEntryPrice = 0
            return .sellAll(qty: qty)
        }
        // 피라미딩: 0.5N 유리하게 갈 때마다 +1유닛
        if units < maxUnits,
           Double(closed.close) > lastEntryPrice + addATRMultiple * atr {
            units += 1
            lastEntryPrice = Double(closed.close)
            return .buyUnit(qty: unitQty)
        }
        return nil
    }
}

// MARK: - 나 vs 봇 하니스 (§15.2 BotComparison)

public struct BotRun {
    public let botName: String
    public let candles: [Candle]
    /// 캔들별 평가액 — 수익 곡선
    public let equityCurve: [Int]
    public let finalEquity: Int
    public let startCash: Int
    public let tradeCount: Int
    public let maxDrawdownPct: Double
    /// 매매 타임라인 (매매 지도에 그대로 얹는다)
    public let actions: [(candleIndex: Int, price: Double, side: Side)]

    public var returnPct: Double {
        Double(finalEquity - startCash) / Double(startCash) * 100
    }
}

public enum BotComparison {

    /// 압축 시나리오(30캔들 안팎)에 맞게 스케일한 터틀 파라미터.
    /// 클래식 20/10/14는 수백 캔들의 실측 시장용 — 압축 시장에선 채널이 형성되기 전에 장이 끝난다.
    public static var scenarioTurtle: TurtleStrategy {
        TurtleStrategy(entryLookback: 5, exitLookback: 3, atrPeriod: 4)
    }

    /// 같은 시나리오(같은 시드)에서 터틀 봇을 자동 매매시킨다.
    /// 봇도 사용자와 같은 주문 API를 쓴다 — 같은 조건, 같은 슬리피지.
    public static func runTurtle(scenario: ScenarioPreset,
                                 strategy: TurtleStrategy? = nil) -> BotRun {
        var turtle = strategy ?? scenarioTurtle
        return runCustom(name: "터틀 봇", scenario: scenario) { candles, avgCost, _ in
            turtle.onCandleClose(candles: candles, avgCost: avgCost)
        }
    }

    /// 최대 낙폭(MDD) — 고점 대비 최대 하락률(%).
    static func maxDrawdown(of curve: [Int]) -> Double {
        var peak = curve.first ?? 1
        var worst = 0.0
        for value in curve {
            peak = max(peak, value)
            let drawdown = Double(peak - value) / Double(peak) * 100
            worst = max(worst, drawdown)
        }
        return worst
    }
}
