import Foundation
import SwiftData
import JurinKit

// MARK: - 매매 사유 태그 (스펙 2 — 1탭 필수)

/// 진입 5종 + 청산 5종. 구조화 데이터라서 L1 룰베이스 복기가 API 없이 가능해진다.
enum TradeReasonTag: String, Codable, CaseIterable {
    // 진입 (매수)
    case breakout, dip, chase, news, gutBuy
    // 청산 (매도)
    case target, stopRule, fear, boredom, gutSell

    var label: String {
        switch self {
        case .breakout: return "돌파 기대"
        case .dip: return "눌림목"
        case .chase: return "급등 추격"
        case .news: return "뉴스·테마"
        case .gutBuy, .gutSell: return "그냥 감"
        case .target: return "목표 도달"
        case .stopRule: return "손절 원칙"
        case .fear: return "무서워서"
        case .boredom: return "지루해서"
        }
    }

    static func tags(for side: Side) -> [TradeReasonTag] {
        switch side {
        case .buy: return [.breakout, .dip, .chase, .news, .gutBuy]
        case .sell: return [.target, .stopRule, .fear, .boredom, .gutSell]
        }
    }
}

// MARK: - 매매 기록 (복기 시스템의 원료)

@Model
final class TradeLog {
    var timestamp: Date
    var sideRaw: String
    var symbol: String
    /// 주문 시 화면에 보이던 최우선 호가
    var displayedPrice: Int
    var qty: Int
    var avgFillPrice: Double
    /// 표시가 대비 불리한 방향이 양수 (슬리피지 튜토리얼·복기의 원료)
    var slippage: Double
    var reasonTagRaw: String
    var note: String?
    var scenarioId: String?
    var seasonNumber: Int
    /// 매도 시에만: 평단 대비 확정 수익률(%). L1 복기의 핵심 집계 대상.
    var realizedReturnPct: Double?

    var side: Side { Side(rawValue: sideRaw) ?? .buy }
    var reasonTag: TradeReasonTag { TradeReasonTag(rawValue: reasonTagRaw) ?? .gutBuy }

    init(timestamp: Date = .now,
         side: Side,
         symbol: String,
         displayedPrice: Int,
         qty: Int,
         avgFillPrice: Double,
         slippage: Double,
         reasonTag: TradeReasonTag,
         note: String? = nil,
         scenarioId: String? = nil,
         seasonNumber: Int,
         realizedReturnPct: Double? = nil) {
        self.timestamp = timestamp
        self.sideRaw = side.rawValue
        self.symbol = symbol
        self.displayedPrice = displayedPrice
        self.qty = qty
        self.avgFillPrice = avgFillPrice
        self.slippage = slippage
        self.reasonTagRaw = reasonTag.rawValue
        self.note = note
        self.scenarioId = scenarioId
        self.seasonNumber = seasonNumber
        self.realizedReturnPct = realizedReturnPct
    }
}

// MARK: - 시즌 (리셋 = 실패가 아니라 다음 시즌, §8.3)

@Model
final class Season {
    /// 시즌 번호 (1부터). 리셋마다 +1.
    var number: Int
    var startedAt: Date
    var endedAt: Date?
    var startCash: Int
    /// 계좌 부검 시점의 최종 평가액
    var endEquity: Int?
    /// 부검에서 고른, 다음 시즌으로 가져가는 규칙 — 이월되는 것은 돈이 아니라 이것.
    var carriedRule: String?
    /// 포트폴리오 스냅샷 (앱 재시작 시 복원) — 매매 직후 갱신
    var savedCash: Int?
    var savedQty: Int?
    var savedAvgCost: Double?
    var savedRealizedPnL: Double?

    init(number: Int, startedAt: Date = .now, startCash: Int) {
        self.number = number
        self.startedAt = startedAt
        self.startCash = startCash
    }
}

// MARK: - 레슨 진도

@Model
final class LessonProgress {
    /// 예: "lesson.candle", "lesson.orderbook", "lesson.chase"
    var lessonId: String
    var startedAt: Date
    var completedAt: Date?

    init(lessonId: String, startedAt: Date = .now) {
        self.lessonId = lessonId
        self.startedAt = startedAt
    }
}

// MARK: - 앱 전역 진행 상태 (단일 레코드)

@Model
final class AppProgress {
    /// 도구 해금 레벨 — P0 레슨 사슬 순서를 따른다:
    /// 0 라인차트 → 1 캔들(레슨1) → 2 호가창·체결(레슨2) → 3 거래량·이평선(레슨3)
    var unlockLevel: Int
    var onboardingDone: Bool

    init(unlockLevel: Int = 0, onboardingDone: Bool = false) {
        self.unlockLevel = unlockLevel
        self.onboardingDone = onboardingDone
    }
}

/// 해금 레벨 상수 — 매직 넘버 방지.
enum UnlockLevel {
    static let lineOnly = 0
    static let candles = 1
    static let orderBook = 2
    static let volumeAndMA = 3
    static let all = 9
}
