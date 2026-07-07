import Foundation
import JurinKit

/// 뉴스 이벤트 카피 (③) — 엔진의 headlineIndex를 문구로 매핑.
/// 가상 종목의 가상 뉴스: 실제 기업·실제 사건을 연상시키지 않게 일반형으로 쓴다.
enum NewsHeadlines {
    private static let positive = [
        "대형 수주 계약 체결 소식",
        "신제품 반응 예상 밖 호조",
        "분기 실적, 시장 기대 상회",
        "특허 소송 승소 확정",
        "해외 진출 인허가 획득",
        "자사주 매입 발표",
        "업계 1위와 협력 체결",
        "정부 지원 과제 선정",
        "핵심 기술 상용화 성공",
        "신용등급 상향 조정"
    ]

    private static let negative = [
        "핵심 계약 연장 불발",
        "분기 실적, 기대 하회",
        "경쟁사 신제품 출시 충격",
        "규제 강화 소식에 투자심리 위축",
        "핵심 인력 이탈 보도",
        "생산 라인 가동 중단",
        "소송 리스크 부각",
        "원자재 가격 급등 부담",
        "대규모 물량 출회 관측",
        "신용등급 하향 검토"
    ]

    // 거시(시장 전체) 뉴스 — 전 종목이 함께 흔들리는 이유
    private static let marketPositive = [
        "기준금리 동결 — 시장 안도",
        "수출 지표 예상 상회",
        "외국인 순매수 전환",
        "환율 안정세 진입",
        "경기 부양책 발표",
        "글로벌 증시 동반 강세",
        "물가 상승세 둔화 확인",
        "반도체 업황 회복 신호",
        "소비 심리 지수 반등",
        "정책 불확실성 해소"
    ]

    private static let marketNegative = [
        "기준금리 인상 우려 확산",
        "환율 급등 — 외국인 이탈",
        "글로벌 증시 동반 급락",
        "경기 침체 경고음",
        "지정학 리스크 부각",
        "물가 지표 쇼크",
        "수출 부진 — 성장 전망 하향",
        "신용 경색 우려",
        "대형 악재에 투자심리 급랭",
        "정책 불확실성 고조"
    ]

    static func text(for event: NewsEvent) -> String {
        let pool: [String]
        if event.isMarketWide {
            pool = event.isPositive ? marketPositive : marketNegative
        } else {
            pool = event.isPositive ? positive : negative
        }
        return pool[event.headlineIndex % pool.count]
    }
}
