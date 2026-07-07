import SwiftUI
import JurinKit

/// 손절 미션 (레슨 9) — 같은 하락을 손절 있는 계좌 vs 없는 계좌로 나눠 겪는다.
/// "작게 지는 습관"이 계좌를 살린다는 걸 두 계좌의 갈라짐으로 보여준다.
struct StopLossMissionView: View {
    let onSuccess: () -> Void

    private enum Phase: Equatable { case predict, running, result }

    @State private var phase: Phase = .predict
    @State private var myAccountHasStop: Bool?
    @State private var stopEngine = MarketEngine(scenario: .deadCatBounce())
    @State private var holdEngine = MarketEngine(scenario: .deadCatBounce())
    @State private var stopTriggered = false
    @State private var buyPrice = 0
    @State private var loop: Task<Void, Never>?

    private let stopLossPct = 0.08   // -8%에서 손절

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .predict: predictStage
            case .running, .result: runStage
            }
        }
        .onDisappear { loop?.cancel() }
    }

    // MARK: 1. 예측 — 손절선을 걸까?

    private var predictStage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("이 종목을 100주 삽니다.\n손절선을 걸까요?")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
                .lineSpacing(4)
                .padding(.top, 22)
            Text("앞으로 시장이 어떻게 될지는 아무도 몰라요.")
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.textSecondary)
                .padding(.top, 6)

            VStack(spacing: 10) {
                predictChoice(
                    title: "-8%에서 손절 걸기",
                    subtitle: "그 값에 닿으면 감정 없이 자동 매도",
                    hasStop: true
                )
                predictChoice(
                    title: "손절 없이 버티기",
                    subtitle: "언젠간 오르겠지, 끝까지 들고 간다",
                    hasStop: false
                )
            }
            .padding(.top, 20)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func predictChoice(title: String, subtitle: String, hasStop: Bool) -> some View {
        Button {
            myAccountHasStop = hasStop
            startSimulation()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(SeedTheme.textPrimary)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(SeedTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(SeedTheme.band, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: 2·3. 체험과 결과

    private var runStage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill").font(.system(size: 11))
                Text("두 계좌가 같은 하락을 겪습니다")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("D+\(stopEngine.candles.count)").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(SeedTheme.violetDeep)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20).padding(.top, 14)

            if stopTriggered && phase == .running {
                HStack(spacing: 7) {
                    Image(systemName: "scissors").font(.system(size: 12))
                    Text("손절 발동 · -8%에서 잘라냈어요")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(SeedTheme.down)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(SeedTheme.downTint, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 20).padding(.top, 8)
            }

            HStack(spacing: 10) {
                accountCard(title: "손절 있음", equity: stopEquity, picked: myAccountHasStop == true)
                accountCard(title: "손절 없음", equity: holdEquity, picked: myAccountHasStop == false)
            }
            .padding(.horizontal, 20).padding(.top, 12)

            Spacer()

            if phase == .result {
                resultCard.padding(.horizontal, 20).padding(.bottom, 16)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("하락이 두 계좌를 통과하는 중…")
                        .font(.system(size: 13)).foregroundStyle(SeedTheme.textSecondary)
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func accountCard(title: String, equity: Int, picked: Bool) -> some View {
        let pnl = equity - 10_000_000
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(SeedTheme.textSecondary)
                if picked {
                    Text("내 선택")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(SeedTheme.violetDeep)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(SeedTheme.violetTint, in: Capsule())
                }
            }
            Text("\(equity.formatted())원")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(SeedTheme.textPrimary)
                .contentTransition(.numericText())
            Text("\(pnl >= 0 ? "+" : "")\(pnl.formatted())원")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(SeedTheme.pnl(Double(pnl)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .stroke(picked ? SeedTheme.violet.opacity(0.6) : .clear, lineWidth: 1.5))
    }

    private var resultCard: some View {
        let stopPnl = stopEquity - 10_000_000
        let holdPnl = holdEquity - 10_000_000
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "message.circle.fill").font(.system(size: 12))
                Text("코치").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(SeedTheme.violetOnDark)
            Text("손절이 \(( holdPnl - stopPnl).formatted())원을 지켰어요.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SeedTheme.inkText)
            Text("손절 없는 계좌는 반등을 기다리다 더 깊이 물렸어요. '언젠간 오르겠지'는 계획이 아니라 희망이에요.\n\n손절은 지는 걸 인정하는 게 아니라, 작게 져서 다음 기회를 남기는 규칙이에요. 크게 잃지 않는 게 결국 이기는 길이에요.")
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.inkText.opacity(0.9))
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

    // MARK: 두 계좌 평가액

    private var stopEquity: Int { stopEngine.portfolio.equity(at: stopEngine.lastPrice) }
    private var holdEquity: Int { holdEngine.portfolio.equity(at: holdEngine.lastPrice) }

    private func startSimulation() {
        // 두 엔진 모두 같은 시드(deadCatBounce)라 동일한 시장. 워밍업 후 100주 매수.
        for engine in [stopEngine, holdEngine] {
            engine.advance(ticks: 100)
            _ = try? engine.placeMarketOrder(side: .buy, qty: 100)
        }
        buyPrice = Int(stopEngine.portfolio.avgCost)
        phase = .running
        loop = Task {
            while !Task.isCancelled {
                guard phase == .running else { return }
                stopEngine.step()
                holdEngine.step()

                // 손절 계좌: 평단 대비 -8% 닿으면 전량 매도 (한 번)
                if !stopTriggered, stopEngine.portfolio.qty > 0,
                   Double(stopEngine.lastPrice) <= Double(buyPrice) * (1 - stopLossPct) {
                    stopTriggered = true
                    _ = try? stopEngine.placeMarketOrder(side: .sell, qty: stopEngine.portfolio.qty)
                }

                if stopEngine.isScenarioFinished {
                    phase = .result
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }
}
