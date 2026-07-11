import SwiftUI

/// 레슨 요약 — 완료한 레슨의 핵심 3줄. 복습 비용을 4분에서 15초로.
enum LessonSummaries {
    static let all: [String: [String]] = [
        "lesson.candle": [
            "캔들 하나 = 시가·종가·최고·최저 네 숫자의 그림",
            "빨강(양봉)은 올랐다, 파랑(음봉)은 내렸다 — 몸통이 길수록 힘이 셌다",
            "캔들은 예쁜 그림이 아니라 실제 체결들의 요약이다",
        ],
        "lesson.orderbook": [
            "화면의 가격은 '마지막 체결가'일 뿐 — 내가 사는 가격이 아니다",
            "호가창엔 사려는 줄과 팔려는 줄이 서 있고, 시장가는 그 줄을 먹으며 체결된다",
            "급하게 큰 수량을 사면 슬리피지(표시가와의 차이)가 커진다",
        ],
        "lesson.chase": [
            "급등이 '확실해 보이는' 순간은 대개 이미 고점 근처다",
            "추격 매수의 상대는 초입에 산 사람들의 차익 실현 물량이다",
            "사기 전에 물어라: 나는 신호를 봤나, 아니면 남들의 흥분을 봤나",
        ],
        "lesson.volume": [
            "가격은 소수가 움직여도 거래량은 못 속인다 — 움직임의 진심",
            "거래량 없는 상승은 의심하고, 거래량 실린 돌파는 무게가 다르다",
            "거래량 급증 = 많은 사람의 의견이 바뀌는 순간",
        ],
        "lesson.crash": [
            "급락의 공포 속 투매는 대부분 바닥 근처에서 나온다",
            "공포에 파는 사람과 줍는 사람의 하루가 갈린다",
            "미리 정한 계획(손절선)이 없으면 공포가 대신 결정한다",
        ],
        "lesson.diversify": [
            "시장 뉴스는 모든 종목이 함께 맞는다 — 좋은 종목도 같이 빠진다",
            "종목마다 시장에 반응하는 크기(β)가 다르다: 테마주 1.4배, 방어주 절반, 금은 반대",
            "성격이 다른 것들을 섞으면 계좌의 흔들림이 줄어든다",
        ],
        "lesson.valuetrap": [
            "싸다/비싸다는 가격이 아니라 이익 대비(PER)로 잰다",
            "낮은 PER엔 낮은 이유가 있을 수 있다 — 가치 함정",
            "가치투자는 싼 걸 사는 게 아니라 가격보다 가치가 큰 걸 사는 것",
        ],
        "lesson.support": [
            "이동평균선은 출렁임을 걷어낸 큰 흐름이다",
            "추세 속 눌림이 이평선에서 받쳐지면(지지) 태우는 자리일 수 있다",
            "지지는 항상 통하지 않는다 — 선이 깨지면 손절이 짝이다",
        ],
        "lesson.stoploss": [
            "손절은 사기 전에 정하는 규칙이다 — 물린 뒤의 '조금만 더'는 희망이지 계획이 아니다",
            "-50%를 복구하려면 +100%가 필요하다 — 크게 잃지 않는 게 이기는 길",
            "손절은 지는 걸 인정하는 게 아니라 작게 져서 다음 기회를 남기는 것",
        ],
        "lesson.patience": [
            "시장의 대부분은 횡보다 — 그리고 지루함이 계좌를 갉는다",
            "방향 없는 장의 잦은 매매는 수수료에 계좌를 내어주는 일",
            "가만히 있는 것도 포지션이다 — 조건이 없으면, 하지 않는다",
        ],
        "lesson.sizing": [
            "계좌를 무너뜨리는 건 타이밍보다 크기 — 몰빵이 문제다",
            "사기 전에 물어라: 이번에 틀리면 얼마나 잃는가?",
            "남긴 현금은 손실 방어이자 바닥에서 주울 다음 기회다",
        ],
        "lesson.graduation": [
            "여기서 얻은 것: 시장의 언어, 세 겹의 방어(손절·분산·수량), 복기 루틴",
            "여기서 못 배운 것: 실돈의 심리, 진짜 뉴스, 제도 디테일, 시장의 어두운 면",
            "실전은 잃어도 되는 소액부터 — 이 앱은 평생 연습장이다",
        ],
        // 심화 시리즈
        "deep.turtle.why": [
            "1983년, 초보 23명이 2주 규칙 교육만으로 전설이 됐다",
            "차이를 만든 건 규칙이 아니라 규칙을 끝까지 지키는 힘",
            "규칙이 어려운 게 아니라, 아플 때 지켜야 해서 어렵다",
        ],
        "deep.turtle.rules": [
            "돌파에 사고, N(평균 변동폭)으로 수량을 정한다 — 한 번에 계좌의 1%만 위험",
            "이기고 있을 때만 추가(피라미딩), 물타기는 금지",
            "출구는 둘: 2N 손절 또는 추세 종료 — 먼저 오는 쪽으로 무조건",
        ],
        "deep.turtle.mind": [
            "기대값 = 승률×평균이익 − 패율×평균손실. 승률 40%도 돈을 번다",
            "터틀의 일상은 손절의 연속 — 대박 몇 번이 수익의 전부",
            "손절은 실패가 아니라 월세 같은 비용이다",
        ],
        "deep.quant.what": [
            "퀀트 = 느낌을 숫자 규칙으로 바꿔 과거로 시험하는 것",
            "가설 → 규칙화 → 백테스트 → 판정, 나쁘면 미련 없이 폐기",
            "퀀트의 미덕은 나쁜 아이디어를 빨리 죽이는 것",
        ],
        "deep.quant.indicators": [
            "RSI는 최근 힘겨루기의 점수판 (30 과매도 / 70 과열)",
            "이평선은 위치(위/아래)와 교차(골든/데드크로스)로 읽는다",
            "모든 지표는 예언이 아니라 요약 — 가치는 정확함이 아니라 일관됨",
        ],
        "deep.quant.traps": [
            "과최적화: 파라미터를 조금 바꿨는데 성적이 무너지면 의심하라",
            "한 가지 장에서만 통한 전략은 여름옷이다 — 네 계절 전부 시험하라",
            "수수료·슬리피지를 빼먹은 백테스트는 마찰 없는 세상의 성적표다",
        ],
    ]
}

/// 완료 레슨 탭 → 핵심 3줄 먼저, 원하면 전체 다시 보기.
struct LessonSummarySheet: View {
    let lesson: LessonDef
    let onReread: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("핵심만 다시")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SeedTheme.violetDeep)
                    Text(lesson.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array((LessonSummaries.all[lesson.id] ?? []).enumerated()),
                        id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SeedTheme.violetDeep)
                            .frame(width: 20, height: 20)
                            .background(SeedTheme.violetTint, in: Circle())
                        Text(line)
                            .font(.system(size: 14))
                            .foregroundStyle(SeedTheme.textPrimary)
                            .lineSpacing(4)
                    }
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))

            Button {
                dismiss()
                onReread()
            } label: {
                Text("전체 다시 보기")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(SeedTheme.violet.opacity(0.5), lineWidth: 1.2))
            }
            Spacer()
        }
        .padding(20)
        .background(SeedTheme.background)
        .presentationDetents([.medium])
    }
}
