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

    /// 캔들이 하나 마감될 때마다 호출. 규칙에 따라 행동과 그 이유를 돌려준다.
    /// 이유는 봇 매매 일지에 그대로 실린다 — 규칙이 추상이 아니라 행동이 되도록.
    /// - Parameter candles: 방금 마감된 캔들을 포함한 전체 이력
    /// - Parameter avgCost: 현재 평단 (포지션 없으면 0)
    public mutating func onCandleClose(candles: [Candle], avgCost: Double) -> (action: Action, reason: String)? {
        guard let closed = candles.last else { return nil }
        // 채널은 '직전까지'의 캔들로 계산한다 — 자기 자신 돌파 방지
        let history = Array(candles.dropLast())
        guard let atr = history.atr(period: atrPeriod) else { return nil }

        if units == 0 {
            guard let channelHigh = history.highestHigh(period: entryLookback) else { return nil }
            if closed.close > channelHigh {
                units = 1
                lastEntryPrice = Double(closed.close)
                return (.buyUnit(qty: unitQty),
                        "최근 \(entryLookback)캔들 최고가 \(channelHigh.formatted())원 돌파 — 추세 시작 신호, 진입")
            }
            return nil
        }

        // 청산 1: 손절선 (평단 − 2N)
        let stopLine = avgCost - stopATRMultiple * atr
        if Double(closed.close) < stopLine {
            let qty = units * unitQty
            units = 0
            lastEntryPrice = 0
            return (.sellAll(qty: qty),
                    "손절선 \(Int(stopLine).formatted())원(평단−\(stopATRMultiple.formatted())×변동폭) 이탈 — 작게 지고 나온다")
        }
        // 청산 2: 채널 하단 이탈
        if let channelLow = history.lowestLow(period: exitLookback),
           closed.close < channelLow {
            let qty = units * unitQty
            units = 0
            lastEntryPrice = 0
            return (.sellAll(qty: qty),
                    "최근 \(exitLookback)캔들 최저가 \(channelLow.formatted())원 이탈 — 추세 종료로 판단, 전량 청산")
        }
        // 피라미딩: 0.5N 유리하게 갈 때마다 +1유닛
        if units < maxUnits,
           Double(closed.close) > lastEntryPrice + addATRMultiple * atr {
            units += 1
            lastEntryPrice = Double(closed.close)
            return (.buyUnit(qty: unitQty),
                    "진입 후 \(addATRMultiple.formatted())×변동폭만큼 유리 — 이기는 포지션에 1유닛 추가 (\(units)/\(maxUnits))")
        }
        return nil
    }
}

// MARK: - 나 vs 봇 하니스 (§15.2 BotComparison)

/// 봇의 매매 한 건 — 언제, 얼마에, 왜.
public struct BotAction {
    public let candleIndex: Int
    public let price: Double
    public let side: Side
    /// 이 매매를 한 규칙적 이유 (매매 일지에 표시)
    public let reason: String
}

