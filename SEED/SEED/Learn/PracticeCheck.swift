import SwiftUI

/// 오늘의 실천 — 가장 최근에 배운 레슨을 그날 시장에서 써보는 과제.
/// 자동 판정 대신 정직한 셀프 체크: 자신과의 약속이 규칙 매매의 첫 근육이다.
enum PracticeCatalog {
    static let all: [String: String] = [
        "lesson.candle": "오늘의 장에서 긴 몸통 캔들이 나오면 멈춰서 읽어보기 — 시가·종가·힘의 방향",
        "lesson.orderbook": "매수 버튼을 누르기 전에 호가 탭을 한 번 열어보기 — 내가 먹게 될 줄 확인",
        "lesson.chase": "오늘 급등을 만나면 사기 전에 자문하기 — \u{201C}신호를 봤나, 흥분을 봤나\u{201D}",
        "lesson.volume": "매수 전 거래량 바를 확인하기 — 평소보다 실렸는가?",
        "lesson.crash": "급락을 만나면 팔기 전에 자문하기 — \u{201C}계획대로인가, 공포인가\u{201D}",
        "lesson.diversify": "내 주식 탭에서 한 종목이 계좌의 절반을 넘지 않는지 확인하기",
        "lesson.valuetrap": "정보 탭에서 두 종목의 PER을 비교해보기 — 왜 다를까 한 번 생각하기",
        "lesson.support": "차트에서 이동평균선 근처의 가격 반응을 한 장면 관찰하기",
        "lesson.stoploss": "오늘 매수한다면 — 사기 전에 손절선 가격을 먼저 계산해두기",
        "lesson.patience": "오늘 시장이 지루하면, 안 사는 것으로 하루를 이겨보기",
        "lesson.sizing": "오늘 매수 전에 자문하기 — \u{201C}틀리면 얼마 잃지?\u{201D} 감당되는 수량인가",
        "lesson.graduation": "복기 탭을 열고 나의 가장 나쁜 습관 하나를 소리 내어 읽기",
        // 트랙 2 — ETF·분산투자
        "etf.what": "시장 탭에서 ETF 상세를 열어 바구니 구성 확인하기 — 내가 뭘 사게 되는지",
        "etf.index": "한빛300 1좌 사보기 — 산 뒤 구성 카드에서 내가 산 것들 확인",
        "etf.fee": "ETF 상세의 운용보수 카드에서 누적 차감액 확인하기 — 며칠 뒤 다시 보기",
        "etf.nav": "두 ETF의 NAV를 나란히 보고 오늘 각각 왜 움직였는지 구성으로 설명해보기",
        "etf.corr": "내 주식 탭의 분산 점검에서 내 계좌 β 확인하기 — 시장의 몇 배로 흔들리나",
        "etf.dca": "나만의 적립 규칙 정하기 — 예: 매 거래일 첫 접속 때 한빛300 3좌",
        "etf.rebalance": "목표 비율을 정하고 실제 비율과 비교하기 — 어긋났다면 리밸런싱 1건",
        "etf.graduation": "운용 계획 3줄(비율·적립·리밸런싱)을 메모에 적고 오늘 그대로 실행하기",
    ]

    static func todaysTask(store: SeedStore) -> (lessonId: String, task: String)? {
        guard let lessonId = store.latestMainLessonCompleted(),
              let task = all[lessonId] else { return nil }
        return (lessonId, task)
    }
}

enum PracticeRecord {
    private static let stampKey = "seed.practice.doneStamp"

    static var doneToday: Bool {
        UserDefaults.standard.integer(forKey: stampKey) == DailyMarket.dayStamp()
    }

    static func markDone() {
        UserDefaults.standard.set(DailyMarket.dayStamp(), forKey: stampKey)
    }

    /// 실수 탭 되돌리기
    static func unmark() {
        UserDefaults.standard.removeObject(forKey: stampKey)
    }
}

/// 배우기 탭 카드 — 과제 한 줄 + 셀프 체크
struct PracticeCard: View {
    let task: String
    @State private var checked = PracticeRecord.doneToday

    var body: some View {
        HStack(spacing: 12) {
            Button {
                checked.toggle()
                checked ? PracticeRecord.markDone() : PracticeRecord.unmark()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(checked ? SeedTheme.violet : SeedTheme.band, lineWidth: 2)
                        .background(Circle().fill(checked ? SeedTheme.violet : .clear))
                        .frame(width: 26, height: 26)
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("오늘의 실천")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SeedTheme.violetDeep)
                Text(task)
                    .font(.system(size: 13))
                    .foregroundStyle(checked ? SeedTheme.textSecondary : SeedTheme.textPrimary)
                    .strikethrough(checked, color: SeedTheme.textSecondary)
                    .lineSpacing(3)
                if checked {
                    Text("좋아요 — 배움이 행동이 됐어요")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SeedTheme.violetDeep)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .sensoryFeedback(.success, trigger: checked)
        .animation(.snappy(duration: 0.25), value: checked)
    }
}
