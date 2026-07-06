import Foundation
import Observation
import SwiftData
import JurinKit

/// 영속성의 단일 창구. 화면들은 SwiftData를 직접 만지지 않고 이 스토어를 통한다
/// (엔타이틀먼트 게이팅도 나중에 여기로 모인다 — §12.4의 결합도 원칙과 동일).
@Observable
@MainActor
final class SeedStore {
    static let schema = Schema([
        TradeLog.self, Season.self, LessonProgress.self, AppProgress.self
    ])

    private let context: ModelContext
    private(set) var currentSeason: Season
    private(set) var progress: AppProgress

    init(context: ModelContext) {
        self.context = context
        // 단일 레코드·활성 시즌은 없으면 만든다 — 첫 실행 부트스트랩.
        let seasons = (try? context.fetch(FetchDescriptor<Season>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.number, order: .reverse)]
        ))) ?? []
        if let active = seasons.first {
            currentSeason = active
        } else {
            let season = Season(number: 1, startCash: 10_000_000)
            context.insert(season)
            currentSeason = season
        }

        let allProgress = (try? context.fetch(FetchDescriptor<AppProgress>())) ?? []
        if let existing = allProgress.first {
            progress = existing
        } else {
            let fresh = AppProgress()
            context.insert(fresh)
            progress = fresh
        }
        try? context.save()
    }

    // MARK: 매매 기록 (M2-3 태그 시트가 호출)

    /// 체결 결과를 TradeLog로 영속화. 매도면 확정 수익률을 함께 계산한다.
    func record(fill: FillResult,
                tag: TradeReasonTag,
                symbol: String = "한빛전자",
                avgCostBeforeOrder: Double,
                note: String? = nil,
                scenarioId: String? = nil,
                atTick: Int? = nil,
                atCandleIndex: Int? = nil) {
        var realized: Double?
        if fill.side == .sell, avgCostBeforeOrder > 0 {
            realized = (fill.avgFillPrice - avgCostBeforeOrder) / avgCostBeforeOrder * 100
        }
        let isFirstTrade = tradeCount() == 0
        let log = TradeLog(
            side: fill.side,
            symbol: symbol,
            displayedPrice: fill.displayedPrice,
            qty: fill.filledQty,
            avgFillPrice: fill.avgFillPrice,
            slippage: fill.slippage,
            reasonTag: tag,
            note: note,
            scenarioId: scenarioId,
            seasonNumber: currentSeason.number,
            realizedReturnPct: realized
        )
        log.atTick = atTick
        log.atCandleIndex = atCandleIndex
        context.insert(log)
        try? context.save()

        Analytics.log(.tradePlaced, [
            "side": fill.side.rawValue,
            "tag": tag.rawValue,
            "scenario": scenarioId ?? "free"
        ])
        if isFirstTrade {
            Analytics.log(.firstTradeFilled, ["tag": tag.rawValue])
        }
    }

    // MARK: 시장 연속성 (시드 + 틱 + 주문 리플레이)

    func persistMarketState(seed: UInt64, tick: Int) {
        currentSeason.engineSeedBits = Int64(bitPattern: seed)
        currentSeason.lastTick = tick
        currentSeason.lastActiveAt = .now
        try? context.save()
    }

    func marketState() -> (seed: UInt64, tick: Int)? {
        guard let bits = currentSeason.engineSeedBits,
              let tick = currentSeason.lastTick else { return nil }
        return (UInt64(bitPattern: bits), tick)
    }

    var lastActiveAt: Date? { currentSeason.lastActiveAt }

    /// 리플레이 대상: 현재 시즌의 본 세션 매매 (시나리오 제외), 틱 순.
    func replayableLogs() -> [TradeLog] {
        seasonLogs()
            .filter { $0.scenarioId == nil && $0.atTick != nil }
            .sorted { ($0.atTick ?? 0) < ($1.atTick ?? 0) }
    }

    /// 매매 지도 마커 (M4 — 부록 A-4의 aha 모먼트).
    func tradeMarks() -> [(candleIndex: Int, price: Double, side: Side)] {
        replayableLogs().compactMap { log in
            guard let index = log.atCandleIndex else { return nil }
            return (index, log.avgFillPrice, log.side)
        }
    }

    // MARK: 포트폴리오 영속 (앱 재시작 복원)

    func persistPortfolio(_ portfolio: Portfolio) {
        currentSeason.savedCash = portfolio.cash
        currentSeason.savedQty = portfolio.qty
        currentSeason.savedAvgCost = portfolio.avgCost
        currentSeason.savedRealizedPnL = portfolio.realizedPnL
        try? context.save()
    }

    func restorePortfolio() -> Portfolio? {
        guard let cash = currentSeason.savedCash,
              let qty = currentSeason.savedQty,
              let avgCost = currentSeason.savedAvgCost else { return nil }
        return Portfolio(cash: cash, qty: qty, avgCost: avgCost,
                         realizedPnL: currentSeason.savedRealizedPnL ?? 0)
    }

    // MARK: L1 룰베이스 복기 집계 (M4-1)

    struct TagStat: Identifiable {
        let tag: TradeReasonTag
        let count: Int
        let winCount: Int
        let lossCount: Int
        let avgRealizedReturnPct: Double?
        var id: String { tag.rawValue }
    }

    /// 현재 시즌의 태그별 성적표 — "급등 추격 4건 · 평균 -3.2%"의 원료.
    func tagStats() -> [TagStat] {
        let seasonNumber = currentSeason.number
        let logs = (try? context.fetch(FetchDescriptor<TradeLog>(
            predicate: #Predicate { $0.seasonNumber == seasonNumber }
        ))) ?? []
        let grouped = Dictionary(grouping: logs) { $0.reasonTagRaw }
        return grouped.compactMap { raw, items in
            guard let tag = TradeReasonTag(rawValue: raw) else { return nil }
            let returns = items.compactMap(\.realizedReturnPct)
            let avg = returns.isEmpty ? nil : returns.reduce(0, +) / Double(returns.count)
            return TagStat(tag: tag,
                           count: items.count,
                           winCount: returns.filter { $0 > 0 }.count,
                           lossCount: returns.filter { $0 < 0 }.count,
                           avgRealizedReturnPct: avg)
        }
        .sorted { $0.count > $1.count }
    }

    /// 승률: 확정(매도) 매매 중 수익 비율. 확정이 없으면 nil.
    func winRate() -> Double? {
        let stats = tagStats()
        let wins = stats.reduce(0) { $0 + $1.winCount }
        let losses = stats.reduce(0) { $0 + $1.lossCount }
        guard wins + losses > 0 else { return nil }
        return Double(wins) / Double(wins + losses) * 100
    }

    /// 매매 직후 미니 복기 한 줄 (M4-4). 데이터가 쌓이기 전엔 안내 문구.
    func miniReview(for tag: TradeReasonTag) -> String {
        guard let stat = tagStats().first(where: { $0.tag == tag }) else {
            return "기록했어요. 결과가 쌓이면 패턴을 알려드릴게요."
        }
        if let avg = stat.avgRealizedReturnPct, stat.winCount + stat.lossCount >= 2 {
            let sign = avg >= 0 ? "+" : ""
            return "'\(tag.label)' 매매 \(stat.count)번째 · 지금까지 확정 평균 \(sign)\(avg.formatted(.number.precision(.fractionLength(1))))%"
        }
        return "'\(tag.label)' 매매 \(stat.count)번째로 기록했어요."
    }

    func tradeCount() -> Int {
        let seasonNumber = currentSeason.number
        let descriptor = FetchDescriptor<TradeLog>(
            predicate: #Predicate { $0.seasonNumber == seasonNumber }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: 부검용 통계 (M4-3)

    private func seasonLogs() -> [TradeLog] {
        let seasonNumber = currentSeason.number
        return (try? context.fetch(FetchDescriptor<TradeLog>(
            predicate: #Predicate { $0.seasonNumber == seasonNumber }
        ))) ?? []
    }

    /// 시작 자금 대비 가장 큰 단일 매수 비중(%) — "몰빵" 판정의 원료.
    func maxBuyWeightPct() -> Double? {
        let buys = seasonLogs().filter { $0.side == .buy }
        guard let biggest = buys.map({ $0.avgFillPrice * Double($0.qty) }).max(),
              currentSeason.startCash > 0 else { return nil }
        return biggest / Double(currentSeason.startCash) * 100
    }

    /// 매수 주문의 평균 슬리피지(원).
    func avgBuySlippage() -> Double? {
        let slippages = seasonLogs().filter { $0.side == .buy }.map(\.slippage)
        guard !slippages.isEmpty else { return nil }
        return slippages.reduce(0, +) / Double(slippages.count)
    }

    // MARK: 시즌 전환 (M4-3 계좌 부검이 호출)

    /// 계좌 부검 통과 후 호출: 현 시즌 마감, 이월 규칙을 새기고 다음 시즌 시작.
    func startNextSeason(endEquity: Int, carriedRule: String?) -> Season {
        currentSeason.endedAt = .now
        currentSeason.endEquity = endEquity
        Analytics.log(.accountReset, [
            "season": "\(currentSeason.number)",
            "endEquity": "\(endEquity)",
            "carriedRule": carriedRule ?? "none"
        ])
        let next = Season(number: currentSeason.number + 1, startCash: 10_000_000)
        next.carriedRule = carriedRule
        context.insert(next)
        currentSeason = next
        try? context.save()
        return next
    }

    // MARK: 레슨·해금 (M2-5 / M3-1이 호출)

    /// 온보딩 완료 — 경험 분기에 따라 시작 해금 레벨이 다르다 (M5-1).
    func completeOnboarding(startLevel: Int) {
        progress.unlockLevel = max(progress.unlockLevel, startLevel)
        progress.onboardingDone = true
        try? context.save()
        Analytics.log(.onboardingLevelChoice,
                      ["choice": startLevel == 0 ? "beginner" : "experienced"])
    }

    func isLessonDone(_ lessonId: String) -> Bool {
        let done = (try? context.fetch(FetchDescriptor<LessonProgress>(
            predicate: #Predicate { $0.lessonId == lessonId }
        )))?.first?.completedAt
        return done != nil
    }

    #if DEBUG
    /// 개발용: 레슨 없이 해금 레벨을 강제 조정 (배포 빌드에는 포함되지 않음).
    func debugSetUnlockLevel(_ level: Int) {
        progress.unlockLevel = level
        try? context.save()
    }
    #endif

    func completeLesson(_ lessonId: String, unlocksLevel level: Int?) {
        let existing = (try? context.fetch(FetchDescriptor<LessonProgress>(
            predicate: #Predicate { $0.lessonId == lessonId }
        )))?.first
        let lesson = existing ?? {
            let fresh = LessonProgress(lessonId: lessonId)
            context.insert(fresh)
            return fresh
        }()
        lesson.completedAt = .now
        if let level, level > progress.unlockLevel {
            progress.unlockLevel = level
            Analytics.log(.toolUnlocked, ["level": "\(level)"])
        }
        try? context.save()
        Analytics.log(.lessonComplete, ["lessonId": lessonId])
    }
}
