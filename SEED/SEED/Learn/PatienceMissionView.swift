import SwiftUI
import JurinKit

/// 인내 미션 (레슨 10) — 방향 없는 횡보 장에서 지루함의 유혹을 견딘다.
/// 자유 매매가 열려 있지만, 안 하는 게 이기는 판. 결과는 수수료가 말해준다.
struct PatienceMissionView: View {
    let onSuccess: () -> Void

    private enum Phase: Equatable { case running, result }

    @State private var engine = MarketEngine(scenario: .sideways())
    @State private var phase: Phase = .running
    @State private var tradeCount = 0
    @State private var loop: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "hourglass").font(.system(size: 11))
                Text("아무 일도 없는 장 · 매매는 자유예요")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("D+\(engine.candles.count)/30")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(SeedTheme.violetDeep)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20).padding(.top, 14)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(engine.lastPrice.formatted())원")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                    .contentTransition(.numericText())
                Spacer()
                if tradeCount > 0 {
                    Text("매매 \(tradeCount)회 · 수수료 \(engine.portfolio.feesPaid.formatted())원")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 10)

            ChartCanvas(candles: engine.candles, current: engine.currentCandle,
                        unlockLevel: UnlockLevel.all)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 14)
                .padding(.top, 6)

            if phase == .result {
                resultCard
                    .padding(.horizontal, 20).padding(.bottom, 16)
            } else {
                HStack(spacing: 8) {
                    Button {
                        trade(side: .buy)
                    } label: {
                        Text("100주 사기")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(SeedTheme.up, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if engine.portfolio.qty > 0 {
                        Button {
                            trade(side: .sell)
                        } label: {
                            Text("전량 팔기")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(SeedTheme.down, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .animation(.snappy(duration: 0.25), value: engine.portfolio.qty > 0)
            }
        }
        .task { startLoop() }
        .onDisappear { loop?.cancel() }
    }

    private var resultCard: some View {
        let pnl = engine.portfolio.equity(at: engine.lastPrice) - engine.config.initialCash
        let fees = engine.portfolio.feesPaid
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "message.circle.fill").font(.system(size: 12))
                Text("코치").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(SeedTheme.violetOnDark)
            HStack {
                Text("30일 결과")
                    .font(.system(size: 13)).foregroundStyle(SeedTheme.inkText.opacity(0.75))
                Spacer()
                Text("\(pnl >= 0 ? "+" : "")\(pnl.formatted())원")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(pnl >= 0 ? Color(hex: 0xFF8A93) : Color(hex: 0x8FBAFF))
            }
            Text(coachText(pnl: pnl, fees: fees))
                .font(.system(size: 14))
                .foregroundStyle(SeedTheme.inkText)
                .lineSpacing(5)
            Button(action: onSuccess) {
                Text("다음")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SeedTheme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(SeedTheme.inkText, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(SeedTheme.ink, in: RoundedRectangle(cornerRadius: 16))
    }

    private func coachText(pnl: Int, fees: Int) -> String {
        if tradeCount == 0 {
            return "한 번도 안 눌렀네요 — 완벽한 인내예요. 방향 없는 장에서 아무것도 안 한 사람이 이 장의 승자예요. 이 감각을 기억하세요: 조건이 없으면, 하지 않는다."
        }
        if pnl < 0 {
            return "매매 \(tradeCount)회, 수수료로만 \(fees.formatted())원이 나갔어요. 방향 없는 장에서 잦은 매매는 수수료에 계좌를 조금씩 내어주는 일이에요. 지루함은 신호가 아니에요."
        }
        return "이번엔 벌었네요(+\(pnl.formatted())원). 다만 솔직하게 — 방향 없는 장에서의 수익은 실력보다 운에 가까워요. 수수료 \(fees.formatted())원은 확실히 나갔고요. 백 번 반복하면 수수료가 이겨요."
    }

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task {
            while !Task.isCancelled {
                guard phase == .running else { return }
                engine.step()
                if engine.pendingDecision != nil { engine.resolveDecision() }
                if engine.isScenarioFinished {
                    phase = .result
                    return
                }
                try? await Task.sleep(for: .milliseconds(18))
            }
        }
    }

    private func trade(side: Side) {
        let qty = side == .buy ? 100 : engine.portfolio.qty
        guard qty > 0, (try? engine.placeMarketOrder(side: side, qty: qty)) != nil else { return }
        tradeCount += 1
    }
}
