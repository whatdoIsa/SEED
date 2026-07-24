import SwiftUI

/// 용어사전 — 앱 곳곳의 낯선 단어를 한 곳에서, 쉬운 말로.
/// "어렵다"의 절반은 용어 장벽이다. 레슨을 다시 읽는 대신 막힌 단어만 해소한다.

struct GlossaryTerm: Identifiable {
    let term: String
    let definition: String
    var id: String { term }
}

enum Glossary {
    static let sections: [(category: String, terms: [GlossaryTerm])] = [
        ("차트 읽기", [
            .init(term: "캔들", definition: "일정 시간의 가격 움직임을 한 개의 몸통+꼬리로 요약한 그림. 시작 가격(시가), 끝 가격(종가), 그 사이의 최고가·최저가 네 가지가 담겨 있어요."),
            .init(term: "양봉 / 음봉", definition: "시가보다 종가가 높으면 양봉(빨강, 올랐다), 낮으면 음봉(파랑, 내렸다). 몸통이 길수록 그 시간의 힘이 셌다는 뜻이에요."),
            .init(term: "거래량", definition: "그 시간 동안 실제로 사고팔린 주식의 수. 가격은 몇 명이서도 움직일 수 있지만, 거래량은 많은 사람이 참여했다는 증거라 '움직임의 진심'을 보여줘요."),
            .init(term: "이동평균선", definition: "최근 N일 종가의 평균을 매일 이어 그린 선. 하루하루의 출렁임을 걷어내고 큰 흐름(방향)만 남겨요. 5일선은 최근 분위기, 20일선은 한 달의 흐름."),
            .init(term: "지지 / 저항", definition: "가격이 내려오다 자꾸 멈추는 자리(지지), 올라가다 자꾸 막히는 자리(저항). 많은 사람이 '이 가격이면 사자/팔자'라고 생각하는 지점에서 생겨요."),
            .init(term: "돌파", definition: "최근 N일 최고가를 넘어서는 것. 그 가격에도 사겠다는 새 수요가 나타났다는 신호로, 추세 시작의 후보예요. 단, 가짜 돌파도 많아요."),
            .init(term: "횡보", definition: "방향 없이 좁은 범위를 오르내리는 장. 지루하지만 시장의 대부분은 횡보예요. 이때 잦은 매매는 수수료만 갉아먹기 쉬워요."),
            .init(term: "데드캣 바운스", definition: "급락 후의 반짝 반등. '죽은 고양이도 높은 데서 떨어지면 튀어오른다'는 뜻으로, 반등이 바닥 신호가 아닐 수 있다는 경고예요."),
        ]),
        ("주문과 체결", [
            .init(term: "호가창", definition: "지금 사겠다는 주문(매수호가)과 팔겠다는 주문(매도호가)이 가격별로 줄 서 있는 판. 화면의 가격 뒤에 있는 진짜 시장이에요."),
            .init(term: "시장가 주문", definition: "가격을 정하지 않고 '지금 당장' 사거나 파는 주문. 즉시 체결되지만, 줄 서 있는 물량을 순서대로 먹어서 표시가보다 불리하게 체결될 수 있어요."),
            .init(term: "지정가 주문", definition: "'이 가격이면 사겠다/팔겠다'고 가격을 정해 걸어두는 주문. 그 가격이 올 때까지 기다리고, 안 오면 체결되지 않아요."),
            .init(term: "슬리피지", definition: "주문 버튼을 누른 순간의 표시가와 실제 체결가의 차이. 시장가 주문이 호가 물량을 먹으며 생겨요. 급할수록 커지는 보이지 않는 비용."),
            .init(term: "미체결", definition: "지정가 주문이 아직 체결되지 않고 대기 중인 상태. 취소하기 전까지 살아 있어요."),
            .init(term: "체결강도", definition: "최근 체결 중 사자 주도(위로 때린 것)와 팔자 주도의 비율. 100%보다 크면 사는 쪽이 더 급하다는 뜻."),
            .init(term: "수수료 / 거래세", definition: "매매마다 내는 비용. 이 앱은 실제 규정을 본떠 매수 0.015%, 매도 0.015%+세금 0.18%를 떼요. 잦은 매매일수록 쌓이는 마찰비예요."),
            .init(term: "상한가 / 하한가", definition: "하루에 오르내릴 수 있는 한계(기준가의 ±30%). 그 밖의 가격으론 주문 자체가 안 돼요."),
            .init(term: "동시호가", definition: "장이 열릴 때 주문만 모았다가 하나의 가격으로 한꺼번에 체결하는 방식. 밤새 쌓인 주문들의 균형점을 찾는 절차예요."),
            .init(term: "기준가", definition: "전일 종가. 오늘의 등락률(%)과 상·하한가를 계산하는 기준이에요."),
        ]),
        ("내 계좌", [
            .init(term: "평단 (평균단가)", definition: "내가 산 주식들의 평균 매수 가격. 여러 번 나눠 샀다면 전부 합쳐 평균 낸 값으로, 손익의 기준선이에요."),
            .init(term: "평가손익 / 확정손익", definition: "평가손익은 아직 팔지 않은 주식의 '지금 팔면' 손익 — 숫자일 뿐 내 돈이 아니에요. 확정손익은 실제로 팔아서 결정된 손익."),
            .init(term: "손절", definition: "'여기까지 내려오면 판다'를 사기 전에 미리 정하고, 닿으면 감정 없이 파는 것. 작게 져서 다음 기회를 남기는 규칙이에요."),
            .init(term: "익절", definition: "이익이 난 상태에서 파는 것. '어디서 팔지'도 사기 전에 정해두는 게 규칙 매매예요."),
            .init(term: "물타기", definition: "떨어진 주식을 더 사서 평단을 낮추는 것. 평단은 내려가지만 지는 포지션에 돈을 더 넣는 행동이라, 거장들은 대부분 금지해요."),
            .init(term: "피라미딩", definition: "물타기의 반대 — 이기고 있는 포지션에만 추가 매수. 터틀의 방식이에요."),
            .init(term: "분산", definition: "성격이 다른 여러 종목에 나눠 담는 것. 시장 전체가 빠지는 날의 충격을 줄여줘요. '계란을 한 바구니에 담지 말라.'"),
            .init(term: "현금 포지션", definition: "아무것도 사지 않고 현금으로 있는 것도 하나의 선택이에요. 방향 없는 장에선 가장 좋은 포지션일 때가 많아요."),
        ]),
        ("지표와 전략", [
            .init(term: "RSI", definition: "최근 오른 힘과 내린 힘의 비율을 0~100으로 나타낸 점수판. 30 아래면 과매도(팔 사람은 대충 팔았다), 70 위면 과열로 읽어요. 예언이 아니라 최근의 요약이에요."),
            .init(term: "골든크로스 / 데드크로스", definition: "짧은 이평선이 긴 이평선을 위로 뚫으면 골든크로스(상승 전환 신호), 아래로 뚫으면 데드크로스. 최근 분위기가 큰 흐름을 이겼다는 확인이에요."),
            .init(term: "변동폭 (N, ATR)", definition: "이 종목이 하루에 보통 얼마나 움직이는지의 평균. 터틀은 이 N으로 살 수량과 손절선을 정해요 — 출렁임이 큰 종목은 적게 사는 식으로."),
            .init(term: "기대값", definition: "승률 × 평균이익 − 패율 × 평균손실. 승률 40%여도 이길 때 크게 이기면 돈을 벌어요. 승률만 보는 건 반쪽짜리 계산이에요."),
            .init(term: "최대 낙폭 (MDD)", definition: "도중 고점에서 가장 깊이 빠졌던 정도. 그 전략을 따르며 견뎌야 했을 고통의 크기라, 수익률이 같다면 낙폭 작은 쪽이 좋은 전략이에요."),
            .init(term: "백테스트", definition: "규칙을 과거 데이터에 돌려 성적을 확인하는 것. '이 규칙이 말이 되는가'까지만 알려줘요 — 과거는 힌트지 보증이 아니에요."),
            .init(term: "과최적화", definition: "파라미터를 과거 데이터에 너무 꼭 맞춘 것. 그 과거에만 완벽하고 새로운 장에선 무너져요. 숫자를 조금 바꿔도 성적이 비슷해야 튼튼한 전략이에요."),
            .init(term: "추세추종 / 역추세", definition: "추세추종은 '강한 것이 더 강해진다'에, 역추세는 '내려간 것은 돌아온다'에 베팅해요. 정반대 철학이고, 각각 통하는 장이 달라요."),
        ]),
        ("기업 가치", [
            .init(term: "PER", definition: "지금 주가가 회사 1년 이익의 몇 배인지. PER 10이면 이익 10년치 = 주가. 낮으면 '이익 대비 싸다'지만, 싼 데는 이유가 있을 수 있어요(가치 함정)."),
            .init(term: "PBR", definition: "주가가 회사 순자산(청산 가치)의 몇 배인지. 1 아래면 장부상 자산보다 싸게 거래된다는 뜻."),
            .init(term: "EPS", definition: "주당순이익 — 회사의 1년 이익을 주식 수로 나눈 것. 한 주가 벌어들이는 돈이에요."),
            .init(term: "배당수익률", definition: "1년 배당금을 지금 주가로 나눈 비율. 은행 이자처럼 보유만으로 받는 현금의 수익률이에요."),
            .init(term: "시가총액", definition: "주가 × 전체 주식 수 = 회사 전체의 시장 가격. 회사 크기를 비교하는 기본 단위예요."),
            .init(term: "안전마진", definition: "추정한 가치보다 충분히 싸게 사서, 계산이 좀 틀려도 살아남을 여유를 확보하는 것. 그레이엄 가치투자의 심장이에요."),
            .init(term: "베타 (β)", definition: "시장 전체가 1 움직일 때 이 종목이 얼마나 움직이는지. β 1.4는 시장보다 크게, 0.5는 절반만, 마이너스는 반대로 움직인다는 뜻이에요."),
        ]),
        ("ETF·분산투자", [
            .init(term: "ETF", definition: "여러 종목을 담은 바구니를 1좌 단위로 주식처럼 사고파는 상품(상장지수펀드). 소액으로 분산할 수 있는 게 첫 번째 초능력이에요."),
            .init(term: "지수 (인덱스)", definition: "여러 종목의 가격을 하나의 숫자로 요약한 시장의 체온계. 코스피가 대표적이고, 지수 ETF는 이 체온계를 따라가는 바구니예요."),
            .init(term: "NAV (순자산가치)", definition: "바구니 안의 전부를 지금 시세로 팔면 1좌당 얼마인가 — ETF의 진짜 가치예요. 구성 종목 가격이 움직이면 실시간으로 따라 움직여요."),
            .init(term: "운용보수 (TER)", definition: "ETF를 굴리는 연간 비용. 통장이 아니라 NAV에서 매일 조금씩 빠져나가 '보이지 않는 월세'라 불러요. 같은 지수라면 싼 쪽이 이겨요."),
            .init(term: "괴리율", definition: "ETF의 시장가와 NAV(진짜 가치)의 어긋난 정도. 프리미엄(+)에 사면 바가지를 쓰는 셈이라, 사기 전에 확인하는 습관이 필요해요."),
            .init(term: "자산배분", definition: "주식·금·현금처럼 성격이 다른 자산을 비율을 정해 섞는 것. 종목 수가 아니라 낮은 상관관계가 계좌의 흔들림을 줄여줘요."),
            .init(term: "적립식 (DCA)", definition: "일정 금액을 정기적으로 나눠 사는 방법. 쌀 때 많이, 비쌀 때 적게 자동으로 사져요. 진짜 힘은 하락장에서도 시장을 떠나지 않게 하는 것."),
            .init(term: "리밸런싱", definition: "쏠린 비율을 원래대로 되돌리는 것 — 오른 걸 팔고 내린 걸 사게 돼요. 감정과 반대로 행동하는 규칙이 구조에 내장된 장치예요."),
        ]),
    ]
}

struct GlossaryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [(category: String, terms: [GlossaryTerm])] {
        guard !query.isEmpty else { return Glossary.sections }
        return Glossary.sections.compactMap { section in
            let hits = section.terms.filter {
                $0.term.localizedCaseInsensitiveContains(query)
                    || $0.definition.localizedCaseInsensitiveContains(query)
            }
            return hits.isEmpty ? nil : (section.category, hits)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(filtered, id: \.category) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.category)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SeedTheme.violetDeep)
                            ForEach(section.terms) { term in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(term.term)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(SeedTheme.textPrimary)
                                    Text(term.definition)
                                        .font(.system(size: 13))
                                        .foregroundStyle(SeedTheme.textSecondary)
                                        .lineSpacing(4)
                                }
                                .padding(13)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 13))
                            }
                        }
                    }
                    if filtered.isEmpty {
                        Text("'\(query)'에 맞는 용어가 없어요.")
                            .font(.system(size: 13))
                            .foregroundStyle(SeedTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(16)
                // 하단 플로팅 검색바가 마지막 카드를 가리지 않게
                .padding(.bottom, 64)
            }
            .background(SeedTheme.background)
            .navigationTitle("용어사전")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "용어 검색")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton { dismiss() }
                }
            }
        }
    }
}
