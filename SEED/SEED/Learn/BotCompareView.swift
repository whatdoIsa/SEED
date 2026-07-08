import SwiftUI
import JurinKit

/// 나 vs 거장 봇 (⑫, §15) — 같은 급등 시나리오를 서로 다른 철학의 봇이 매매하면 어떻게 되는가.
/// 추세추종(터틀)과 가치투자(반대 철학)를 골라 비교한다.
struct BotCompareView: View {
    let store: SeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var archetype: BotArchetype = .turtle
    @State private var run: BotRun?
    @State private var showsRematch = false

    /// 봇 아키타입 — 철학·시간지평·규칙·아이콘을 한 곳에.
    enum BotArchetype: String, CaseIterable, Identifiable {
        case turtle, value
        var id: String { rawValue }

        var pickerLabel: String { self == .turtle ? "추세추종" : "가치투자" }
        var name: String { self == .turtle ? "터틀 봇 · 추세추종형" : "그레이엄 봇 · 가치투자형" }
        var icon: String { self == .turtle ? "tortoise.fill" : "building.columns.fill" }
        var philosophy: String {
            self == .turtle ? "\"예측하지 않는다. 추세를 따라간다.\""
                            : "\"남들이 던질 때 줍고, 열광할 때 판다.\""
        }
        var horizon: String { self == .turtle ? "단기" : "장기" }
        var rules: [(String, String)] {
            self == .turtle
                ? [("진입", "최근 5캔들 최고가 돌파 시 매수"),
                   ("추가", "0.5×변동폭(ATR) 유리해질 때마다 +1유닛, 최대 4"),
                   ("청산", "3캔들 최저가 이탈 또는 평단 −2×ATR 손절")]
                : [("진입", "내재가치 추정보다 3.5% 이상 쌀 때 매수"),
                   ("보유", "가치가 회복될 때까지 버틴다"),
                   ("청산", "내재가치보다 4% 이상 비싸지면 전량 매도")]
        }
        var ruleShort: String { self == .turtle ? "돌파 규칙" : "저평가 진입" }
        var compareInsight: (_ botCheaper: Bool) -> String {
            switch self {
            case .turtle:
                return { $0
                    ? "봇이 먼저(싸게) 탔어요. 공정하게 말하면 — 레슨 3에서 당신에게 주어진 선택지는 급등이 이미 다 보인 고점뿐이었어요. 그게 현실에서 초보가 급등주를 만나는 시점이거든요. 봇은 그보다 앞선 돌파 순간에 기계적으로 반응했고요. 아래 리매치로 같은 조건에서 직접 겨뤄보세요."
                    : "이번엔 당신의 진입이 봇보다 낫거나 비슷했어요. 다만 봇은 백 번 반복해도 똑같이 해냅니다 — 그게 규칙의 힘이에요." }
            case .value:
                return { _ in
                    "가치투자 봇은 급등을 아예 쫓지 않아요. 가격이 내재가치 밑으로 빠지는 순간만 기다렸다 줍죠. 추세추종과 정반대 시점에 움직이는 걸 보세요." }
            }
        }
        func run() -> BotRun {
            self == .turtle
                ? BotComparison.runTurtle(scenario: .chaseRally())
                : BotComparison.runValue(scenario: .chaseRally())
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("나 vs 거장 봇")
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

                Picker("봇", selection: $archetype) {
                    ForEach(BotArchetype.allCases) { Text($0.pickerLabel).tag($0) }
                }
                .pickerStyle(.segmented)

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

                    buyAndHoldLine(run: run)

                    journalSection(run: run)

                    comparisonCard(run: run)

                    Button {
                        showsRematch = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.trianglehead.counterclockwise")
                                .font(.system(size: 14, weight: .semibold))
                            Text("같은 장, 직접 다시 겪기")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 13))
                    }
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
        .task(id: archetype) {
            // 결정론 덕분에 언제 돌려도 같은 결과 — 캐시가 필요 없다
            run = archetype.run()
        }
        .fullScreenCover(isPresented: $showsRematch) {
            ChaseRematchView()
        }
    }

    // MARK: 봇 아이덴티티 카드 (§15.3 — 아키타입 + 시간지평 배지 + 규칙)

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(SeedTheme.violet).frame(width: 36, height: 36)
                    Image(systemName: archetype.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(archetype.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SeedTheme.inkText)
                    Text(archetype.philosophy)
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.inkText.opacity(0.7))
                }
                Spacer()
                Text(archetype.horizon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SeedTheme.violetOnDark)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().stroke(SeedTheme.violetOnDark.opacity(0.6), lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(archetype.rules.enumerated()), id: \.offset) { _, rule in
                    ruleRow(rule.0, rule.1)
                }
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

    // MARK: 존버 기준선 — 봇이 항상 이기는 건 아니라는 정직한 비교

    @ViewBuilder
    private func buyAndHoldLine(run: BotRun) -> some View {
        if let first = run.candles.first, let last = run.candles.last, first.close > 0 {
            let holdPct = Double(last.close - first.close) / Double(first.close) * 100
            let botWins = run.returnPct > holdPct
            HStack(spacing: 7) {
                Image(systemName: "hand.raised.fill").font(.system(size: 11))
                Text("그냥 들고만 있었다면 \(holdPct >= 0 ? "+" : "")\(holdPct.formatted(.number.precision(.fractionLength(2))))% — \(botWins ? "이번엔 봇의 규칙이 나았어요" : "이번엔 존버가 나았어요. 봇이 항상 이기는 건 아니에요")")
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(SeedTheme.textSecondary)
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 11))
        }
    }

    // MARK: 매매 일지 — 왜 그때 샀는가

    @ViewBuilder
    private func journalSection(run: BotRun) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("봇의 매매 일지")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
            if run.actions.isEmpty {
                Text("이번 장에선 한 번도 매매하지 않았어요 — 조건에 맞는 순간이 없으면 봇은 그냥 기다려요. 그것도 규칙이에요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .lineSpacing(4)
            } else {
                ForEach(Array(run.actions.enumerated()), id: \.offset) { _, action in
                    journalRow(action)
                }
            }
        }
        .padding(15)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func journalRow(_ action: BotAction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(action.side == .buy ? "매수" : "매도")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(action.side == .buy ? SeedTheme.up : SeedTheme.down,
                            in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(action.candleIndex)번째 캔들 · \(Int(action.price).formatted())원")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text(action.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .lineSpacing(3)
            }
            Spacer()
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
                compareRow(name: archetype.pickerLabel + " 봇",
                           detail: "\(Int(bot.price).formatted())원 · \(archetype.ruleShort)",
                           highlight: true)
            } else {
                Text("이 봇은 이번 시나리오에서 한 번도 진입하지 않았어요 — 조건에 맞는 순간이 없었던 거예요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            if let mine = myFirstBuy, let bot = botFirstBuy {
                Text(archetype.compareInsight(mine.avgFillPrice > bot.price))
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
                .frame(width: 72, alignment: .leading)
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
