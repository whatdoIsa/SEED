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
                scenarioId: String? = nil) {
        var realized: Double?
        if fill.side == .sell, avgCostBeforeOrder > 0 {
            realized = (fill.avgFillPrice - avgCostBeforeOrder) / avgCostBeforeOrder * 100
        }
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
        context.insert(log)
        try? context.save()
    }

    // MARK: L1 룰베이스 복기 집계 (M4-1의 토대)

    struct TagStat: Identifiable {
        let tag: TradeReasonTag
        let count: Int
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
            return TagStat(tag: tag, count: items.count, avgRealizedReturnPct: avg)
        }
        .sorted { $0.count > $1.count }
    }

    func tradeCount() -> Int {
        let seasonNumber = currentSeason.number
        let descriptor = FetchDescriptor<TradeLog>(
            predicate: #Predicate { $0.seasonNumber == seasonNumber }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: 시즌 전환 (M4-3 계좌 부검이 호출)

    /// 계좌 부검 통과 후 호출: 현 시즌 마감, 이월 규칙을 새기고 다음 시즌 시작.
    func startNextSeason(endEquity: Int, carriedRule: String?) -> Season {
        currentSeason.endedAt = .now
        currentSeason.endEquity = endEquity
        let next = Season(number: currentSeason.number + 1, startCash: 10_000_000)
        next.carriedRule = carriedRule
        context.insert(next)
        currentSeason = next
        try? context.save()
        return next
    }

    // MARK: 레슨·해금 (M2-5 / M3-1이 호출)

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
        }
        try? context.save()
    }
}
