import SwiftUI
import JurinKit

/// 자유 매매 리매치 — 레슨 3과 같은 급등 장을, 이번엔 매 순간 사고팔 수 있는 상태로.
/// 레슨 3은 일부러 고점에서만 선택지를 줬다(대본 함정). 여기선 조건이 봇과 같으므로
/// 첫 진입 비교가 비로소 공정해진다. 기록은 이 화면 안에서만 쓰고 버린다.
struct ChaseRematchView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case running, result }

    @State private var engine = MarketEngine(scenario: .chaseRally())
    @State private var phase: Phase = .running
    @State private var myTrades: [(candleIndex: Int, price: Double, side: Side)] = []
    @State private var loop = LiveLoop()

    var body: some View {
        VStack(spacing: 0) {
            header
            if phase == .running {
                liveChart
                tradeButtons
            } else {
                resultView
            }
        }
        .background(SeedTheme.background)
        .task { startLoop() }
        .onDisappear { loop.cancel() }
    }

    // MARK: 헤더

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SeedTheme.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(SeedTheme.card, in: Circle())
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("리매치 · 같은 장, 자유 매매")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("이번엔 언제든 사고팔 수 있어요 — 봇과 같은 조건")
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            Spacer()
            if phase == .running {
                Button {
                    loop.speed = loop.speed == 1 ? 2 : 1
                } label: {
                    Text("\(loop.speed)x")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SeedTheme.inverse)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(SeedTheme.textPrimary, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 진행 — 차트 + 상시 매매 버튼

    private var liveChart: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(engine.lastPrice.formatted())원")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(SeedTheme.pnl(Double(engine.lastPrice - 50_000)))
                    .contentTransition(.numericText())
                Spacer()
                if engine.portfolio.qty > 0 {
                    Text("보유 \(engine.portfolio.qty)주 · 평단 \(Int(engine.portfolio.avgCost).formatted())원")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 6)

            ChartCanvas(candles: engine.candles, current: engine.currentCandle,
                        unlockLevel: UnlockLevel.all)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 14)
                .padding(.top, 6)
        }
    }

    private var tradeButtons: some View {
        LiveTradeButtons(engine: engine) { side, fill in
            myTrades.append((engine.candles.count, fill.avgFillPrice, side))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: 결과 — 이번엔 공정한 비교

    private var resultView: some View {
        let bot = BotComparison.runTurtle(scenario: .chaseRally())
        let myEquity = engine.portfolio.equity(at: engine.lastPrice)
        let myReturnPct = Double(myEquity - engine.config.initialCash)
            / Double(engine.config.initialCash) * 100
        let myFirstBuy = myTrades.first { $0.side == .buy }
        let botFirstBuy = bot.actions.first { $0.side == .buy }

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("공정한 비교")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                    .padding(.top, 8)
                Text("이번엔 당신도 매 순간 살 수 있었어요 — 같은 조건에서의 기록이에요.")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("내 매매 지도")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    TradeMapCanvas(candles: engine.candles, marks: myTrades)
                        .frame(height: 150)
                }
                .padding(12)
                .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))

                HStack(spacing: 10) {
                    resultStat("내 수익률",
                               "\(myReturnPct >= 0 ? "+" : "")\(myReturnPct.formatted(.number.precision(.fractionLength(2))))%",
                               color: SeedTheme.pnl(myReturnPct))
                    resultStat("터틀 봇",
                               "\(bot.returnPct >= 0 ? "+" : "")\(bot.returnPct.formatted(.number.precision(.fractionLength(2))))%",
                               color: SeedTheme.pnl(bot.returnPct))
                }

                entryComparison(myFirstBuy: myFirstBuy, botFirstBuy: botFirstBuy)

                Button {
                    dismiss()
                } label: {
                    Text("닫기")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 13))
                }
                .padding(.top, 4)

                Text("교육용 · 수익 보장 아님")
                    .font(.system(size: 10))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func entryComparison(
        myFirstBuy: (candleIndex: Int, price: Double, side: Side)?,
        botFirstBuy: BotAction?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("첫 진입")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
            if let mine = myFirstBuy {
                entryRow("나", "\(mine.candleIndex)번째 캔들 · \(Int(mine.price).formatted())원")
            } else {
                entryRow("나", "진입 안 함")
            }
            if let bot = botFirstBuy {
                entryRow("터틀 봇", "\(bot.candleIndex)번째 캔들 · \(Int(bot.price).formatted())원")
            }
            Text(coachLine(myFirstBuy: myFirstBuy, botFirstBuy: botFirstBuy))
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.violetDeep)
                .lineSpacing(4)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 11))
        }
        .padding(14)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func coachLine(
        myFirstBuy: (candleIndex: Int, price: Double, side: Side)?,
        botFirstBuy: BotAction?
    ) -> String {
        guard let bot = botFirstBuy else {
            return "봇이 이번엔 진입하지 않았어요."
        }
        guard let mine = myFirstBuy else {
            return "이번엔 안 탔군요 — 급등을 그냥 보내는 것도 선택이에요. 다만 봇은 돌파 규칙이 신호를 주면 망설임 없이 탑니다."
        }
        if mine.price < bot.price {
            return "봇보다 싸게 탔어요! 다만 한 가지 — 봇은 이 진입을 백 번 반복해도 똑같이 하지만, 사람의 감은 다음 판에 다를 수 있어요. 그 차이가 규칙의 힘이에요."
        }
        if mine.candleIndex <= bot.candleIndex {
            return "봇과 비슷한 시점에 탔네요. 돌파 초입을 스스로 알아본 거예요 — 레슨 3의 교훈이 몸에 붙고 있어요."
        }
        return "이번에도 봇이 먼저 탔어요. 자유롭게 살 수 있어도, 급등이 '확실해 보일 때'는 이미 초입이 지난 뒤인 경우가 많아요. 그게 사람의 눈과 규칙의 차이예요."
    }

    private func entryRow(_ name: String, _ detail: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
                .frame(width: 60, alignment: .leading)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.textSecondary)
            Spacer()
        }
    }

    private func resultStat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(SeedTheme.textSecondary)
            Text(value).font(.system(size: 17, weight: .semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 진행 루프

    private func startLoop() {
        loop.speed = 2 // 리매치 기본 속도
        loop.start(engine: engine) { phase = .result }
    }
}
