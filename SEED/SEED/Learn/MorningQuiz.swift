import SwiftUI

/// 아침 복습 퀴즈 — 어제(또는 그 전) 배운 레슨을 다음날 1문제로 되새긴다.
/// 간격을 두고 꺼내야 기억이 굳는다 (간격 반복). 하루 1레슨 페이스와 맞물린다.

struct QuizQuestion: Identifiable {
    var id: String { lessonId }
    let lessonId: String
    let question: String
    let choices: [String]
    let answerIndex: Int
    let explanation: String
}

enum QuizCatalog {
    static let all: [String: QuizQuestion] = [
        "lesson.candle": QuizQuestion(
            lessonId: "lesson.candle",
            question: "파란색(음봉) 캔들의 뜻은?",
            choices: ["시가보다 종가가 낮다 — 그 시간엔 내렸다",
                      "거래량이 적었다",
                      "하한가에 닿았다"],
            answerIndex: 0,
            explanation: "캔들 색은 시가 대비 종가의 방향이에요. 몸통이 길수록 그 방향의 힘이 셌다는 뜻이고요."),
        "lesson.orderbook": QuizQuestion(
            lessonId: "lesson.orderbook",
            question: "화면에 보이는 '현재가'로 내가 살 수 있을까?",
            choices: ["항상 그 가격에 살 수 있다",
                      "아니다 — 그건 마지막 체결가일 뿐, 나는 매도 호가 줄을 먹으며 산다",
                      "지정가 주문이면 무조건 그 가격에 체결된다"],
            answerIndex: 1,
            explanation: "시장가 주문은 팔겠다고 줄 선 물량을 순서대로 먹어요. 그 차이가 슬리피지예요."),
        "lesson.chase": QuizQuestion(
            lessonId: "lesson.chase",
            question: "급등이 '확실해 보이는' 순간, 확률적으로 나는 어디쯤에 있나?",
            choices: ["추세의 초입 — 지금 타면 싸게 탄다",
                      "이미 고점 근처 — 초입에 산 사람들의 물량을 받는 자리",
                      "알 수 없으므로 절반만 산다"],
            answerIndex: 1,
            explanation: "누구나 알아볼 만큼 급등이 진행됐다면, 초입에 산 사람들이 팔 준비를 하는 시점이에요."),
        "lesson.volume": QuizQuestion(
            lessonId: "lesson.volume",
            question: "거래량 없이 가격만 오르는 상승은 어떻게 읽어야 하나?",
            choices: ["조용히 오르니 더 좋다",
                      "참여자가 적다는 뜻 — 진심이 얕은 움직임이라 의심한다",
                      "거래량과 가격은 관계없다"],
            answerIndex: 1,
            explanation: "가격은 소수가 움직일 수 있지만 거래량은 못 속여요. 거래량이 실린 움직임이 무게가 달라요."),
        "lesson.crash": QuizQuestion(
            lessonId: "lesson.crash",
            question: "급락 한가운데서 가장 위험한 행동은?",
            choices: ["미리 정한 손절선대로 파는 것",
                      "계획 없이 공포에 투매하는 것",
                      "관망하는 것"],
            answerIndex: 1,
            explanation: "공포 투매는 대부분 바닥 근처에서 나와요. 파는 것 자체가 아니라 '계획 없이' 파는 게 문제예요."),
        "lesson.diversify": QuizQuestion(
            lessonId: "lesson.diversify",
            question: "β(베타)가 1.4인 종목의 뜻은?",
            choices: ["시장이 1% 빠질 때 이 종목은 1.4%쯤 빠지는 경향",
                      "1.4년에 한 번 배당한다",
                      "PER이 1.4배라는 뜻"],
            answerIndex: 0,
            explanation: "β는 시장 전체 대비 반응 크기예요. 시장이 빠지는 날 테마주가 더 아픈 이유죠."),
        "lesson.valuetrap": QuizQuestion(
            lessonId: "lesson.valuetrap",
            question: "PER 3배로 아주 '싼' 회사를 발견했다. 첫 질문은?",
            choices: ["당장 사자 — 싸니까",
                      "왜 이렇게 싼가? 시장이 뭘 알고 있나?",
                      "PER이 낮으니 안전하다"],
            answerIndex: 1,
            explanation: "시장이 미래 이익 급감을 미리 반영해 가격을 낮춘 것일 수 있어요 — 가치 함정이에요."),
        "lesson.support": QuizQuestion(
            lessonId: "lesson.support",
            question: "오르던 가격이 20일 이평선까지 눌렸다. 지지 매수의 짝이 되는 규칙은?",
            choices: ["선이 깨지면 손절",
                      "떨어질 때마다 물타기",
                      "무조건 3일 보유"],
            answerIndex: 0,
            explanation: "지지는 항상 통하지 않아요. 선을 뚫고 내려가면 흐름이 바뀐 신호 — 그래서 손절이 짝이에요."),
        "lesson.stoploss": QuizQuestion(
            lessonId: "lesson.stoploss",
            question: "-50% 손실을 원금으로 되돌리려면 몇 %가 필요할까?",
            choices: ["+50%", "+75%", "+100%"],
            answerIndex: 2,
            explanation: "100원이 50원이 되면, 다시 100원이 되기 위해 50원이 두 배가 돼야 해요. 크게 잃지 않는 게 이기는 길인 이유예요."),
        "lesson.patience": QuizQuestion(
            lessonId: "lesson.patience",
            question: "방향 없는 횡보장에서 확실하게 쌓이는 것 하나는?",
            choices: ["수익", "수수료", "배당"],
            answerIndex: 1,
            explanation: "방향이 없으니 벌 것은 불확실한데, 매매마다 나가는 수수료는 확실해요. 가만히 있는 것도 포지션이에요."),
        "lesson.sizing": QuizQuestion(
            lessonId: "lesson.sizing",
            question: "수량을 정할 때 먼저 물어야 하는 질문은?",
            choices: ["이번에 얼마나 벌 수 있나",
                      "이번에 틀리면 얼마나 잃는가",
                      "남들은 몇 주나 샀나"],
            answerIndex: 1,
            explanation: "감당 가능한 손실에서 거꾸로 수량을 정하는 게 자금 관리예요. 터틀은 그 답을 계좌의 1%로 정했죠."),
        "lesson.graduation": QuizQuestion(
            lessonId: "lesson.graduation",
            question: "이 앱에서 완성한 규칙을 실전으로 가져갈 때 첫걸음은?",
            choices: ["확신 있는 종목에 크게 시작",
                      "잃어도 되는 소액으로 규칙이 실돈 앞에서도 지켜지는지 확인",
                      "실전에선 감이 더 중요하니 규칙은 버린다"],
            answerIndex: 1,
            explanation: "가상 돈과 실돈의 심리는 달라요. 진짜 첫 시험은 종목 선택이 아니라 — 실돈 앞에서의 나 자신이에요."),
        // 트랙 2 — ETF·분산투자
        "etf.what": QuizQuestion(
            lessonId: "etf.what",
            question: "ETF가 지워주는 위험과 못 지우는 위험은?",
            choices: ["시장 전체의 위험은 지우고, 개별 회사의 위험은 남는다",
                      "개별 회사의 위험은 줄이고, 시장 전체의 위험은 그대로다",
                      "두 위험 모두 사라진다"],
            answerIndex: 1,
            explanation: "바구니 속 한 종목이 무너져도 비중만큼만 아파요. 하지만 시장이 빠지는 날은 바구니째 빠져요 — ETF는 마법이 아니라 평균이에요."),
        "etf.index": QuizQuestion(
            lessonId: "etf.index",
            question: "지수 ETF를 산다는 것의 정확한 뜻은?",
            choices: ["시장 평균 수익률을 확실히 받는다",
                      "전문가가 고른 좋은 종목만 산다",
                      "시장이 빠져도 손해 보지 않는다"],
            answerIndex: 0,
            explanation: "지수는 시장의 체온계고, 지수 ETF는 그걸 따라가는 바구니예요. 평균이 초라해 보여도 — 장기전에선 대부분의 프로가 그 평균을 못 이겼어요."),
        "etf.fee": QuizQuestion(
            lessonId: "etf.fee",
            question: "운용보수가 무서운 진짜 이유는?",
            choices: ["금액이 커서",
                      "수익이 나든 말든 원금 전체에 매년 복리로 작용해서",
                      "팔 때 한꺼번에 청구돼서"],
            answerIndex: 1,
            explanation: "0.84%p 차이가 30년 뒤 1,500만원이 되는 게 복리예요. NAV에서 매일 조금씩 빠져 고지서도 없죠 — 보이지 않는 월세예요."),
        "etf.nav": QuizQuestion(
            lessonId: "etf.nav",
            question: "괴리율 +2%인 ETF를 산다는 것은?",
            choices: ["진짜 가치보다 2% 비싸게 사는 것",
                      "수수료를 2% 아끼는 것",
                      "NAV가 2% 오른다는 예고"],
            answerIndex: 0,
            explanation: "NAV가 바구니의 진짜 가치예요. 시장가가 그 위에 떠 있으면(프리미엄) 지수가 그대로여도 괴리가 닫히는 것만으로 손해를 봐요."),
        "etf.corr": QuizQuestion(
            lessonId: "etf.corr",
            question: "진짜 분산을 만드는 것은?",
            choices: ["종목 수를 최대한 늘리는 것",
                      "서로 다르게(낮거나 반대로) 움직이는 자산을 섞는 것",
                      "가장 안전한 종목 하나에 집중하는 것"],
            answerIndex: 1,
            explanation: "같은 방향으로 움직이는 넷은 계란 네 개, 바구니 하나예요. 금(β -0.5)처럼 반대로 숨쉬는 자산이 흔들림을 줄여줘요."),
        "etf.dca": QuizQuestion(
            lessonId: "etf.dca",
            question: "적립식(DCA)의 진짜 힘은 어디서 오나?",
            choices: ["항상 몰빵보다 수익률이 높아서",
                      "하락장을 '싸게 사는 달'로 바꿔 시장을 떠나지 않게 해서",
                      "수수료가 면제돼서"],
            answerIndex: 1,
            explanation: "우상향 시장에선 통계적으로 몰빵이 더 자주 이겼어요. 그래도 적립식이 권해지는 건 심리 — 계속하게 만드는 구조가 결국 이겨요."),
        "etf.rebalance": QuizQuestion(
            lessonId: "etf.rebalance",
            question: "리밸런싱이 하는 일을 한 문장으로?",
            choices: ["오른 자산을 더 사서 추세를 탄다",
                      "오른 걸 팔고 내린 걸 사서 원래 비율로 되돌린다",
                      "모든 자산을 팔고 현금으로 피신한다"],
            answerIndex: 1,
            explanation: "비싸게 팔고 싸게 사는 행동이 규칙 안에 내장된 장치예요. 감정은 정확히 반대를 시키니까 — 기계적으로 뒤집는 거죠."),
        "etf.graduation": QuizQuestion(
            lessonId: "etf.graduation",
            question: "코어-위성 구조에서 코어의 역할은?",
            choices: ["단기 급등주로 수익을 극대화한다",
                      "지수·자산배분 ETF로 시장 평균을 확실히 확보한다",
                      "현금으로만 채워 위험을 0으로 만든다"],
            answerIndex: 1,
            explanation: "코어(60~80%)가 평균을 지켜주니 위성(개별주)이 틀려도 계좌가 버텨요. 실험은 작게, 기본은 크게."),
    ]

