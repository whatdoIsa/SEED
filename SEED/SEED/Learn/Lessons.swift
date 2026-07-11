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
    case tapVolumeSpike
    case crashScenario
    case diversification
    case valueTrap
    case supportBounce
    case stopLoss
    case patience
    case positionSizing
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
    /// nil이면 읽기형 레슨 — 개념 페이지만으로 완료된다 (심화 시리즈)
    let mission: MissionKind?
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
        unlocksLevel: nil,  // 심리 레슨 — 도구 해금 없음
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

    static let volume = LessonDef(
        id: "lesson.volume",
        order: 4,
        title: "거래량, 움직임의 진심",
        subtitle: "가격은 속여도 거래량은 못 속인다",
        duration: "약 90초",
        unlocksLevel: UnlockLevel.volumeAndMA,
        unlockLabel: "거래량 읽는 눈 완성",
        concept: [
            ConceptPage(
                text: "가격이 오르는 건 누구나 봐요. 중요한 건 **얼마나 많은 사람이 그 값에 동의했는가** — 그게 거래량이에요.\n\n**거래량이 함께 터진 상승**은 진심이에요. 거래량 없이 슬금슬금 오른 가격은 몇 명이 밀어올린 것일 수 있어요 — 쉽게 무너져요.",
                visual: .none
            ),
            ConceptPage(
                text: "차트 아래 막대가 거래량이에요. 캔들과 같은 색으로, 그 시간에 얼마나 활발히 거래됐는지 보여줘요.\n\n**막대가 유난히 큰 캔들**을 눈여겨봐요 — 거기서 뭔가가 시작되거나 끝나요.",
                visual: .none
            )
        ],
        mission: .tapVolumeSpike
    )

    static let crash = LessonDef(
        id: "lesson.crash",
        order: 5,
        title: "급락, 공포를 파는 날",
        subtitle: "안전하게 한 번 더 데여보기",
        duration: "약 3분",
        unlocksLevel: UnlockLevel.all,
        unlockLabel: "급락 생존 훈련 완료",
        concept: [
            ConceptPage(
                text: "급락이 오면 머릿속에 한 문장만 남아요 — **\"더 떨어지기 전에 팔아야 해.\"**\n\n그런데 모두가 그 생각을 하는 순간이 바닥 근처인 경우가 많아요. 공포에 판 사람이 바닥을 만들어주고, 그 값에 누군가는 줍죠.",
                visual: .none
            ),
            ConceptPage(
                text: "팔지 말라는 얘기가 아니에요. **원칙으로 파는 것(손절)과 공포로 파는 것(패닉)은 완전히 달라요.**\n\n이번엔 주식을 들고 있는 채로 급락을 맞아봐요. 진짜 돈이 아니니까, 공포를 연습할 수 있어요.",
                visual: .none
            )
        ],
        mission: .crashScenario
    )

    static let diversify = LessonDef(
        id: "lesson.diversify",
        order: 6,
        title: "계란과 바구니",
        subtitle: "시장 전체가 빠지는 날의 생존법",
        duration: "약 2분",
        unlocksLevel: nil,
        unlockLabel: "분산 감각 장착",
        concept: [
            ConceptPage(
                text: "종목 뉴스는 고르면 피할 수 있어요. 그런데 **시장 뉴스는 모두가 함께 맞아요** — 금리, 환율, 침체 공포. 그런 날엔 좋은 종목도 같이 빠집니다.\n\n\"계란을 한 바구니에 담지 말라\"는 말은 이 날을 위한 거예요.",
                visual: .none
            ),
            ConceptPage(
                text: "종목마다 시장에 반응하는 크기가 달라요 — 이걸 **베타(β)**라고 해요.\n\n테마주는 시장이 1 빠질 때 **1.4배**로 맞고, 방어주는 **절반**만 맞고, 금 같은 자산은 **반대로** 움직이기도 해요.\n\n섞으면 계좌의 흔들림이 줄어요. 말로는 안 와닿죠 — 직접 맞아봅시다.",
                visual: .none
            )
        ],
        mission: .diversification
    )

    static let valueTrap = LessonDef(
        id: "lesson.valuetrap",
        order: 7,
        title: "싼 데는 이유가 있다",
        subtitle: "PER·PBR로 종목을 저울질하기",
        duration: "약 2분",
        unlocksLevel: nil,
        unlockLabel: "가치 지표 읽는 눈",
        concept: [
            ConceptPage(
                text: "가격만 보면 뭐가 싼지 알 수 없어요. 5만원짜리와 50만원짜리 중 뭐가 싼 걸까요? 답은 **이익 대비 얼마인가**예요.\n\n**PER**는 지금 가격이 회사 1년 이익의 몇 배인지예요. PER 10이면 지금 이익이 10년 쌓이면 주가만큼 벌어요. 낮을수록 '이익에 비해 싸다'는 뜻이에요.",
                visual: .none
            ),
            ConceptPage(
                text: "그런데 **낮은 PER이 무조건 좋은 건 아니에요.** 시장이 그 회사의 미래를 어둡게 보면, 이익이 곧 줄 거라 예상해서 가격을 미리 낮춰둔 거예요 — 이걸 **가치 함정**이라고 해요.\n\n반대로 PER이 높은데도 사람들이 사는 건, 이익이 앞으로 크게 늘 거라 **기대**하기 때문이에요.\n\n숫자 하나로 단정하지 말고, '왜 이 값일까'를 물어야 해요. 직접 저울질해봅시다.",
                visual: .none
            )
        ],
        mission: .valueTrap
    )

    static let supportBounce = LessonDef(
        id: "lesson.support",
        order: 8,
        title: "선이 받쳐주는 자리",
        subtitle: "이동평균선과 지지·저항",
        duration: "약 2분",
        unlocksLevel: nil,
        unlockLabel: "추세를 읽는 눈",
        concept: [
            ConceptPage(
                text: "**이동평균선**은 최근 며칠 종가의 평균을 이은 선이에요. 20일선은 최근 20일 평균이죠. 개별 캔들의 출렁임을 걷어내고 **큰 흐름**만 보여줘요.\n\n가격이 이평선 위에 있으면 상승 흐름, 아래면 하락 흐름 — 방향을 한눈에 읽는 도구예요.",
                visual: .none
            ),
            ConceptPage(
                text: "신기하게도, 오르던 가격이 잠깐 내려도 **이평선 근처에서 다시 튀어오르는** 일이 자주 있어요. 많은 사람이 '이 선에서는 사자'고 생각하니까요 — 이걸 **지지**라고 해요. 반대로 위에서 막히면 **저항**이고요.\n\n이런 흐름은 캔들 몇 개론 안 보여요. 수십 캔들이 지나야 드러나죠. 배속을 올려서 시간을 빠르게 감아봅시다.",
                visual: .none
            )
        ],
        mission: .supportBounce
    )

    static let stopLoss = LessonDef(
        id: "lesson.stoploss",
        order: 9,
        title: "손절, 지키기 위한 규칙",
        subtitle: "질 때 작게 지는 법",
        duration: "약 3분",
        unlocksLevel: nil,
        unlockLabel: "손절 원칙 장착",
        concept: [
            ConceptPage(
                text: "투자에서 이기는 사람과 무너지는 사람의 차이는 이길 때가 아니라 **질 때** 갈려요. 크게 잃지만 않으면 계좌는 살아남거든요.\n\n**손절**은 '여기까지 내려오면 판다'를 **사기 전에 미리 정해두는 것**이에요. 이미 물린 뒤에 '조금만 더 기다려볼까' 하는 건 손절이 아니라 희망이에요.",
                visual: .none
            ),
            ConceptPage(
                text: "손절선을 정하는 법은 여러 가지예요 — 산 값에서 **일정 % 아래**, 또는 지지선(이평선)을 **뚫고 내려가는 자리**.\n\n중요한 건 정한 선을 **지키는 것**이에요. 선에 닿으면 감정 없이 판다. 반토막의 수학 기억하죠? -50%는 +100%가 있어야 회복돼요. 작게 지는 습관이 결국 이기는 습관이에요.\n\n같은 하락을, 손절 있는 사람과 없는 사람으로 나눠서 겪어봅시다.",
                visual: .none
            )
        ],
        mission: .stopLoss
    )

    static let patience = LessonDef(
        id: "lesson.patience",
        order: 10,
        title: "지루함과 싸우기",
        subtitle: "아무 일도 없는 장에서 살아남기",
        duration: "약 2분",
        unlocksLevel: nil,
        unlockLabel: "기다림의 근육",
        concept: [
            ConceptPage(
                text: "시장의 대부분은 급등도 급락도 아니에요 — **방향 없는 횡보**죠. 그런데 이상하게, 이런 장에서 계좌가 갉려요.\n\n범인은 **지루함**이에요. 뭐라도 해야 할 것 같아서 사고, 조금 오르면 팔고, 다시 사고… 매매마다 수수료가 나가고, 방향이 없으니 벌 것도 없어요.",
                visual: .none
            ),
            ConceptPage(
                text: "프로들은 말해요 — **\"가만히 있는 것도 포지션\"** 이라고. 조건이 안 맞으면 안 하는 것, 그게 훈련된 인내예요.\n\n봇 매매 일지에서 봤죠? 조건이 없으면 봇은 그냥 기다려요.\n\n이제 아무 일도 없는 장을 드릴게요. 유혹을 견뎌보세요.",
                visual: .none
            )
        ],
        mission: .patience
    )

    static let sizing = LessonDef(
        id: "lesson.sizing",
        order: 11,
        title: "얼마나 살까",
        subtitle: "타이밍보다 크기가 계좌를 지킨다",
        duration: "약 2분",
        unlocksLevel: nil,
        unlockLabel: "자금 관리 감각",
        concept: [
            ConceptPage(
                text: "언제 살지, 언제 팔지는 배웠어요. 그런데 실전에서 초보의 계좌를 무너뜨리는 건 대부분 타이밍이 아니라 **크기**예요 — 한 번에 전부를 거는 것.\n\n같은 종목, 같은 타이밍이라도 전 재산으로 산 사람과 절반만 산 사람의 운명은 완전히 달라요. 틀렸을 때의 결과가 다르니까요.",
                visual: .none
            ),
            ConceptPage(
                text: "거장들의 공통 규칙이 여기 있어요. 터틀은 **한 번의 매수로 계좌의 1%만 위험**에 두도록 수량을 정했죠(터틀 ② 참고). 핵심 질문은 \"얼마나 벌까\"가 아니라 —\n\n**\"이번에 틀리면 얼마나 잃는가?\"**\n\n이 질문에 답할 수 있는 수량이 올바른 수량이에요. 같은 하락을 몰빵 계좌와 절반 계좌로 나눠 겪어봅시다.",
                visual: .none
            )
        ],
        mission: .positionSizing
    )

    static let graduation = LessonDef(
        id: "lesson.graduation",
        order: 12,
        title: "졸업 — 이 앱과 실전이 다른 것",
        subtitle: "정직한 마지막 수업",
        duration: "읽기 3분",
        unlocksLevel: nil,
        unlockLabel: "커리큘럼 수료",
        concept: [
            ConceptPage(
                text: "여기까지 왔다면, 당신은 이제 이런 것들을 가져요.\n\n캔들·호가·거래량을 읽는 눈. 급등을 쫓지 않고 급락에 계획으로 답하는 습관. 손절선·분산·수량이라는 세 겹의 방어. 그리고 매매마다 이유를 적고 복기하는 루틴 — 사실 이게 전부 중에 제일 큰 거예요.\n\n이건 진짜 실력이에요. 다만, 정직하게 말할 게 남았어요.",
                visual: .none
            ),
            ConceptPage(
                text: "**이 앱이 가르치지 못한 것들**\n\n① **실돈의 심리** — 가상 1,000만원의 -10%와 진짜 월급의 -10%는 완전히 다른 경험이에요. 여기서 완벽했던 규칙이 실전의 공포 앞에서 흔들릴 수 있어요.\n\n② **진짜 뉴스** — 여기의 뉴스는 깔끔한 신호였지만, 실전의 뉴스는 소음과 해석 싸움이에요.\n\n③ **제도의 디테일** — 세금, 수수료 체계, 거래 정지, 공시… 실전엔 이 앱이 단순화한 규칙이 훨씬 많아요.\n\n④ **시장의 어두운 면** — 작전, 리딩방, 허위 정보. 여기엔 없지만 실전엔 있어요.",
                visual: .none
            ),
            ConceptPage(
                text: "그래서 나가는 자세는 이래요.\n\n**작게 시작하세요.** 잃어도 생활이 흔들리지 않는 돈으로, 여기서 만든 규칙이 실돈 앞에서도 지켜지는지부터 확인하세요. 그게 진짜 첫 시험이에요.\n\n**이 앱은 계속 연습장이에요.** 실전을 시작해도 새 전략은 여기서 먼저 시험하고, 흔들린 날엔 여기로 돌아와 복기하세요.\n\n마지막으로 — 이 앱은 수익을 보장하지 않고, 어떤 종목도 추천하지 않아요. 판단과 책임은 언제나 당신의 것. 그걸 감당할 수 있는 사람이 되는 게 이 커리큘럼의 목표였어요. 졸업을 축하해요. 🌱",
                visual: .none
            )
        ],
        mission: nil
    )

    static var all: [LessonDef] { registered }
    static var registered: [LessonDef] = [candle, orderbook, chase, volume, crash, diversify, valueTrap, supportBounce, stopLoss, patience, sizing, graduation]
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

enum TapVolumeMissionData {
    /// 인덱스 3에서 가격·거래량이 함께 터진다 — 진짜 움직임의 표본.
    static let candles: [MiniCandle] = [
        MiniCandle(open: 100, high: 103, low: 98, close: 101),
        MiniCandle(open: 101, high: 104, low: 99, close: 100),
        MiniCandle(open: 100, high: 103, low: 98, close: 102),
        MiniCandle(open: 102, high: 115, low: 101, close: 113), // 거래량 폭증 + 장대양봉
        MiniCandle(open: 113, high: 117, low: 110, close: 114),
        MiniCandle(open: 114, high: 116, low: 111, close: 112)
    ]
    static let volumes = [42, 35, 39, 180, 66, 48]
    static let spikeIndex = 3
    static let priceMin = 96
    static let priceMax = 119
}
