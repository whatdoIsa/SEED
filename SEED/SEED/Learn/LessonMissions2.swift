import SwiftUI
import JurinKit

// MARK: - 미션 4: 거래량 폭증 캔들 탭 (레슨 4)

struct TapVolumeSpikeMissionView: View {
    let onSuccess: () -> Void
    @State private var feedback: String?
    @State private var succeeded = false

    private let candles = TapVolumeMissionData.candles
    private let volumes = TapVolumeMissionData.volumes
    private var maxVolume: Int { volumes.max() ?? 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundStyle(SeedTheme.violetOnDark)
                Text("**진짜 움직임**이 시작된 캔들을 탭하세요 — 거래량이 말해줘요")
                    .font(.system(size: 13))
            }
            .foregroundStyle(SeedTheme.inkText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(SeedTheme.ink, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20).padding(.top, 18)

            HStack(alignment: .bottom, spacing: 14) {
                ForEach(Array(candles.enumerated()), id: \.element.id) { index, candle in
                    VStack(spacing: 6) {
                        MiniCandleView(candle: candle,
                                       priceMin: TapVolumeMissionData.priceMin,
                                       priceMax: TapVolumeMissionData.priceMax,
                                       height: 140)
                        RoundedRectangle(cornerRadius: 2)
                            .fill((candle.isBullish ? SeedTheme.up : SeedTheme.down).opacity(0.5))
                            .frame(width: 22,
                                   height: max(CGFloat(volumes[index]) / CGFloat(maxVolume) * 46, 3))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { tap(index) }
                    .allowsHitTesting(!succeeded)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 26)

            if let feedback {
                Text(feedback)
                    .font(.system(size: 14))
                    .foregroundStyle(succeeded ? SeedTheme.violetDeep : SeedTheme.textPrimary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(succeeded ? SeedTheme.violetTint : SeedTheme.card,
                                in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20).padding(.top, 20)
            }

            Spacer()

            if succeeded {
                Button(action: onSuccess) {
                    Text("다음")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20).padding(.bottom, 18)
            }
        }
    }

    private func tap(_ index: Int) {
        if index == TapVolumeMissionData.spikeIndex {
            succeeded = true
            feedback = "맞아요. 저 큰 거래량이 '많은 사람이 이 값에 동의했다'는 표시예요. 거래량 없는 상승은 이만큼 믿을 수 없어요."
        } else if candles[index].isBullish {
            feedback = "오르긴 했지만 거래량이 작아요. 몇 명이 밀어올린 걸 수도 있어요 — 막대가 가장 큰 캔들을 찾아봐요."
        } else {
            feedback = "아래 거래량 막대를 봐요. 유난히 큰 막대가 하나 있죠?"
        }
    }
}

// MARK: - 미션 5: 급락 패닉셀 시나리오 (레슨 5)

struct CrashScenarioMissionView: View {
    let store: SeedStore
    let onSuccess: () -> Void

    private enum Phase: Equatable {
        case running, deciding, result
    }

    @State private var engine = MarketEngine(scenario: .panicCrash())
    @State private var phase: Phase = .running
    @State private var didAutoBuy = false
    @State private var soldInPanic = false
    @State private var entryPrice: Double = 0
    @State private var loop: Task<Void, Never>?

    /// 이 틱에 자동으로 보유가 생긴다 — 급락은 '들고 있을 때' 무섭다.
    private let autoBuyTick = 80

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
                Text("한빛중공업")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("\(engine.lastPrice.formatted())원")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SeedTheme.pnl(Double(engine.lastPrice) - (entryPrice > 0 ? entryPrice : 50_000)))
                    .contentTransition(.numericText())
                Spacer()
                if engine.portfolio.qty > 0 {
                    Text("보유 \(engine.portfolio.qty)주 · 평단 \(Int(engine.portfolio.avgCost).formatted())")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12)

            ChartCanvas(candles: engine.candles, current: engine.currentCandle,
                        unlockLevel: UnlockLevel.all)
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

    @ViewBuilder
    private var bottomCard: some View {
        switch phase {
        case .running:
            HStack(spacing: 8) {
                ProgressView()
                Text(didAutoBuy ? "보유 중… 시장을 지켜보세요" : "곧 100주를 들고 시작해요")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)

        case .deciding:
            VStack(alignment: .leading, spacing: 12) {
                Text("끝없이 떨어질 것 같아요. 어떻게 할까요?")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SeedTheme.inkText)
                Text("지금 팔면 평단 대비 약 \(lossNowPct())% 손실이 확정돼요.")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.inkText.opacity(0.75))
                HStack(spacing: 8) {
                    Button {
                        panicSell()
                        resume()
                    } label: {
                        Text("지금 다 팔기")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(SeedTheme.down, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        resume()
                    } label: {
                        Text("버티기")
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

    private var resultCard: some View {
        let pnl = engine.portfolio.equity(at: engine.lastPrice) - engine.config.initialCash
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "message.circle.fill").font(.system(size: 12))
                Text("코치").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(SeedTheme.violetOnDark)
            HStack {
                Text("시나리오 손익")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.inkText.opacity(0.75))
                Spacer()
                Text("\(pnl >= 0 ? "+" : "")\(pnl.formatted())원")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(pnl >= 0 ? Color(hex: 0xFF8A93) : Color(hex: 0x8FBAFF))
            }
            Text(soldInPanic
                 ? "바닥 근처에서 팔았어요. 그 공포가 패닉셀이에요 — 판 뒤에 가격이 일부 돌아온 걸 보셨죠. 팔 거라면 급락 전에 '원칙'으로 정해두는 거예요."
                 : "버텼고, 회복분을 되찾았어요. 다만 기억해요 — 이번엔 회복하는 시나리오였을 뿐, 항상 돌아오는 건 아니에요. 그래서 '어디서 팔지'를 미리 정해두는 게 손절 원칙이에요.")
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

    private func lossNowPct() -> String {
        guard entryPrice > 0 else { return "0" }
        let pct = (Double(engine.lastPrice) - entryPrice) / entryPrice * 100
        return pct.formatted(.number.precision(.fractionLength(1)))
    }

    private func startLoop() {
        guard loop == nil else { return }
        // 워밍업: 과거 캔들을 그린 상태로 시작 — 빈 차트에 거대 막대가 쌓이는 혼란 방지
        if engine.tick == 0 { engine.advance(ticks: 100) }
        loop = Task {
            while !Task.isCancelled {
                if phase == .running {
                    engine.step()

                    if !didAutoBuy && engine.tick >= autoBuyTick {
                        didAutoBuy = true
                        entryPrice = Double(engine.lastPrice)
                        _ = try? engine.placeMarketOrder(side: .buy, qty: 100)
                        entryPrice = engine.portfolio.avgCost
                    }
                    if engine.pendingDecision != nil {
                        engine.resolveDecision()
                        phase = .deciding
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

    private func panicSell() {
        let qty = engine.portfolio.qty
        guard qty > 0 else { return }
        let avgCostBefore = engine.portfolio.avgCost
        guard let fill = try? engine.placeMarketOrder(side: .sell, qty: qty) else { return }
        soldInPanic = true
        store.record(fill: fill, tag: .fear, symbol: "한빛중공업",
                     avgCostBeforeOrder: avgCostBefore,
                     scenarioId: engine.scenario?.id)
    }
}
