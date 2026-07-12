import Foundation
import JurinKit

/// 합성 ETF 카탈로그 (트랙 2) — 기존 6종목 위에 얹힌 바스켓 상품.
/// 구성 좌수는 스펙 초기가 기준으로 고정된다 → 시즌·세션과 무관하게 결정론적.
/// 두 상품의 대비 자체가 커리큘럼이다: 저보수 지수형 vs 금 섞은 자산배분형.
struct ETFSpec: Identifiable {
    let code: String
    let name: String
    let oneLiner: String
    /// 연 운용보수 (TER)
    let expenseRatioAnnual: Double
    let inceptionNAV: Int
    let weights: [(symbol: String, weight: Double)]
    var id: String { code }

    /// 바스켓 β — 구성 가중 평균. 분산 점검·레슨의 원료.
    var basketBeta: Double {
        weights.reduce(0) { sum, entry in
            sum + entry.weight * (SymbolCatalog.spec(code: entry.symbol)?.config.marketBeta ?? 0)
        }
    }

    var expenseRatioLabel: String {
        "연 \((expenseRatioAnnual * 100).formatted(.number.precision(.fractionLength(2))))%"
    }

    func makeFund(ledger: AccountLedger) -> ETFFund {
        ETFFund(symbol: code,
                name: name,
                inceptionNAV: inceptionNAV,
                weights: weights,
                inceptionPrices: Dictionary(
                    uniqueKeysWithValues: SymbolCatalog.all.map { ($0.code, $0.initialPrice) }),
                expenseRatioAnnual: expenseRatioAnnual,
                ledger: ledger)
    }
}

enum ETFCatalog {
    /// 지수형 — "시장 전체를 통째로 산다". 종목 선택을 포기하는 대신 보수가 싸다.
    /// 비중은 시가총액 가중에 상한을 둔 형태 (실제 지수의 CAP 규칙 단순화).
    static let coreIndex = ETFSpec(
        code: "HIX",
        name: "한빛300 지수",
        oneLiner: "시장 전체를 통째로 담는 바구니",
        expenseRatioAnnual: 0.0015,
        inceptionNAV: 10_000,
        weights: [
            ("HBE", 0.40),
            ("HBH", 0.25),
            ("HBF", 0.25),
            ("HBB", 0.10)
        ]
    )

    /// 자산배분형 — 주식과 금을 섞어 흔들림을 줄인다. 편해진 만큼 보수는 더 낸다.
    static let balanced = ETFSpec(
        code: "HBA",
        name: "한빛 균형 자산배분",
        oneLiner: "주식 60 + 금 40, 흔들림을 줄인 바구니",
        expenseRatioAnnual: 0.0035,
        inceptionNAV: 10_000,
        weights: [
            ("HBE", 0.25),
            ("HBH", 0.10),
            ("HBF", 0.25),
            ("GLD", 0.40)
        ]
    )

    static let all: [ETFSpec] = [coreIndex, balanced]

    static func spec(code: String) -> ETFSpec? {
        all.first { $0.code == code }
    }

    static func code(forName name: String) -> String? {
        all.first { $0.name == name }?.code
    }
}
