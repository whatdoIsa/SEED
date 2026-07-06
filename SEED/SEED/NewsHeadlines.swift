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

    static func text(for event: NewsEvent) -> String {
        let pool = event.isPositive ? positive : negative
        return pool[event.headlineIndex % pool.count]
    }
}
