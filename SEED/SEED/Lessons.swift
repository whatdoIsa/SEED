import Foundation

// MARK: - 레슨 정의 (선언적 — 콘텐츠 문서 Part 1의 카피를 데이터로)

struct ConceptPage: Identifiable {
    enum Visual {
        case none
        case candleAnatomy
        case orderBookIntro
        case fomoIntro
    }

    let id = UUID()
    let text: String
    let visual: Visual
}

enum MissionKind {
    case tapBullish
    case slippageTutorial
    case chaseScenario
}

struct LessonDef: Identifiable {
    let id: String
    let order: Int
    let title: String
    let subtitle: String
    let duration: String
    /// 완료 시 열리는 해금 레벨 (nil이면 레벨 변화 없음)
    let unlocksLevel: Int?
    let unlockLabel: String
    let concept: [ConceptPage]
    let mission: MissionKind
}

enum LessonCatalog {
    static let candle = LessonDef(
        id: "lesson.candle",
        order: 1,
        title: "캔들, 시장의 심장박동",
        subtitle: "빨강과 파랑이 말해주는 것",
        duration: "약 90초",
        unlocksLevel: UnlockLevel.candles,
        unlockLabel: "캔들 차트 해금",
        concept: [
            ConceptPage(
                text: "방금까지 본 선은 '지금 값' 하나만 보여줬어요. 그런데 5분이든 하루든, 그 시간 동안 가격은 오르락내리락해요.\n\n**캔들 하나가 그 시간의 이야기 전부**를 담아요.",
                visual: .none
            ),
            ConceptPage(
                text: "시작보다 **오르며 끝난 시간은 빨강(양봉)**, 내리며 끝난 시간은 **파랑(음봉)**이에요.\n\n통통한 **몸통**은 시작값과 끝값 사이, 가느다란 **꼬리**는 그 시간의 최고·최저예요. 위로 긴 꼬리는 '올랐다가 도로 밀렸다'는 흔적이에요.\n\n참, 외국 앱은 반대예요 — 우리나라는 오르면 빨강입니다.",
                visual: .candleAnatomy
            )
        ],
        mission: .tapBullish
    )

    static let orderbook = LessonDef(
        id: "lesson.orderbook",
        order: 2,
        title: "호가창, 가격 뒤의 진짜 시장",
        subtitle: "표시가는 왜 내 체결가가 아닐까",
        duration: "약 2분",
        unlocksLevel: UnlockLevel.orderBook,
        unlockLabel: "호가창 · 체결 해금",
        concept: [
            ConceptPage(
                text: "화면의 52,300원은 사실 **'지금 살 수 있는 가장 싼 한 주'**의 값이에요.\n\n그 뒤엔 줄이 서 있어요 — \"이 값에 팔게요\"(매도호가)와 \"이 값에 살게요\"(매수호가).",
                visual: .orderBookIntro
            ),
            ConceptPage(
                text: "각 값에 걸린 주식 수를 **잔량**이라고 해요.\n\n최우선 매도호가의 잔량이 적으면, 한 번에 크게 사는 순간 그 위 값까지 먹으면서 **내가 산 평균값이 밀려요.**\n\n이걸 지금 직접 겪어볼 거예요.",
                visual: .none
            )
        ],
        mission: .slippageTutorial
    )

    static let chase = LessonDef(
        id: "lesson.chase",
        order: 3,
        title: "급등주를 쫓으면 생기는 일",
        subtitle: "안전하게 한 번 데여보기",
        duration: "약 3분",
        unlocksLevel: UnlockLevel.volumeAndMA,
        unlockLabel: "거래량·이평선 + 복기 리포트 해금",
        concept: [
            ConceptPage(
                text: "빨간 급등을 보면 사고 싶어져요. 남들 다 버는데 나만 놓치는 것 같거든요. 이 조급함엔 이름이 있어요 — **FOMO**(놓칠까 봐 두려운 마음).",
                visual: .none
            ),
            ConceptPage(
                text: "그런데 갑자기 뛴 가격은 종종 **원래 자리로 되돌아와요(평균회귀).** 늦게 올라탄 사람이 꼭지를 뒤집어쓰는 이유예요.\n\n백문이 불여일견. 이번엔 **안전하게 한 번 데여봐요.** 진짜 돈이 아니니까요.",
                visual: .fomoIntro
            )
        ],
        mission: .chaseScenario
    )

    static var all: [LessonDef] { registered }
    static var registered: [LessonDef] = [candle, orderbook, chase]
}

// MARK: - 미션 1용 손수 만든 캔들 (교육 목적으로 모양을 통제)

struct MiniCandle: Identifiable {
    let id = UUID()
    let open: Int
    let high: Int
    let low: Int
    let close: Int

    var isBullish: Bool { close >= open }
    /// 위꼬리가 몸통보다 긴 캔들 — "올랐다 밀린 흔적" 교육 포인트
    var hasLongUpperWick: Bool {
        let body = abs(close - open)
        return (high - max(open, close)) > max(body, 1)
    }
}

enum TapBullishMissionData {
    /// 음봉·양봉·긴 위꼬리 양봉이 골고루 섞이게 손으로 설계.
    static let candles: [MiniCandle] = [
        MiniCandle(open: 100, high: 104, low: 96, close: 97),   // 음봉
        MiniCandle(open: 97, high: 106, low: 96, close: 104),   // 양봉
        MiniCandle(open: 104, high: 110, low: 102, close: 102), // 음봉
        MiniCandle(open: 102, high: 112, low: 101, close: 109), // 양봉
        MiniCandle(open: 109, high: 121, low: 108, close: 111), // 양봉 + 긴 위꼬리
        MiniCandle(open: 111, high: 114, low: 105, close: 106)  // 음봉
    ]
    static let priceMin = 94
    static let priceMax = 123
}