    /// 오늘 복습할 문제: 가장 최근에 완료한 본편 레슨 중 '오늘 이전'에 완료한 것.
    static func todaysQuiz(store: SeedStore) -> QuizQuestion? {
        guard let lessonId = store.latestMainLessonCompletedBeforeToday() else { return nil }
        return all[lessonId]
    }
}

/// 하루 한 번 판정 (기기 저장)
enum QuizRecord {
    private static let stampKey = "seed.quiz.lastDoneStamp"

    static var doneToday: Bool {
        UserDefaults.standard.integer(forKey: stampKey) == DailyMarket.dayStamp()
    }

    static func markDone() {
        UserDefaults.standard.set(DailyMarket.dayStamp(), forKey: stampKey)
    }
}

/// 퀴즈 시트 — 문제 → 선택 → 정답 공개 + 해설
struct MorningQuizSheet: View {
    let quiz: QuizQuestion
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("아침 복습")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SeedTheme.violetDeep)
                    Text(quiz.question)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                        .lineSpacing(4)
                }
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(Array(quiz.choices.enumerated()), id: \.offset) { index, choice in
                    Button {
                        guard picked == nil else { return }
                        picked = index
                        QuizRecord.markDone()
                    } label: {
                        HStack {
                            Text(choice)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(choiceColor(index))
                                .multilineTextAlignment(.leading)
                                .lineSpacing(3)
                            Spacer()
                            if picked != nil && index == quiz.answerIndex {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SeedTheme.up)
                            } else if picked == index {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(SeedTheme.down)
                            }
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(choiceBackground(index), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let picked {
                VStack(alignment: .leading, spacing: 8) {
                    Text(picked == quiz.answerIndex ? "정확해요! 👏" : "아깝네요 — 정답을 봐요")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    Text(quiz.explanation)
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textSecondary)
                        .lineSpacing(4)
                    Button {
                        dismiss()
                    } label: {
                        Text("오늘도 한 판 하러 가기")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.top, 4)
                }
                .transition(.opacity)
            }
            Spacer()
        }
        .animation(.snappy(duration: 0.25), value: picked)
        .padding(20)
        .background(SeedTheme.background)
        .presentationDetents([.medium, .large])
    }

    private func choiceColor(_ index: Int) -> Color {
        guard picked != nil else { return SeedTheme.textPrimary }
        return index == quiz.answerIndex ? SeedTheme.textPrimary : SeedTheme.textSecondary
    }

    private func choiceBackground(_ index: Int) -> Color {
        guard picked != nil else { return SeedTheme.card }
        if index == quiz.answerIndex { return SeedTheme.up.opacity(0.1) }
        if picked == index { return SeedTheme.down.opacity(0.08) }
        return SeedTheme.card
    }
}
