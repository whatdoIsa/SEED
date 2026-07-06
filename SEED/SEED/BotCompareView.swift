import SwiftUI
import JurinKit

/// 나 vs 터틀 봇 (⑫, §15) — 같은 급등 시나리오를 감정 없는 규칙이 매매하면 어떻게 되는가.
struct BotCompareView: View {
    let store: SeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var run: BotRun?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("나 vs 터틀 봇")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SeedTheme.textSecondary)
                    }
                }

                identityCard

                if let run {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("레슨 3과 같은 급등 시나리오를 봇이 매매한 기록이에요.")
                            .font(.system(size: 13))
                            .foregroundStyle(SeedTheme.textSecondary)
                        TradeMapCanvas(
                            candles: run.candles,
                            marks: run.actions.map { ($0.candleIndex, $0.price, $0.side) }
                        )
                        .frame(height: 170)
                        .padding(12)
                        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
                    }

                    HStack(spacing: 10) {
                        statCard("수익률",
                                 "\(run.returnPct >= 0 ? "+" : "")\(run.returnPct.formatted(.number.precision(.fractionLength(2))))%",
                                 color: SeedTheme.pnl(run.returnPct))
                        statCard("매매", "\(run.tradeCount)회")
                        statCard("최대 낙폭", "-\(run.maxDrawdownPct.formatted(.number.precision(.fractionLength(1))))%")
                    }

                    comparisonCard(run: run)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("봇이 시나리오를 매매하는 중…")
                            .font(.system(size: 13))
                            .foregroundStyle(SeedTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }

                Text("교육용 전략 · 수익 보장 아님 · 백테스트 우수 ≠ 실전 수익")
                    .font(.system(size: 10))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(SeedTheme.background)
        .task {
            // 결정론 덕분에 언제 돌려도 같은 결과 — 캐시가 필요 없다
            run = BotComparison.runTurtle(scenario: .chaseRally())
        }
    }

    // MARK: 봇 아이덴티티 카드 (§15.3 — 아키타입 + 시간지평 배지 + 규칙)

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(SeedTheme.violet).frame(width: 36, height: 36)
                    Image(systemName: "tortoise.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("터틀 봇 · 추세추종형")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SeedTheme.inkText)
                    Text("\"예측하지 않는다. 추세를 따라간다.\"")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.inkText.opacity(0.7))
                }
                Spacer()
                Text("단기")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SeedTheme.violetOnDark)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().stroke(SeedTheme.violetOnDark.opacity(0.6), lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 4) {
                ruleRow("진입", "최근 5캔들 최고가 돌파 시 매수")
                ruleRow("추가", "0.5×변동폭(ATR) 유리해질 때마다 +1유닛, 최대 4")
                ruleRow("청산", "3캔들 최저가 이탈 또는 평단 −2×ATR 손절")
            }
        }
        .padding(15)
        .background(SeedTheme.ink, in: RoundedRectangle(cornerRadius: 15))
    }

    private func ruleRow(_ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SeedTheme.violetOnDark)
                .frame(width: 30, alignment: .leading)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(SeedTheme.inkText.opacity(0.85))
        }
    }

    // MARK: 나 vs 봇 비교

    private func comparisonCard(run: BotRun) -> some View {
        let myLogs = store.scenarioLogs(scenarioId: "scenario.chase-rally")
        let myFirstBuy = myLogs.first { $0.side == .buy }
        let botFirstBuy = run.actions.first { $0.side == .buy }

        return VStack(alignment: .leading, spacing: 10) {
            Text("첫 진입 비교")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
            if let mine = myFirstBuy {
                compareRow(name: "나",
                           detail: "\(Int(mine.avgFillPrice).formatted())원 · \(mine.reasonTag.label)",
                           highlight: false)
            } else {
                Text("레슨 3에서 산 기록이 없어요 — 기다리기를 골랐거나 아직 안 했어요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            if let bot = botFirstBuy {
                compareRow(name: "터틀 봇",
                           detail: "\(Int(bot.price).formatted())원 · 돌파 규칙",
                           highlight: true)
            }
            if let mine = myFirstBuy, let bot = botFirstBuy {
                let gap = Int(mine.avgFillPrice - bot.price)
                Text(gap > 0
                     ? "봇이 \(gap.formatted())원 먼저(싸게) 탔어요. 봇은 급등의 '초입 돌파'에 반응했고, 사람은 급등이 눈에 보인 뒤에 탔기 때문이에요."
                     : "이번엔 당신의 진입이 봇보다 낫거나 비슷했어요. 다만 봇은 이 결과를 백 번 반복해도 똑같이 해냅니다 — 그게 규칙의 힘이에요.")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .lineSpacing(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 11))
            }
        }
        .padding(15)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func compareRow(name: String, detail: String, highlight: Bool) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(highlight ? SeedTheme.violetDeep : SeedTheme.textPrimary)
                .frame(width: 60, alignment: .leading)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.textPrimary)
            Spacer()
        }
    }

    private func statCard(_ label: String, _ value: String, color: Color = SeedTheme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(SeedTheme.textSecondary)
            Text(value).font(.system(size: 17, weight: .semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(SeedTheme.background, in: RoundedRectangle(cornerRadius: 12))
    }
}
