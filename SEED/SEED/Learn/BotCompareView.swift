import SwiftUI
import JurinKit

/// 거장 도장 (⑫, §15) — 거장 5인의 철학·역사·규칙을 배우고,
/// 같은 장에 세워 "전략은 장을 탄다"를 눈으로 확인한다.
struct BotCompareView: View {
    let store: SeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var masterIndex = 0
    @State private var scenario: DojoScenario = .chase
    @State private var run: BotRun?
    @State private var showsProfile = false
    @State private var showsRematch = false

    private var master: MasterProfile { MasterCatalog.all[masterIndex] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("거장 도장")
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

                masterChips
                identityCard
                scenarioChips

                if let run {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(scenario.label)을 \(master.shortName) 봇이 매매한 기록이에요.")
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

                    if scenario == .chase && master.id == "turtle" {
                        comparisonCard(run: run)
                    }

                    if scenario == .chase {
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

                Text("실존 인물의 철학을 단순화해 재현한 교육용 봇 · 수익 보장 아님 · 투자 권유 아님")
                    .font(.system(size: 10))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(SeedTheme.background)
        .task(id: "\(masterIndex)-\(scenario.rawValue)") {
            // 결정론 덕분에 언제 돌려도 같은 결과 — 캐시가 필요 없다
            run = master.run(scenario.preset)
        }
        .sheet(isPresented: $showsProfile) {
            MasterProfileSheet(master: master)
        }
        .fullScreenCover(isPresented: $showsRematch) {
            ChaseRematchView()
        }
    }

    // MARK: 거장 선택

    private var masterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Array(MasterCatalog.all.enumerated()), id: \.element.id) { index, profile in
                    Button {
                        masterIndex = index
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: profile.icon).font(.system(size: 11))
                            Text(profile.shortName).font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(masterIndex == index ? SeedTheme.inverse : SeedTheme.textPrimary)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(masterIndex == index ? SeedTheme.textPrimary : SeedTheme.card,
                                    in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: 어느 장에 세울까

    private var scenarioChips: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("어느 장에 세워볼까요? — 전략은 장을 타요")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SeedTheme.textSecondary)
            HStack(spacing: 6) {
                ForEach(DojoScenario.allCases) { item in
                    Button {
                        scenario = item
                    } label: {
                        Text(item.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(scenario == item ? SeedTheme.inverse : SeedTheme.textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(scenario == item ? SeedTheme.textPrimary : SeedTheme.card,
                                        in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: 거장 아이덴티티 카드

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(SeedTheme.violet).frame(width: 36, height: 36)
                    Image(systemName: master.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(master.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SeedTheme.inkText)
                    Text(master.quote)
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.inkText.opacity(0.7))
                        .lineLimit(2)
                }
                Spacer()
                Text(master.horizon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SeedTheme.violetOnDark)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().stroke(SeedTheme.violetOnDark.opacity(0.6), lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(master.rules.enumerated()), id: \.offset) { _, rule in
                    ruleRow(rule.0, rule.1)
                }
            }
            Button {
                showsProfile = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "book.fill").font(.system(size: 11))
                    Text("\(master.shortName)의 이야기 읽기")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11))
                }
                .foregroundStyle(SeedTheme.violetOnDark)
                .padding(.vertical, 9).padding(.horizontal, 12)
                .background(SeedTheme.violetOnDark.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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

    // MARK: 존버 기준선

    @ViewBuilder
    private func buyAndHoldLine(run: BotRun) -> some View {
        if let first = run.candles.first, let last = run.candles.last, first.close > 0 {
            let holdPct = Double(last.close - first.close) / Double(first.close) * 100
            let botWins = run.returnPct > holdPct
            HStack(spacing: 7) {
                Image(systemName: "hand.raised.fill").font(.system(size: 11))
                Text("그냥 들고만 있었다면 \(holdPct >= 0 ? "+" : "")\(holdPct.formatted(.number.precision(.fractionLength(2))))% — \(botWins ? "이번 장은 \(master.shortName)의 규칙이 나았어요" : "이번 장은 존버가 나았어요. 어떤 전략도 모든 장을 이기진 못해요")")
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(SeedTheme.textSecondary)
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 11))
        }
    }

    // MARK: 매매 일지

    @ViewBuilder
    private func journalSection(run: BotRun) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(master.shortName)의 매매 일지")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
            if run.actions.isEmpty {
                Text(master.id == "templeton"
                     ? "이 장에선 '비관의 극점'이 오지 않아 한 번도 사지 않았어요 — 기준에 맞는 날만 움직이는 게 역발상이에요."
                     : "이번 장에선 한 번도 매매하지 않았어요 — 조건에 맞는 순간이 없으면 거장은 그냥 기다려요. 그것도 규칙이에요.")
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

    // MARK: 나 vs 봇 (레슨 3 기록 — 급등장 × 터틀에서만)

    private func comparisonCard(run: BotRun) -> some View {
        let myLogs = store.scenarioLogs(scenarioId: "scenario.chase-rally")
        let myFirstBuy = myLogs.first { $0.side == .buy }
        let botFirstBuy = run.actions.first { $0.side == .buy }

        return VStack(alignment: .leading, spacing: 10) {
            Text("첫 진입 비교 (레슨 3)")
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
                Text(mine.avgFillPrice > bot.price
                     ? "봇이 먼저(싸게) 탔어요. 공정하게 말하면 — 레슨 3에서 당신에게 주어진 선택지는 급등이 이미 다 보인 고점뿐이었어요. 그게 현실에서 초보가 급등주를 만나는 시점이거든요. 봇은 그보다 앞선 돌파 순간에 기계적으로 반응했고요. 아래 리매치로 같은 조건에서 직접 겨뤄보세요."
                     : "이번엔 당신의 진입이 봇보다 낫거나 비슷했어요. 다만 봇은 백 번 반복해도 똑같이 해냅니다 — 그게 규칙의 힘이에요.")
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

// MARK: - 거장 프로필 시트 (이야기·강한 장·죽는 장·심리 함정)

struct MasterProfileSheet: View {
    let master: MasterProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11).fill(SeedTheme.violet).frame(width: 44, height: 44)
                        Image(systemName: master.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(master.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(SeedTheme.textPrimary)
                        Text(master.quote)
                            .font(.system(size: 12))
                            .foregroundStyle(SeedTheme.textSecondary)
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

                // 일반 String은 마크다운을 해석하지 않으므로 명시적으로 파싱 (줄바꿈 보존)
                Text((try? AttributedString(
                    markdown: master.story,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    ?? AttributedString(master.story))
                    .font(.system(size: 14))
                    .foregroundStyle(SeedTheme.textPrimary)
                    .lineSpacing(6)

                infoCard(icon: "sun.max.fill", tint: SeedTheme.up,
                         title: "강한 장", text: master.strongMarkets)
                infoCard(icon: "cloud.rain.fill", tint: SeedTheme.down,
                         title: "죽는 장", text: master.weakMarkets)
                infoCard(icon: "brain.head.profile", tint: SeedTheme.violetDeep,
                         title: "사람이 무너지는 지점", text: master.mentalTrap)

                Text("이야기는 역사적 사실을 바탕으로 하며, 봇은 해당 철학을 교육용으로 단순화한 재현입니다. 특정 전략의 수익을 보장하지 않아요.")
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.7))
                    .lineSpacing(4)
            }
            .padding(20)
        }
        .background(SeedTheme.background)
        .presentationDetents([.large])
    }

    private func infoCard(icon: String, tint: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .lineSpacing(4)
            }
            Spacer()
        }
        .padding(13)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 13))
    }
}
