import Foundation
import JurinKit

/// 거장 도장 — 실존 투자 거장들의 프로필과 봇.
/// 이야기는 역사적 사실, 봇은 그 철학의 단순화된 재현 (프로필에 명시).
struct MasterProfile: Identifiable {
    let id: String
    /// 칩에 쓰는 짧은 이름
    let shortName: String
    /// 봇 이름 · 성향
    let title: String
    let icon: String
    /// 단기/장기
    let horizon: String
    /// 대표 어록 (요지)
    let quote: String
    /// 인물 이야기 — 역사
    let story: String
    /// 봇 규칙 (라벨, 설명)
    let rules: [(String, String)]
    let strongMarkets: String
    let weakMarkets: String
    /// 이 전략을 사람이 따라할 때 무너지는 지점
    let mentalTrap: String
    let run: (ScenarioPreset) -> BotRun
}

enum MasterCatalog {
    static let all: [MasterProfile] = [turtle, graham, oneil, kostolany, templeton]

    static let turtle = MasterProfile(
        id: "turtle",
        shortName: "터틀",
        title: "터틀 봇 · 추세추종",
        icon: "tortoise.fill",
        horizon: "단기",
        quote: "\u{201C}예측하지 않는다. 추세를 따라간다.\u{201D}",
        story: """
        1983년, 전설적 트레이더 리처드 데니스는 동료 윌리엄 에크하르트와 내기를 했어요. "훌륭한 트레이더는 타고나는가, 만들어지는가." 데니스는 신문 광고로 경험 없는 사람들을 뽑아 2주간 규칙만 가르쳤죠 — 이들이 '터틀'입니다.

        결과는 데니스의 승리였어요. 터틀들은 4년간 연평균 80% 수준의 성과를 냈고, 이 실험은 투자사에 한 문장을 남겼어요: 성과를 만드는 건 재능이 아니라 **규칙과 그것을 지키는 일관성**이다.

        불편한 진실도 있어요. 터틀의 승률은 절반도 안 됐어요. 작게 여러 번 지고, 큰 추세 몇 번으로 버는 구조거든요. 그래서 진짜 시험은 시장이 아니라 — 연속 손절을 견디는 자기 자신이었대요.
        """,
        rules: [
            ("진입", "최근 최고가 돌파 시 매수 (추세 시작 신호)"),
            ("추가", "유리해질 때마다 1유닛 추가, 최대 4"),
            ("청산", "채널 하단 이탈 또는 평단 −2×변동폭 손절")
        ],
        strongMarkets: "긴 추세가 나오는 장 — 급등·급락 모두 (방향은 상관없다)",
        weakMarkets: "횡보장 — 가짜 돌파에 반복 손절당한다 (whipsaw)",
        mentalTrap: "연속 손절 구간에서 '규칙이 틀렸나' 의심하며 손절을 건너뛰는 순간, 터틀이 아니게 된다.",
        run: { BotComparison.runTurtle(scenario: $0) }
    )

    static let graham = MasterProfile(
        id: "graham",
        shortName: "그레이엄",
        title: "그레이엄 봇 · 가치투자",
        icon: "building.columns.fill",
        horizon: "장기",
        quote: "\u{201C}시장은 단기엔 투표 기계, 장기엔 저울이다.\u{201D}",
        story: """
        벤저민 그레이엄은 1929년 대공황에 재산을 잃고, 그 잿더미에서 가치투자를 만들었어요. 핵심은 두 가지예요.

        하나, **안전마진** — 1,000원짜리 가치를 700원에 사면, 계산이 좀 틀려도 살아남는다. 둘, **미스터 마켓** — 시장을 조울증 걸린 동업자라 생각하라. 그는 매일 다른 가격을 외치는데, 그의 기분에 전염되지 말고 그가 헐값을 부르는 날만 이용하라.

        그의 제자가 워런 버핏이에요. 버핏은 스승의 가르침을 한 문장으로 줄였죠: "남들이 탐욕스러울 때 두려워하고, 남들이 두려워할 때 탐욕스러워라."
        """,
        rules: [
            ("진입", "내재가치 추정보다 충분히 쌀 때만 매수 (안전마진)"),
            ("보유", "가치가 회복될 때까지 버틴다"),
            ("청산", "내재가치보다 비싸지면 매도 — 열광에 판다")
        ],
        strongMarkets: "급락장 — 공포가 가격을 가치 밑으로 끌어내릴 때",
        weakMarkets: "거품 급등장 — 살 게 없어 오래 구경만 한다",
        mentalTrap: "'싸다'고 산 게 더 싸질 때. 안전마진 계산 없이 흉내만 내면 떨어지는 칼을 잡게 된다.",
        run: { BotComparison.runValue(scenario: $0) }
    )

