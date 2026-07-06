import Foundation

// MARK: - 시나리오 프리셋 (스펙 3)

/// 시나리오 = fairValue 키프레임 경로 + 단계별 에이전트 오버라이드 + 결정 지점 + 결정론적 시드.
/// 같은 프리셋이면 항상 같은 시장이 나온다 — 복기·"나 vs 봇" 비교의 전제.
public struct ScenarioPreset {

    public struct Keyframe {
        public let tick: Int
        public let value: Double

        public init(tick: Int, value: Double) {
            self.tick = tick
            self.value = value
        }
    }

    /// 틱 구간 [startTick, endTick) 동안 특정 에이전트의 파라미터를 바꾼다.
    public struct AgentOverride {
        public let agentId: String
        public let startTick: Int
        public let endTick: Int
        public let params: AgentParams

        public init(agentId: String, startTick: Int, endTick: Int, params: AgentParams) {
            self.agentId = agentId
            self.startTick = startTick
            self.endTick = endTick
            self.params = params
        }

        func contains(_ tick: Int) -> Bool { tick >= startTick && tick < endTick }
    }

    /// 시나리오 진행 중 사용자에게 던지는 선택지. 태그는 rawValue 문자열로 전달해
    /// 코어가 앱의 태그 타입에 의존하지 않게 한다 (레이어 규칙).
    public struct DecisionPrompt: Equatable {
        public struct Option: Equatable {
            public let label: String
            public let tagRaw: String

            public init(label: String, tagRaw: String) {
                self.label = label
                self.tagRaw = tagRaw
            }
        }

        public let tick: Int
        public let prompt: String
        public let options: [Option]

        public init(tick: Int, prompt: String, options: [Option]) {
            self.tick = tick
            self.prompt = prompt
            self.options = options
        }
    }

    public let id: String
    public let seed: UInt64
    public let initialPrice: Int
    public let durationTicks: Int
    /// 시나리오 중 fairValue가 앵커를 따라가는 힘 (기본 랜덤워크보다 강하게).
    public let anchorPull: Double
    public let keyframes: [Keyframe]
    public let overrides: [AgentOverride]
    public let decisions: [DecisionPrompt]
    /// 압축 프레이밍 라벨 (예: "1캔들 = 1일"). UI 고지용.
    public let timeScaleLabel: String?

    public init(id: String, seed: UInt64, initialPrice: Int, durationTicks: Int,
                anchorPull: Double, keyframes: [Keyframe],
                overrides: [AgentOverride] = [], decisions: [DecisionPrompt] = [],
                timeScaleLabel: String? = nil) {
        self.id = id
        self.seed = seed
        self.initialPrice = initialPrice
        self.durationTicks = durationTicks
        self.anchorPull = anchorPull
        self.keyframes = keyframes.sorted { $0.tick < $1.tick }
        self.overrides = overrides
        self.decisions = decisions.sorted { $0.tick < $1.tick }
        self.timeScaleLabel = timeScaleLabel
    }

    /// 키프레임 사이 선형 보간. 범위 밖은 양 끝값으로 고정.
    public func anchorValue(at tick: Int) -> Double {
        guard let first = keyframes.first else { return Double(initialPrice) }
        guard tick > first.tick else { return first.value }
        for (prev, next) in zip(keyframes, keyframes.dropFirst()) {
            if tick <= next.tick {
                let span = Double(next.tick - prev.tick)
                guard span > 0 else { return next.value }
                let t = Double(tick - prev.tick) / span
                return prev.value + (next.value - prev.value) * t
            }
        }
        return keyframes.last!.value
    }
}

// MARK: - P0 시나리오: 급등주 추격매수의 결말 (M1-4)

public extension ScenarioPreset {

    /// 5단계 경로: 기저 횡보 → 촉발 급등 → 과열 오버슛(결정 지점) → 평균회귀 → 안정화.
    /// 오버슛에서 추격하면 물리고, 첫 눌림을 기다리면 우위가 생기도록 설계되어 있다.
    static func chaseRally(seed: UInt64 = 20_260_707) -> ScenarioPreset {
        ScenarioPreset(
            id: "scenario.chase-rally",
            seed: seed,
            initialPrice: 50_000,
            durationTicks: 600,
            anchorPull: 0.12,
            keyframes: [
                Keyframe(tick: 0, value: 50_000),      // 1 기저 횡보
                Keyframe(tick: 180, value: 50_200),
                Keyframe(tick: 230, value: 58_000),    // 2 촉발 (뉴스성 급등)
                Keyframe(tick: 300, value: 61_000),    // 3 과열 오버슛 (결정 지점)
                Keyframe(tick: 330, value: 60_000),
                Keyframe(tick: 450, value: 52_000),    // 4 평균회귀
                Keyframe(tick: 600, value: 51_500)     // 5 안정화
            ],
            overrides: [
                // 급등 구간: 추세추종·노이즈가 불에 기름을 붓는다
                AgentOverride(agentId: "TREND", startTick: 180, endTick: 330,
                              params: AgentParams(activity: 0.9, minQty: 60, maxQty: 220)),
                AgentOverride(agentId: "NOISE", startTick: 180, endTick: 330,
                              params: AgentParams(activity: 0.95, minQty: 20, maxQty: 120)),
                // 회귀 구간: 가치투자자가 고평가 물량을 시장에 던진다
                AgentOverride(agentId: "VALUE", startTick: 300, endTick: 480,
                              params: AgentParams(activity: 0.85, minQty: 80, maxQty: 260))
            ],
            decisions: [
                DecisionPrompt(
                    tick: 290,
                    prompt: "급등이 이어지고 있어요. 어떻게 할까요?",
                    options: [
                        DecisionPrompt.Option(label: "지금 사기", tagRaw: "chase"),
                        DecisionPrompt.Option(label: "첫 눌림까지 기다리기", tagRaw: "dip")
                    ]
                )
            ],
            timeScaleLabel: "1캔들 = 1일"
        )
    }
}
