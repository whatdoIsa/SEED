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
        TradeLog.self, Season.self, LessonProgress.self, AppProgress.self, SymbolState.self
    ])

    private let context: ModelContext
    private(set) var currentSeason: Season
    private(set) var progress: AppProgress
    /// 완료된 레슨 id — 관찰 대상 stored property. 이걸 통해 잠금 화면들이 즉시 갱신된다.
    /// (DB 직접 조회는 Observation이 추적하지 못해 화면이 안 바뀌던 문제 해결)
    private(set) var completedLessonIds: Set<String> = []

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

        // 완료 레슨 집합을 메모리로 로드 (이후 판정은 이 관찰 property로)
        let doneLessons = (try? context.fetch(FetchDescriptor<LessonProgress>())) ?? []
        completedLessonIds = Set(doneLessons.filter { $0.completedAt != nil }.map(\.lessonId))
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
                atCandleIndex: Int? = nil,
                wasLimit: Bool = false) {
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
        log.isLimitFill = wasLimit
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

    // MARK: 시장 연속성 (종목별 시드 + 틱 + 주문 리플레이)

    func persistSymbolState(code: String, seed: UInt64, tick: Int) {
        let seasonNumber = currentSeason.number
        let existing = (try? context.fetch(FetchDescriptor<SymbolState>(
            predicate: #Predicate { $0.code == code && $0.seasonNumber == seasonNumber }
        )))?.first
        if let existing {
            existing.lastTick = tick
            existing.seedBits = Int64(bitPattern: seed)
        } else {
            context.insert(SymbolState(seasonNumber: seasonNumber, code: code,
                                       seedBits: Int64(bitPattern: seed), lastTick: tick))
        }
        currentSeason.lastActiveAt = .now
        try? context.save()
    }

    func symbolState(code: String) -> (seed: UInt64, tick: Int)? {
        let seasonNumber = currentSeason.number
        guard let state = (try? context.fetch(FetchDescriptor<SymbolState>(
            predicate: #Predicate { $0.code == code && $0.seasonNumber == seasonNumber }
        )))?.first else { return nil }
        return (UInt64(bitPattern: state.seedBits), state.lastTick)
    }

    var lastActiveAt: Date? { currentSeason.lastActiveAt }

    /// 시장 기후 시드 — 시즌마다 하나. 없으면 만들어 고정한다 (리플레이 연속성).
    func climateSeed() -> UInt64 {
        if let bits = currentSeason.climateSeedBits {
            return UInt64(bitPattern: bits)
        }
        let seed = UInt64.random(in: 0...UInt64.max)
        currentSeason.climateSeedBits = Int64(bitPattern: seed)
        try? context.save()
        return seed
    }

    /// 리플레이 대상: 현재 시즌의 본 세션 매매 (시나리오 제외), 틱 순.
    func replayableLogs() -> [TradeLog] {
        seasonLogs()
            .filter { $0.scenarioId == nil && $0.atTick != nil }
            .sorted { ($0.atTick ?? 0) < ($1.atTick ?? 0) }
    }

    /// 특정 시나리오에서의 내 매매 — "나 vs 봇" 비교의 원료.
    func scenarioLogs(scenarioId: String) -> [TradeLog] {
        ((try? context.fetch(FetchDescriptor<TradeLog>(
            predicate: #Predicate { $0.scenarioId == scenarioId },
            sortBy: [SortDescriptor(\.timestamp)]
        ))) ?? [])
    }

    /// 최근 7일 매매 수 — 주간 푸시 본문의 원료.
    func weeklyTradeCount() -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let descriptor = FetchDescriptor<TradeLog>(
            predicate: #Predicate { $0.timestamp >= cutoff }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// 왕복 매매 페어링 (A) — 보유 습관의 원료.
    func roundTrips() -> [RoundTrip] {
        TradePairing.roundTrips(logs: replayableLogs())
    }

    func holdingStats() -> HoldingStats? {
        TradePairing.stats(from: roundTrips())
    }

    /// 매매 지도 마커 (M4 — 부록 A-4의 aha 모먼트). 종목별.
    func tradeMarks(symbolName: String) -> [(candleIndex: Int, price: Double, side: Side)] {
        replayableLogs().compactMap { log in
            guard log.symbol == symbolName, let index = log.atCandleIndex else { return nil }
            return (index, log.avgFillPrice, log.side)
        }
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
        // 관찰 property를 읽어 잠금 화면들이 즉시 반응하게 한다.
        completedLessonIds.contains(lessonId)
    }

    /// 전체 초기화 (설정): 모든 매매·시즌·레슨·진행을 지우고 첫 실행 상태로.
    /// 온보딩부터 다시 시작된다. 되돌릴 수 없다 — 호출 전 UI에서 반드시 확인받을 것.
    func eraseAll() {
        func deleteAll<T: PersistentModel>(_ type: T.Type) {
            let items = (try? context.fetch(FetchDescriptor<T>())) ?? []
            for item in items { context.delete(item) }
        }
        deleteAll(TradeLog.self)
        deleteAll(Season.self)
        deleteAll(LessonProgress.self)
        deleteAll(AppProgress.self)
        deleteAll(SymbolState.self)

        let season = Season(number: 1, startCash: 10_000_000)
        context.insert(season)
        currentSeason = season
        let fresh = AppProgress()
        context.insert(fresh)
        progress = fresh
        completedLessonIds = []
        try? context.save()
        Analytics.log(.accountReset, ["reason": "erase-all"])
    }

    #if DEBUG
    /// 개발용: 차트 도구 레벨만 강제 조정 (레슨 완료 상태는 건드리지 않음).
    func debugSetUnlockLevel(_ level: Int) {
        progress.unlockLevel = level
        try? context.save()
    }

    /// 개발용: 모든 레슨 완료 처리 + 전체 해금 — 오늘의 장·복기·봇·퀀트·후속 레슨이
    /// 전부 열린다. 미션을 하나하나 하지 않고 화면을 점검할 때.
    func debugUnlockEverything() {
        for lesson in LessonCatalog.registered where !completedLessonIds.contains(lesson.id) {
            let progressRecord = LessonProgress(lessonId: lesson.id)
            progressRecord.completedAt = .now
            context.insert(progressRecord)
        }
        completedLessonIds = Set(LessonCatalog.registered.map(\.id))
        progress.unlockLevel = UnlockLevel.all
        progress.onboardingDone = true
        try? context.save()
    }

    /// 개발용: 진행 상태 전체 초기화 (레슨·해금·온보딩) — 처음부터 흐름 점검용.
    func debugResetProgress() {
        let lessons = (try? context.fetch(FetchDescriptor<LessonProgress>())) ?? []
        for lesson in lessons { context.delete(lesson) }
        completedLessonIds = []
        progress.unlockLevel = UnlockLevel.lineOnly
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
        completedLessonIds.insert(lessonId)
        if let level, level > progress.unlockLevel {
            progress.unlockLevel = level
            Analytics.log(.toolUnlocked, ["level": "\(level)"])
        }
        try? context.save()
        Analytics.log(.lessonComplete, ["lessonId": lessonId])
    }
}
