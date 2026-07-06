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

    /// 레슨 2·3은 각 미션 구현과 함께 추가된다 (슬리피지 튜토리얼 / 급등 시나리오).
    static var all: [LessonDef] { registered }
    static var registered: [LessonDef] = [candle]
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
