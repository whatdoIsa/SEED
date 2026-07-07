import Foundation
import JurinKit

/// 종목 카탈로그 (다종목) — 성격이 다른 시장들.
/// "종목마다 성격이 다르다"는 것 자체가 레슨이다: 둔한 대형주와 미친 잡주는 다른 세계다.
/// 합성 재무제표 (D, §15.2 선행 과제) — 가상 종목의 펀더멘털.
/// 가격은 시장이 만들고, 이익·자산은 여기서 온다. PER·PBR은 이 둘의 비율로 살아 움직인다.
struct SymbolFinancials {
    /// 발행주식수
    let sharesOutstanding: Int
    /// 주당순이익 (EPS)
    let eps: Double
    /// 주당순자산 (BPS)
    let bps: Double
    /// 주당 배당금 (연) — 없으면 무배당
    let dividendPerShare: Int?

    func per(at price: Int) -> Double? {
        eps > 0 ? Double(price) / eps : nil
    }
    func pbr(at price: Int) -> Double? {
        bps > 0 ? Double(price) / bps : nil
    }
    func marketCap(at price: Int) -> Int { sharesOutstanding * price }
    func dividendYieldPct(at price: Int) -> Double? {
        guard let dividendPerShare, price > 0 else { return nil }
        return Double(dividendPerShare) / Double(price) * 100
    }
}

struct SymbolSpec: Identifiable {
    let code: String
    let name: String
    let oneLiner: String
    let initialPrice: Int
    let config: EngineConfig
    var isCrypto: Bool = false
    /// nil이면 재무제표가 없는 자산 (금·크립토)
    var financials: SymbolFinancials? = nil
    var id: String { code }
}

enum SymbolCatalog {
    static let all: [SymbolSpec] = [
        SymbolSpec(
            code: "HBE",
            name: "한빛전자",
            oneLiner: "둔하게 움직이는 대형주",
            initialPrice: 120_000,
            config: EngineConfig(
                fairVolatility: 0.0006,
                volClusterGain: 30,
                newsTickProbability: 1.0 / 1_400,
                marketBeta: 0.85
            ),
            financials: SymbolFinancials(
                sharesOutstanding: 480_000_000,   // 시총 약 57.6조
                eps: 10_900,                       // 시작가 기준 PER ≈ 11
                bps: 100_000,                      // PBR ≈ 1.2
                dividendPerShare: 2_600            // 배당수익률 ≈ 2.2%
            )
        ),
        SymbolSpec(
            code: "HBH",
            name: "한빛중공업",
            oneLiner: "평범한 중형주",
            initialPrice: 45_000,
            config: EngineConfig(marketBeta: 1.0),
            financials: SymbolFinancials(
                sharesOutstanding: 90_000_000,     // 시총 약 4.1조
                eps: 5_000,                        // PER ≈ 9
                bps: 56_000,                       // PBR ≈ 0.8 — 청산가치보다 싸다?
                dividendPerShare: 1_400            // ≈ 3.1%
            )
        ),
        SymbolSpec(
            code: "HBB",
            name: "한빛바이오",
            oneLiner: "널뛰는 고변동 테마주",
            initialPrice: 8_500,
            config: EngineConfig(
                fairVolatility: 0.0018,
                volClusterGain: 55,
                newsTickProbability: 1.0 / 500,
                newsMagnitudeRange: 0.03...0.10,
                marketBeta: 1.4
            ),
            financials: SymbolFinancials(
                sharesOutstanding: 60_000_000,     // 시총 약 5,100억
                eps: 100,                          // PER ≈ 85 — 이익보다 기대로 산다
                bps: 1_400,                        // PBR ≈ 6
                dividendPerShare: nil              // 무배당
            )
        ),
        SymbolSpec(
            code: "HBF",
            name: "한빛식품",
            oneLiner: "시장이 흔들려도 밥은 먹는 방어주",
            initialPrice: 68_000,
            config: EngineConfig(
                fairVolatility: 0.0005,
                volClusterGain: 25,
                newsTickProbability: 1.0 / 1_800,
                newsMagnitudeRange: 0.015...0.04,
                marketBeta: 0.45
            ),
            financials: SymbolFinancials(
                sharesOutstanding: 40_000_000,     // 시총 약 2.7조
                eps: 5_700,                        // PER ≈ 12
                bps: 62_000,                       // PBR ≈ 1.1
                dividendPerShare: 2_400            // ≈ 3.5%
            )
        ),
        SymbolSpec(
            code: "GLD",
            name: "한빛골드",
            oneLiner: "시장과 반대로 숨쉬는 안전자산",
            initialPrice: 250_000,
            config: EngineConfig(
                fairVolatility: 0.0007,
                volClusterGain: 25,
                newsTickProbability: 1.0 / 1_800,
                newsMagnitudeRange: 0.015...0.04,
                marketBeta: -0.5
            )
        ),
        // 크립토 합성 모드 (§16): 주식과 같은 엔진, 다른 제도 —
        // 24시간(장 마감 없음)·상하한가 없음·거래세 없음·고변동. 데이터는 합성.
        SymbolSpec(
            code: "BTX",
            name: "비트씨",
            oneLiner: "24시간 도는 가상자산",
            initialPrice: 480_000,
            config: EngineConfig(
                tickSize: 500,
                fairVolatility: 0.0028,
                volClusterGain: 65,
                newsTickProbability: 1.0 / 400,
                newsMagnitudeRange: 0.04...0.12,
                commissionRate: 0.0005,
                sellTaxRate: 0,
                candlesPerDay: 0,
                priceBandRate: 0,
                usesKRXTickSize: false,
                marketBeta: 0.2
            ),
            isCrypto: true
        )
    ]

    static func spec(code: String) -> SymbolSpec? {
        all.first { $0.code == code }
    }

    static func code(forName name: String) -> String? {
        all.first { $0.name == name }?.code
    }
}