    static let oneil = MasterProfile(
        id: "oneil",
        shortName: "오닐",
        title: "오닐 봇 · 모멘텀",
        icon: "flame.fill",
        horizon: "단기",
        quote: "\u{201C}손실은 -8%에서 자른다. 예외는 없다.\u{201D}",
        story: """
        윌리엄 오닐은 30세에 뉴욕증권거래소 최연소 회원이 된 인물로, 100년 치 최고 주식들을 전부 분석해 공통점을 찾았어요 — 크게 오른 주식은 **신고가를 뚫으며 거래량이 붙을 때** 출발했다는 것. "싸게 사서 비싸게 팔라"의 반대죠. 비싸 보일 때 사서 더 비싸게 파는 전략이에요.

        하지만 그가 정말 유명한 건 매수 규칙이 아니라 **매도 철칙**이에요: 매수가에서 -8%가 되면 이유를 묻지 않고 판다. 뉴스도, 희망도, 자존심도 안 듣는다.

        "주식이 8% 빠졌다면 당신의 판단이 틀렸다는 시장의 통보다. 통보를 받아들이는 데 돈이 덜 드는 시점은 지금뿐이다."
        """,
        rules: [
            ("진입", "신고가 돌파 + 거래량 급증 확인 시 매수"),
            ("손절", "매수가 −8% 도달 시 무조건 매도 (철칙)"),
            ("청산", "단기 추세가 꺾이면 이익 보전")
        ],
        strongMarkets: "거래량이 실린 강한 급등장 — 주도주를 탄다",
        weakMarkets: "데드캣·횡보 — 가짜 돌파에 타지만, 손절이 피해를 -8%로 막는다",
        mentalTrap: "-8% 손절을 '이번만' 미루는 것. 오닐 전략에서 손절을 빼면 남는 건 고점 추격뿐이다.",
        run: { BotComparison.runONeil(scenario: $0) }
    )

    static let kostolany = MasterProfile(
        id: "kostolany",
        shortName: "코스톨라니",
        title: "코스톨라니 봇 · 소신파",
        icon: "moon.zzz.fill",
        horizon: "초장기",
        quote: "\u{201C}우량주를 사서 수면제를 먹고 자라. 10년 뒤에 깨어나면 부자가 되어 있을 것이다.\u{201D}",
        story: """
        앙드레 코스톨라니는 헝가리 출신으로 80년 가까이 시장을 산 유럽의 전설이에요. 그의 유명한 비유가 '개와 주인의 산책'이에요 — 주가(개)는 기업 가치(주인)보다 앞서 뛰기도 뒤처지기도 하지만, 결국 주인 곁으로 돌아온다. 그러니 개의 움직임에 일희일비하지 말라는 거죠.

        그는 투자자를 둘로 나눴어요. 시세에 흔들리는 '부화뇌동파', 그리고 소신을 가진 '소신파'. 소신파의 조건은 생각, 인내, 그리고 돈의 여유.

        이 봇의 매매 일지는 한 줄뿐이에요. 처음에 사고, 끝까지 잔다. **그 한 줄이 이 봇의 전부이자, 가장 어려운 기술**이에요 — 매일 열리는 시장 앞에서 아무것도 하지 않는 것.
        """,
        rules: [
            ("진입", "시즌 초반에 산다"),
            ("보유", "무슨 일이 있어도 잔다 — 뉴스·급락·유혹 전부 무시"),
            ("청산", "없다 (장 끝까지)")
        ],
        strongMarkets: "길게 우상향하는 장 — 아무것도 안 하고 다 먹는다",
        weakMarkets: "장기 하락장 — 같이 다 맞는다. 분산과 여유 자금이 전제인 이유",
        mentalTrap: "급락의 한가운데서 '이번엔 다르다'며 파는 것. 소신파는 팔 이유를 시세에서 찾지 않는다.",
        run: { BotComparison.runKostolany(scenario: $0) }
    )

    static let templeton = MasterProfile(
        id: "templeton",
        shortName: "템플턴",
        title: "템플턴 봇 · 역발상",
        icon: "arrow.uturn.up",
        horizon: "중기",
        quote: "\u{201C}비관이 최고조에 달했을 때가 최적의 매수 시점이다.\u{201D}",
        story: """
        1939년, 2차 세계대전이 터지고 시장이 공포에 잠겼을 때 — 존 템플턴은 뉴욕 증시에서 1달러 미만으로 떨어진 주식을 종목당 100달러씩, 104개 전부 샀어요. 심지어 파산 상태인 회사까지도요. 4년 뒤 이 '공포 바구니'는 4배가 됐습니다.

        그의 논리는 단순해요. 모두가 팔았다면 더 팔 사람이 없다 — 그럼 남은 방향은 하나뿐. 반대로 모두가 낙관할 때는 더 살 사람이 없죠.

        "강세장은 비관 속에서 태어나 회의 속에서 자라고, 낙관 속에서 성숙해 행복감 속에서 죽는다." 그래서 템플턴은 남들이 도망칠 때 들어가고, 남들이 몰려들 때 조용히 나옵니다.
        """,
        rules: [
            ("진입", "고점 대비 크게 빠진 '비관의 극점'에서 매수"),
            ("보유", "회복을 기다린다"),
            ("청산", "비관이 걷히고 낙관이 돌아오면 매도")
        ],
        strongMarkets: "급락 후 회복장, 데드캣의 진짜 바닥 — 공포를 산다",
        weakMarkets: "꾸준한 상승장 — 살 기회 자체가 오지 않는다",
        mentalTrap: "비관의 '극점'을 못 기다리고 하락 초입에 사는 것. 역발상은 용기가 아니라 기준이다.",
        run: { BotComparison.runTempleton(scenario: $0) }
    )
}

/// 도장에서 겨루는 장 — 같은 거장을 여러 장에 세워보면 '전략은 장을 탄다'가 드러난다.
enum DojoScenario: String, CaseIterable, Identifiable {
    case chase, crash, sideways, deadCat
    var id: String { rawValue }

    var label: String {
        switch self {
        case .chase: return "급등장"
        case .crash: return "급락장"
        case .sideways: return "횡보장"
        case .deadCat: return "데드캣"
        }
    }

    var preset: ScenarioPreset {
        switch self {
        case .chase: return .chaseRally()
        case .crash: return .panicCrash()
        case .sideways: return .sideways()
        case .deadCat: return .deadCatBounce()
        }
    }
}
