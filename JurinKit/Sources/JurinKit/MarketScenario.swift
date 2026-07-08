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

    /// 급락 패닉셀 시나리오 (⑥, 레슨 5): 보유 중 갑작스런 급락 → 공포 최고점의 결정
    /// → 바닥 다지기 → 부분 회복. 패닉에 팔면 바닥 근처 손실 확정, 버티면 회복분을 되찾는다.
    static func panicCrash(seed: UInt64 = 20_260_708) -> ScenarioPreset {
        ScenarioPreset(
            id: "scenario.panic-crash",
            seed: seed,
            initialPrice: 50_000,
            durationTicks: 600,
            anchorPull: 0.12,
            keyframes: [
                Keyframe(tick: 0, value: 50_000),      // 평온한 보유 구간
                Keyframe(tick: 120, value: 50_200),
                Keyframe(tick: 165, value: 42_500),    // 악재 급락 (-15%)
                Keyframe(tick: 260, value: 41_000),    // 바닥 다지기 (결정의 공포 구간)
                Keyframe(tick: 430, value: 45_500),    // 부분 회복
                Keyframe(tick: 600, value: 46_500)
            ],
            overrides: [
                // 급락 구간: 패닉 매물 + 추세 추종의 투매
                AgentOverride(agentId: "NOISE", startTick: 120, endTick: 280,
                              params: AgentParams(activity: 0.95, minQty: 30, maxQty: 160)),
                AgentOverride(agentId: "TREND", startTick: 120, endTick: 290,
                              params: AgentParams(activity: 0.85, minQty: 50, maxQty: 200)),
                // 바닥·회복 구간: 가치투자자의 저가 매수
                AgentOverride(agentId: "VALUE", startTick: 240, endTick: 520,
                              params: AgentParams(activity: 0.8, minQty: 70, maxQty: 240))
            ],
            decisions: [
                DecisionPrompt(
                    tick: 195,
                    prompt: "끝없이 떨어질 것 같아요. 어떻게 할까요?",
                    options: [
                        DecisionPrompt.Option(label: "지금 다 팔기", tagRaw: "fear"),
                        DecisionPrompt.Option(label: "버티기", tagRaw: "hold")
                    ]
                )
            ],
            timeScaleLabel: "1캔들 = 1일"
        )
    }

    /// 데드캣 바운스 시나리오: 급락 → 반짝 반등(희망) → 다시 하락(진짜 바닥).
    /// "떨어진 게 반등하니 바닥인 줄 알고 샀다가 더 물리는" 함정을 체험시킨다.
    static func deadCatBounce(seed: UInt64 = 20_260_709) -> ScenarioPreset {
        ScenarioPreset(
            id: "scenario.dead-cat",
            seed: seed,
            initialPrice: 50_000,
            durationTicks: 640,
            anchorPull: 0.12,
            keyframes: [
                Keyframe(tick: 0, value: 50_000),      // 평온
                Keyframe(tick: 120, value: 50_200),
                Keyframe(tick: 180, value: 43_000),    // 1차 급락
                Keyframe(tick: 240, value: 47_500),    // 반짝 반등 (죽은 고양이의 튀어오름)
                Keyframe(tick: 300, value: 47_000),    // 결정 지점 부근 — "바닥인가?"
                Keyframe(tick: 400, value: 39_000),    // 진짜 하락 재개
                Keyframe(tick: 520, value: 40_500),    // 진짜 바닥 다지기
                Keyframe(tick: 640, value: 41_500)
            ],
            overrides: [
                AgentOverride(agentId: "TREND", startTick: 120, endTick: 460,
                              params: AgentParams(activity: 0.85, minQty: 50, maxQty: 200)),
                AgentOverride(agentId: "NOISE", startTick: 120, endTick: 460,
                              params: AgentParams(activity: 0.92, minQty: 25, maxQty: 150)),
                AgentOverride(agentId: "VALUE", startTick: 460, endTick: 620,
                              params: AgentParams(activity: 0.8, minQty: 70, maxQty: 240))
            ],
            decisions: [
                DecisionPrompt(
                    tick: 285,
                    prompt: "떨어지던 게 다시 오르네요. 바닥일까요?",
                    options: [
                        DecisionPrompt.Option(label: "반등이니 지금 사기", tagRaw: "chase"),
                        DecisionPrompt.Option(label: "더 지켜보기", tagRaw: "dip")
                    ]
                )
            ],
            timeScaleLabel: "1캔들 = 1일"
        )
    }

    /// 횡보 시나리오: 아무 일도 없이 좁은 박스권. 지루함에 매매하면 수수료만 나간다.
    /// "가만히 있는 것도 매매"라는 인내를 가르친다.
    static func sideways(seed: UInt64 = 20_260_710) -> ScenarioPreset {
        ScenarioPreset(
            id: "scenario.sideways",
            seed: seed,
            initialPrice: 50_000,
            durationTicks: 600,
            anchorPull: 0.18,   // 강한 회귀로 박스권을 좁게 유지
            keyframes: [
                Keyframe(tick: 0, value: 50_000),
                Keyframe(tick: 150, value: 50_400),
                Keyframe(tick: 300, value: 49_700),
                Keyframe(tick: 450, value: 50_300),
                Keyframe(tick: 600, value: 50_000)
            ],
            overrides: [
                // 노이즈만 잔파도를 만들고 추세는 죽여 방향성이 안 생기게
                AgentOverride(agentId: "TREND", startTick: 0, endTick: 600,
                              params: AgentParams(activity: 0.1, minQty: 20, maxQty: 60))
            ],
            timeScaleLabel: "1캔들 = 1일"
        )
    }
}
