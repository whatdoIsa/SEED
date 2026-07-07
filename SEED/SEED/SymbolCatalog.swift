import Foundation
import JurinKit

/// 종목 카탈로그 (다종목) — 성격이 다른 시장들.
/// "종목마다 성격이 다르다"는 것 자체가 레슨이다: 둔한 대형주와 미친 잡주는 다른 세계다.
struct SymbolSpec: Identifiable {
    let code: String
    let name: String
    let oneLiner: String
    let initialPrice: Int
    let config: EngineConfig
    var isCrypto: Bool = false
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
                newsTickProbability: 1.0 / 1_400
            )
        ),
        SymbolSpec(
            code: "HBH",
            name: "한빛중공업",
            oneLiner: "평범한 중형주",
            initialPrice: 45_000,
            config: EngineConfig()
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
                newsMagnitudeRange: 0.03...0.10
            )
        )
    ]

    static func spec(code: String) -> SymbolSpec? {
        all.first { $0.code == code }
    }

    static func code(forName name: String) -> String? {
        all.first { $0.name == name }?.code
    }
}
