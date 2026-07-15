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
    // CloudKit 호환: 모든 속성은 인라인 기본값 필수 (init이 실제 값으로 덮어씀)
    var timestamp: Date = Date.distantPast
    var sideRaw: String = "buy"
    var symbol: String = ""
    /// 주문 시 화면에 보이던 최우선 호가
    var displayedPrice: Int = 0
    var qty: Int = 0
    var avgFillPrice: Double = 0
    /// 표시가 대비 불리한 방향이 양수 (슬리피지 튜토리얼·복기의 원료)
    var slippage: Double = 0
    var reasonTagRaw: String = "gut_buy"
    var note: String?
    var scenarioId: String?
    var seasonNumber: Int = 1
    /// 매도 시에만: 평단 대비 확정 수익률(%). L1 복기의 핵심 집계 대상.
    var realizedReturnPct: Double?
    /// 체결 시점의 엔진 틱 — 세션 리플레이의 좌표 (시나리오 매매는 nil)
    var atTick: Int?
    /// 체결 시점의 캔들 인덱스 — 매매 지도의 x 좌표
    var atCandleIndex: Int?
    /// 지정가 체결 여부 — 리플레이 시 포트폴리오 복원 경로로 분기
    var isLimitFill: Bool?
    /// 체결 당시의 타임라인 번호 (nil = 0) — 스냅샷 폴백으로 시장이 리셋되면
    /// 이전 타임라인의 매매는 베이스라인에 이미 반영돼 있어 리플레이에서 제외된다
    var timelineEpoch: Int?

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
    var number: Int = 1
    var startedAt: Date = Date.distantPast
    var endedAt: Date?
    var startCash: Int = 0
    /// 계좌 부검 시점의 최종 평가액
    var endEquity: Int?
    /// 부검에서 고른, 다음 시즌으로 가져가는 규칙 — 이월되는 것은 돈이 아니라 이것.
    var carriedRule: String?
    /// 포트폴리오 스냅샷 (리플레이 불가능한 구버전 데이터의 폴백)
    var savedCash: Int?
    var savedQty: Int?
    var savedAvgCost: Double?
    var savedRealizedPnL: Double?
    /// 시장 연속성: 시드 + 진행 틱만 있으면 같은 시장을 그대로 재현한다
    var engineSeedBits: Int64?
    var lastTick: Int?
    var lastActiveAt: Date?
    /// 시장 기후(상관관계) 시드 — 시즌 단위로 고정
    var climateSeedBits: Int64?
    /// 타임라인 번호 (nil = 0) — 스냅샷 폴백으로 시장을 리셋할 때마다 +1
    var timelineEpoch: Int?
    /// 타임라인 리셋 시점의 계좌 상태(LedgerSnapshot JSON) — 이후 매매만 리플레이하면 된다.
    /// Season 레코드에 실려 iCloud로 동기화되므로 재설치에도 현금·보유가 복원된다.
    var ledgerBaselineData: Data?

    init(number: Int, startedAt: Date = .now, startCash: Int) {
        self.number = number
        self.startedAt = startedAt
        self.startCash = startCash
    }
}

// MARK: - 종목별 시장 상태 (다종목 연속성)

@Model
final class SymbolState {
    var seasonNumber: Int = 1
    var code: String = ""
    var seedBits: Int64 = 0
    var lastTick: Int = 0
    /// 미체결 지정가 직렬화([MarketSession.PersistedOrder] JSON) — 재시작 시 재접수.
    /// 없으면 대기 주문이 앱 재시작에서 조용히 증발한다.
    var openOrdersData: Data?

    init(seasonNumber: Int, code: String, seedBits: Int64, lastTick: Int) {
        self.seasonNumber = seasonNumber
        self.code = code
        self.seedBits = seedBits
        self.lastTick = lastTick
    }
}

// MARK: - 레슨 진도

@Model
final class LessonProgress {
    /// 예: "lesson.candle", "lesson.orderbook", "lesson.chase"
    var lessonId: String = ""
    var startedAt: Date = Date.distantPast
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
    var unlockLevel: Int = 0
    var onboardingDone: Bool = false

    init(unlockLevel: Int = 0, onboardingDone: Bool = false) {
        self.unlockLevel = unlockLevel
        self.onboardingDone = onboardingDone
    }
}

/// 해금 레벨 상수 — 매직 넘버 방지.
/// 레벨 = 완료한 레슨 수. 레슨 하나를 마칠 때마다 1씩 오른다 (직관 체계).
/// 도구는 그것을 가르치는 레슨의 순번에서 열린다.
enum UnlockLevel {
    static let lineOnly = 0
    static let candles = 1      // 레슨 1: 캔들
    static let orderBook = 2    // 레슨 2: 호가창
    static let volumeAndMA = 4  // 레슨 4: 거래량·이동평균선
    static let all = 5          // 레슨 5: 급락 — 이후 도구 전부
    /// 표시용 최대 레벨 = 전체 레슨 수
    static var max: Int { LessonCatalog.registered.count }
}
