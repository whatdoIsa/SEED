import SwiftUI
import JurinKit

/// 급등주 추격매수 시나리오 미션 (M3-4) — chaseRally 프리셋을 압축 시간으로 체험.
/// 오버슛에서 결정을 던지고, 평균회귀를 겪게 한 뒤, 선택에 맞는 복기를 준다.
struct ChaseScenarioMissionView: View {
    let store: SeedStore
    let onSuccess: () -> Void

    private enum Phase: Equatable {
        case running
        case deciding
        case dipOffer
        case result
    }

    @State private var engine = MarketEngine(scenario: .chaseRally())
    @State private var phase: Phase = .running
    @State private var decision: ScenarioPreset.DecisionPrompt?
    @State private var waitingForDip = false
    @State private var boughtTag: TradeReasonTag?
    @State private var buyFill: FillResult?
    @State private var loop: Task<Void, Never>?

    /// 눌림 매수 기회를 주는 틱 (평균회귀 진행 중)
    private let dipTick = 470

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11))
                Text("압축 시간: 1캔들 = 1일 · 모의 시나리오")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("D+\(engine.candles.count)일")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(SeedTheme.violetDeep)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20).padding(.top, 14)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("한빛바이오")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("\(engine.lastPrice.formatted())원")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(priceColor)
                    .contentTransition(.numericText())
                Spacer()
                if let fill = buyFill {
                    Text("내 평단 \(Int(fill.avgFillPrice).formatted())원")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12)

            ChartCanvas(
                candles: engine.candles,
                current: engine.currentCandle,
                unlockLevel: UnlockLevel.all
            )
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 14)
            .padding(.top, 6)

            bottomCard
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .task { startLoop() }
        .onDisappear { loop?.cancel() }
    }

    private var priceColor: Color {
        SeedTheme.pnl(Double(engine.lastPrice - 50_000))
    }

    // MARK: 하단 카드 — 상태별 전환

    @ViewBuilder
    private var bottomCard: some View {
        switch phase {
        case .running:
            HStack(spacing: 8) {
                ProgressView()
                Text(waitingForDip ? "기다리는 중… 시장을 지켜보세요" : "시장이 흘러갑니다…")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)

        case .deciding:
            VStack(alignment: .leading, spacing: 12) {
                Text(decision?.prompt ?? "급등이 이어지고 있어요. 어떻게 할까요?")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SeedTheme.inkText)
                Text("모두가 사고 있어요. 지금 100주면 약 \((engine.lastPrice * 100).formatted())원.")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.inkText.opacity(0.75))
                HStack(spacing: 8) {
                    Button {
                        buy(tag: .chase)
                        resume()
                    } label: {
                        Text("지금 사기")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(SeedTheme.up, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        waitingForDip = true
                        resume()
                    } label: {
                        Text("첫 눌림까지 기다리기")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SeedTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(SeedTheme.inkText, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(16)
            .background(SeedTheme.ink, in: RoundedRectangle(cornerRadius: 16))

        case .dipOffer:
            VStack(alignment: .leading, spacing: 12) {
                Text("가격이 많이 내려왔어요. 지금이 첫 눌림이에요.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SeedTheme.inkText)
                HStack(spacing: 8) {
                    Button {
                        buy(tag: .dip)
                        resume()
                    } label: {
                        Text("100주 사기")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(SeedTheme.up, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        resume()
                    } label: {
                        Text("계속 지켜보기")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SeedTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(SeedTheme.inkText, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(16)
            .background(SeedTheme.ink, in: RoundedRectangle(cornerRadius: 16))

        case .result:
            resultCard
        }
    }

    // MARK: 결과 복기

    private var resultCard: some View {
        let pnl = engine.portfolio.unrealizedPnL(at: engine.lastPrice)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "message.circle.fill")
                    .font(.system(size: 12))
                Text("코치")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(SeedTheme.violetOnDark)

            if buyFill != nil {
                HStack {
                    Text("이번 시나리오 손익")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.inkText.opacity(0.75))
                    Spacer()
                    Text("\(Int(pnl) >= 0 ? "+" : "")\(Int(pnl).formatted())원")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(pnl >= 0 ? Color(hex: 0xFF8A93) : Color(hex: 0x8FBAFF))
                }
            }

            Text(resultText)
                .font(.system(size: 14))
                .foregroundStyle(SeedTheme.inkText)
                .lineSpacing(5)

            Button(action: onSuccess) {
                Text("다음")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SeedTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(SeedTheme.inkText, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(SeedTheme.ink, in: RoundedRectangle(cornerRadius: 16))
    }

    private var resultText: String {
        switch boughtTag {
        case .chase:
            return "고점 부근에서 샀어요. 방금 그 조급함이 FOMO예요. 다음엔 첫 눌림을 기다려볼까요? 이 매매는 복기 리포트에 기록해뒀어요."
        case .dip:
            return "잘 참았어요. 급등을 쫓지 않고 눌림에서 샀죠 — 같은 100주인데 훨씬 싸게요. 기다림도 매매예요."
        default:
            return "지켜보기만 했네요. 급등이 제자리로 돌아오는 걸 눈으로 봤어요 — 그게 평균회귀예요. 다음엔 눌림에서 진입을 시도해봐도 좋아요."
        }
    }

    // MARK: 루프·주문

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task {
            while !Task.isCancelled {
                if phase == .running {
                    engine.step()

                    if let pending = engine.pendingDecision {
                        decision = pending
                        engine.resolveDecision()
                        phase = .deciding
                    } else if waitingForDip && engine.tick >= dipTick {
                        waitingForDip = false
                        phase = .dipOffer
                    } else if engine.isScenarioFinished {
                        phase = .result
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(28))
            }
        }
    }

    private func resume() {
        phase = .running
    }

    private func buy(tag: TradeReasonTag) {
        let avgCostBefore = engine.portfolio.avgCost
        guard let fill = try? engine.placeMarketOrder(side: .buy, qty: 100) else { return }
        buyFill = fill
        boughtTag = tag
        store.record(fill: fill, tag: tag, symbol: "한빛바이오",
                     avgCostBeforeOrder: avgCostBefore,
                     scenarioId: engine.scenario?.id)
    }
}