public struct BotRun {
    public let botName: String
    public let candles: [Candle]
    /// 캔들별 평가액 — 수익 곡선
    public let equityCurve: [Int]
    public let finalEquity: Int
    public let startCash: Int
    public let tradeCount: Int
    public let maxDrawdownPct: Double
    /// 매매 타임라인 (매매 지도 + 매매 일지)
    public let actions: [BotAction]

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
        if strategy == nil {
            // 유닛을 가격에 맞춤 — 비싼 장에서 매수가 조용히 실패하지 않게 (4유닛까지 현금 내)
            turtle.unitQty = max(1, 2_300_000 / max(scenario.initialPrice, 1))
        }
        return runCustom(name: "터틀 봇", scenario: scenario) { ctx in
            turtle.onCandleClose(candles: ctx.candles, avgCost: ctx.avgCost)
        }
    }

    /// 가치투자 거장 봇 (§15) — fairValue 대비 싸면 사서 버티고, 비싸지면 판다.
    /// 추세추종(터틀)과 정반대 철학: 남들이 던질 때 줍고, 열광할 때 판다.
    /// 압축 시나리오는 실측 시장보다 fairValue를 바짝 따라가므로 안전마진을 작게 잡는다.
    /// 핵심: 순간 fairValue가 아니라 그 장기 EMA(intrinsic)를 기준으로 쓴다. 가격이 버블로
    /// 치솟으면 fairValue도 따라 오르지만, 추정치는 천천히 움직여 "지금은 비싸다"를 알아본다.
    /// 이것이 가치투자가 거품에 휩쓸리지 않는 이유를 재현한다.
    public static func runValue(scenario: ScenarioPreset,
                                marginOfSafety: Double = 0.035,
                                premium: Double = 0.04,
                                emaAlpha: Double = 0.06,
                                unitQty: Int? = nil) -> BotRun {
        var intrinsic: Double = 0
        return runCustom(name: "가치투자 봇", scenario: scenario) { ctx in
            intrinsic = intrinsic == 0 ? ctx.fairValue
                : intrinsic * (1 - emaAlpha) + ctx.fairValue * emaAlpha
            let price = Double(ctx.lastPrice)
            let gapPct = (price / intrinsic - 1) * 100
            if ctx.holdingQty == 0 {
                // 내재가치 추정보다 안전마진만큼 쌀 때만 산다
                guard price <= intrinsic * (1 - marginOfSafety) else { return nil }
                let qty = unitQty ?? max(1, 8_500_000 / max(ctx.lastPrice, 1))
                return (.buyUnit(qty: qty),
                        "내 가치 추정 \(Int(intrinsic).formatted())원보다 \(abs(gapPct).formatted(.number.precision(.fractionLength(1))))% 싸다 — 안전마진 확보, 매수")
            } else {
                // 내재가치 추정보다 프리미엄만큼 비싸지면 전량 매도
                guard price >= intrinsic * (1 + premium) else { return nil }
                return (.sellAll(qty: ctx.holdingQty),
                        "내 가치 추정보다 \(gapPct.formatted(.number.precision(.fractionLength(1))))% 비싸다 — 열광에 판다, 전량 매도")
            }
        }
    }

    /// 오닐 봇 (모멘텀) — 신고가 돌파 + 거래량 확인 매수, -8% 칼손절.
    /// "손실은 -8%에서 무조건 자른다"는 오닐의 철칙이 핵심 교육 포인트.
    public static func runONeil(scenario: ScenarioPreset,
                                lookback: Int = 7,
                                stopPct: Double = 0.08,
                                unitQty: Int? = nil) -> BotRun {
        var entryPrice: Double = 0
        return runCustom(name: "오닐 봇", scenario: scenario) { ctx in
            guard let closed = ctx.candles.last else { return nil }
            let history = Array(ctx.candles.dropLast())

            if ctx.holdingQty == 0 {
                guard let channelHigh = history.highestHigh(period: lookback),
                      closed.close > channelHigh else { return nil }
                // 거래량 확인: 돌파가 진짜인지 — 최근 평균의 1.3배 이상
                let recent = history.suffix(8)
                let avgVolume = recent.isEmpty ? 0
                    : recent.map(\.volume).reduce(0, +) / recent.count
                guard avgVolume > 0, closed.volume * 10 >= avgVolume * 13 else { return nil }
                entryPrice = Double(closed.close)
                let qty = unitQty ?? max(1, 8_000_000 / max(closed.close, 1))
                return (.buyUnit(qty: qty),
                        "신고가 \(channelHigh.formatted())원 돌파 + 거래량 평소의 \((Double(closed.volume) / Double(avgVolume)).formatted(.number.precision(.fractionLength(1))))배 — 수요가 진짜다, 매수")
            }

            // 철칙: -8% 무조건 손절
            if Double(closed.close) <= entryPrice * (1 - stopPct) {
                return (.sellAll(qty: ctx.holdingQty),
                        "매수가 대비 -\(Int(stopPct * 100))% — 오닐의 철칙, 이유를 묻지 않고 손절")
            }
            // 이익 보전: 단기 추세 꺾임
            if QuantCondition.deadCross(short: 3, long: 8).isMet(candles: ctx.candles) {
                return (.sellAll(qty: ctx.holdingQty),
                        "단기 이평선이 꺾였다 — 추세 종료, 이익을 지키고 나온다")
            }
            return nil
        }
    }

    /// 코스톨라니 봇 (소신파) — 초반에 사서 끝까지 잔다.
    /// 매매 일지가 한 줄뿐인 것 자체가 교훈: 시장의 소음을 무시하는 힘.
    public static func runKostolany(scenario: ScenarioPreset,
                                    unitQty: Int? = nil) -> BotRun {
        runCustom(name: "코스톨라니 봇", scenario: scenario) { ctx in
            guard ctx.holdingQty == 0, ctx.candles.count >= 1, ctx.candles.count <= 3 else { return nil }
            let qty = unitQty ?? max(1, 9_400_000 / max(ctx.lastPrice, 1))
            return (.buyUnit(qty: qty),
                    "우량한 것을 사서, 수면제를 먹고, 잔다 — 흔들림은 계획에 없다")
        }
    }

    /// 템플턴 봇 (역발상) — 비관이 최고조일 때 사서, 낙관이 돌아오면 판다.
    /// 급락장에서 진가, 꾸준한 상승장에선 살 기회 자체가 없다.
    public static func runTempleton(scenario: ScenarioPreset,
                                    panicDrawdownPct: Double = 8,
                                    calmDrawdownPct: Double = 2,
                                    lookback: Int = 15,
                                    unitQty: Int? = nil) -> BotRun {
        runCustom(name: "템플턴 봇", scenario: scenario) { ctx in
            guard let closed = ctx.candles.last, ctx.candles.count > 3 else { return nil }
            let window = min(ctx.candles.count, lookback)
            guard let recentHigh = ctx.candles.highestHigh(period: window),
                  recentHigh > 0 else { return nil }
            let drawdown = (1 - Double(closed.close) / Double(recentHigh)) * 100

            if ctx.holdingQty == 0 {
                guard drawdown >= panicDrawdownPct else { return nil }
                let qty = unitQty ?? max(1, 8_500_000 / max(ctx.lastPrice, 1))
                return (.buyUnit(qty: qty),
                        "고점 대비 -\(drawdown.formatted(.number.precision(.fractionLength(1))))% — 비관이 최고조일 때가 사는 날이다")
            }
            guard drawdown <= calmDrawdownPct else { return nil }
            return (.sellAll(qty: ctx.holdingQty),
                    "비관이 걷히고 낙관이 돌아왔다 — 남들이 살 때 판다")
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
