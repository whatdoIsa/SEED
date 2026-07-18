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
        saveContext()

        // 완료 레슨 집합을 메모리로 로드 (이후 판정은 이 관찰 property로)
        let doneLessons = (try? context.fetch(FetchDescriptor<LessonProgress>())) ?? []
        completedLessonIds = Set(doneLessons.filter { $0.completedAt != nil }.map(\.lessonId))
    }

    /// 저장 실패를 조용히 삼키지 않는다 — CloudKit 백엔드 실패가 관측 불가하면
    /// 데이터 유실 원인을 영영 못 찾는다. 실패해도 앱은 계속 동작한다.
    private func saveContext() {
        do { try context.save() } catch {
            #if DEBUG
            print("[SeedStore] context.save 실패: \(error)")
            #endif
        }
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
        log.timelineEpoch = currentSeason.timelineEpoch
        context.insert(log)
        saveContext()

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

    func persistSymbolState(code: String, seed: UInt64, tick: Int, openOrders: Data? = nil) {
        let seasonNumber = currentSeason.number
        let bits = Int64(bitPattern: seed)
        let states = (try? context.fetch(FetchDescriptor<SymbolState>(
            predicate: #Predicate { $0.code == code && $0.seasonNumber == seasonNumber }
        ))) ?? []
        if let own = states.first(where: { $0.seedBits == bits }) {
            own.lastTick = tick
            own.openOrdersData = openOrders
        } else {
            // 다른 시드의 기존 레코드(iCloud 복원분)는 덮어쓰지 않는다 — 재설치 직후
            // 임포트 전 창에서 복원 상태를 덮어쓰면 리플레이가 영구 불능이 된다.
            // 자기 레코드를 새로 만들고, 중복은 refreshAfterRemoteImport가 병합한다.
            let fresh = SymbolState(seasonNumber: seasonNumber, code: code,
                                    seedBits: bits, lastTick: tick)
            fresh.openOrdersData = openOrders
            context.insert(fresh)
        }
        currentSeason.lastActiveAt = .now
        saveContext()
    }

    /// 미체결 지정가 직렬화 데이터 — 리플레이로 복원된 시장에 재접수할 때 읽는다.
    func openOrdersData(code: String) -> Data? {
        let seasonNumber = currentSeason.number
        let states = (try? context.fetch(FetchDescriptor<SymbolState>(
            predicate: #Predicate { $0.code == code && $0.seasonNumber == seasonNumber }
        ))) ?? []
        return states.max(by: { $0.lastTick < $1.lastTick })?.openOrdersData
    }

    /// 타임라인 리셋(스냅샷 폴백) 전용 — 이 종목의 시장 상태를 의도적으로 새로 교체한다.
    func replaceSymbolState(code: String, seed: UInt64, tick: Int) {
        let seasonNumber = currentSeason.number
        let states = (try? context.fetch(FetchDescriptor<SymbolState>(
            predicate: #Predicate { $0.code == code && $0.seasonNumber == seasonNumber }
        ))) ?? []
        for state in states { context.delete(state) }
        context.insert(SymbolState(seasonNumber: seasonNumber, code: code,
                                   seedBits: Int64(bitPattern: seed), lastTick: tick))
        saveContext()
    }

    func symbolState(code: String) -> (seed: UInt64, tick: Int)? {
        let seasonNumber = currentSeason.number
        let states = (try? context.fetch(FetchDescriptor<SymbolState>(
            predicate: #Predicate { $0.code == code && $0.seasonNumber == seasonNumber }
        ))) ?? []
        // 병합 전 중복이 있으면 진행 틱이 큰 쪽(복원본)을 신뢰한다
        guard let state = states.max(by: { $0.lastTick < $1.lastTick }) else { return nil }
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
        saveContext()
        return seed
    }

    // MARK: 원장 타임라인 (베이스라인 + 에포크)

    /// 현재 타임라인 번호 — 스냅샷 폴백으로 시장을 리셋할 때마다 +1. (nil = 0)
    var timelineEpoch: Int { currentSeason.timelineEpoch ?? 0 }

    /// 시즌의 원장 베이스라인 — 타임라인 리셋 시점의 계좌 상태.
    /// 부팅 시 원장을 여기서 시작하고, 현재 타임라인의 매매만 리플레이하면 된다.
    func ledgerBaseline() -> LedgerSnapshot? {
        guard let data = currentSeason.ledgerBaselineData else { return nil }
        return try? JSONDecoder().decode(LedgerSnapshot.self, from: data)
    }

    /// 타임라인 리셋: 현재 계좌 상태를 베이스라인으로 못박고 에포크를 올린다.
    /// 이전 매매는 베이스라인에 반영됐으므로 이후 리플레이에서 제외된다.
    func beginNewTimeline(baseline: LedgerSnapshot) {
        currentSeason.timelineEpoch = timelineEpoch + 1
        currentSeason.ledgerBaselineData = try? JSONEncoder().encode(baseline)
        saveContext()
    }

    /// 이번 시즌의 본 세션 실매매 전부 (시나리오 제외) — 복기·매매지도의 원료.
    private func seasonRealLogs() -> [TradeLog] {
        seasonLogs()
            .filter { $0.scenarioId == nil && $0.atTick != nil }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// 리플레이 대상: 현재 타임라인의 본 세션 매매, 틱 순.
    func replayableLogs() -> [TradeLog] {
        let epoch = timelineEpoch
        return seasonRealLogs()
            .filter { ($0.timelineEpoch ?? 0) == epoch }
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

    /// 왕복 매매 페어링 (A) — 보유 습관의 원료. 타임라인과 무관하게 시즌 전체.
    func roundTrips() -> [RoundTrip] {
        TradePairing.roundTrips(logs: seasonRealLogs())
    }

    func holdingStats() -> HoldingStats? {
        TradePairing.stats(from: roundTrips())
    }

    /// 매매 지도 마커 (M4 — 부록 A-4의 aha 모먼트). 종목별.
    func tradeMarks(symbolName: String) -> [(candleIndex: Int, price: Double, side: Side)] {
        seasonRealLogs().compactMap { log in
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
    /// 진행 중인 시즌의 약속(규칙)을 설정 — 시즌 1처럼 부검을 거치지 않은 시즌용.
    func setSeasonRule(_ rule: String?) {
        currentSeason.carriedRule = rule
        saveContext()
    }

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
        saveContext()
        return next
    }

    // MARK: 레슨·해금 (M2-5 / M3-1이 호출)

    /// 온보딩 완료 — 경험 분기에 따라 시작 해금 레벨이 다르다 (M5-1).
    func completeOnboarding(startLevel: Int) {
        progress.unlockLevel = max(progress.unlockLevel, startLevel)
        progress.onboardingDone = true
        saveContext()
        Analytics.log(.onboardingLevelChoice,
                      ["choice": startLevel == 0 ? "beginner" : "experienced"])
    }

    /// 오늘 완료한 본편 레슨 수 — 하루 1레슨 페이스의 기준.
    /// (심화 시리즈·오늘의 장은 세지 않는다)
    func mainLessonsCompletedToday() -> Int {
        let mainIds = Set(LessonCatalog.registered.map(\.id))
        let calendar = Calendar.current
        let lessons = (try? context.fetch(FetchDescriptor<LessonProgress>())) ?? []
        return lessons.filter { record in
            guard let done = record.completedAt else { return false }
            return mainIds.contains(record.lessonId) && calendar.isDateInToday(done)
        }.count
    }

    /// 복습·실천이 따라가는 트랙: 트랙 1 진행 중엔 트랙 1, 완주 후 트랙 2를 시작했으면 트랙 2.
    /// completedAt 전역 최신순이 아니라 트랙 진도 기준이라, 다른 트랙 맛보기(무료 1편)나
    /// iCloud 복원으로 되살아난 옛 기록이 복습을 가로채지 못한다.
    private var reviewTrackLessonIds: [String] {
        let track1 = LessonCatalog.all.map(\.id)
        let track2 = ETFTrackCatalog.all.map(\.id)
        let track1Done = track1.allSatisfy { completedLessonIds.contains($0) }
        let track2Started = track2.contains { completedLessonIds.contains($0) }
        return track1Done && track2Started ? track2 : track1
    }

    /// lessonId별 가장 최근 완료 시각 — 복원 병합 전의 중복 레코드가 있어도 판정이 흔들리지 않는다.
    private func latestCompletionDates() -> [String: Date] {
        let lessons = (try? context.fetch(FetchDescriptor<LessonProgress>())) ?? []
        var latest: [String: Date] = [:]
        for record in lessons {
            guard let done = record.completedAt else { continue }
            latest[record.lessonId] = max(latest[record.lessonId] ?? .distantPast, done)
        }
        return latest
    }

    /// 아침 복습 퀴즈의 대상: 진행 중인 트랙에서 진도상 가장 앞선 완료 편.
    /// 오늘 완료한 편은 건너뛴다 (배운 건 다음날 꺼내야 하므로) — 그 직전 편으로 물러난다.
    func latestMainLessonCompletedBeforeToday() -> String? {
        let dates = latestCompletionDates()
        let calendar = Calendar.current
        return reviewTrackLessonIds.reversed().first { id in
            guard let done = dates[id] else { return false }
            return !calendar.isDateInToday(done)
        }
    }

    /// 오늘의 실천 과제 대상: 진행 중인 트랙에서 진도상 가장 앞선 완료 편 (오늘 포함).
    func latestMainLessonCompleted() -> String? {
        reviewTrackLessonIds.reversed().first { completedLessonIds.contains($0) }
    }

    /// 마감된 시즌들 (아카이브) — 번호 순
    func pastSeasons() -> [Season] {
        let seasons = (try? context.fetch(FetchDescriptor<Season>(
            sortBy: [SortDescriptor(\.number)]
        ))) ?? []
        return seasons.filter { $0.endedAt != nil }
    }

    func isLessonDone(_ lessonId: String) -> Bool {
        // 관찰 property를 읽어 잠금 화면들이 즉시 반응하게 한다.
        completedLessonIds.contains(lessonId)
    }

    /// iCloud 복원 반영: CloudKit 임포트는 앱 실행 뒤에 도착하므로,
    /// 활성화될 때마다 저장소를 다시 읽어 참조를 최신으로 맞추고
    /// (새 기기 부트스트랩이 만든) 중복 레코드를 병합·정리한다. 멱등.
    func refreshAfterRemoteImport() {
        // 레슨: 같은 lessonId 중복 병합 — 임포트 도착 전에 새 기기에서 완료한 레코드와
        // 복원 레코드가 겹칠 수 있다. 완료 시각이 최신인 것을 남긴다
        // (옛 날짜 레코드가 남으면 오늘 마친 레슨이 아침 복습에 다시 나온다).
        let lessons = (try? context.fetch(FetchDescriptor<LessonProgress>())) ?? []
        var keptLessons: [String: LessonProgress] = [:]
        for record in lessons {
            guard let kept = keptLessons[record.lessonId] else {
                keptLessons[record.lessonId] = record
                continue
            }
            if (record.completedAt ?? .distantPast) > (kept.completedAt ?? .distantPast) {
                context.delete(kept)
                keptLessons[record.lessonId] = record
            } else {
                context.delete(record)
            }
        }
        // 완료 집합 재구성 (복원분 합류)
        completedLessonIds = Set(keptLessons.values.filter { $0.completedAt != nil }.map(\.lessonId))

        // 진행 상태: 여러 개면 최댓값으로 병합 후 하나만 남긴다
        let allProgress = (try? context.fetch(FetchDescriptor<AppProgress>())) ?? []
        if let first = allProgress.first {
            if allProgress.count > 1 {
                let mergedLevel = allProgress.map(\.unlockLevel).max() ?? 0
                let mergedOnboarding = allProgress.contains { $0.onboardingDone }
                first.unlockLevel = mergedLevel
                first.onboardingDone = mergedOnboarding
                for extra in allProgress.dropFirst() { context.delete(extra) }
            }
            progress = first
        }

        // 시즌: 활성(endedAt == nil)이 여러 개면 병합 — 높은 번호 우선, 같은 번호면
        // 먼저 시작한 쪽(복원 원본)을 남긴다. 새 기기 부트스트랩이 만든 빈 시즌은
        // startedAt이 더 늦다. 기후 시드·원장 베이스라인이 원본에 있으므로
        // 원본을 잃으면 리플레이가 어긋난다.
        let seasons = (try? context.fetch(FetchDescriptor<Season>(
            sortBy: [SortDescriptor(\.number, order: .reverse)]
        ))) ?? []
        let active = seasons.filter { $0.endedAt == nil }
        if active.count > 1 {
            let best = active.min { a, b in
                if a.number != b.number { return a.number > b.number }
                return a.startedAt < b.startedAt
            }!
            for extra in active where extra !== best {
                context.delete(extra)
            }
            currentSeason = best
        } else if let only = active.first {
            currentSeason = only
        }

        // 종목 상태: (시즌, 종목)당 하나 — 진행 틱이 큰 쪽(복원본)을 남긴다
        let states = (try? context.fetch(FetchDescriptor<SymbolState>())) ?? []
        var seen: [String: SymbolState] = [:]
        for state in states {
            let key = "\(state.seasonNumber)#\(state.code)"
            if let kept = seen[key] {
                if state.lastTick > kept.lastTick {
                    context.delete(kept)
                    seen[key] = state
                } else {
                    context.delete(state)
                }
            } else {
                seen[key] = state
            }
        }
        saveContext()
        WidgetBridge.sync(completed: completedLessonIds)
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
        saveContext()
        // 위젯도 초기화 — 안 하면 지워진 스트릭을 무기한 계속 보여준다
        WidgetBridge.sync(completed: [])
        Analytics.log(.accountReset, ["reason": "erase-all"])
    }

    #if DEBUG
    /// 개발용: 차트 도구 레벨만 강제 조정 (레슨 완료 상태는 건드리지 않음).
    func debugSetUnlockLevel(_ level: Int) {
        progress.unlockLevel = level
        saveContext()
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
        progress.unlockLevel = UnlockLevel.max
        progress.onboardingDone = true
        saveContext()
    }

    /// 개발용: 진행 상태 전체 초기화 (레슨·해금·온보딩) — 처음부터 흐름 점검용.
    func debugResetProgress() {
        let lessons = (try? context.fetch(FetchDescriptor<LessonProgress>())) ?? []
        for lesson in lessons { context.delete(lesson) }
        completedLessonIds = []
        progress.unlockLevel = UnlockLevel.lineOnly
        saveContext()
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
        saveContext()
        Analytics.log(.lessonComplete, ["lessonId": lessonId])
        WidgetBridge.sync(completed: completedLessonIds)
    }
}
