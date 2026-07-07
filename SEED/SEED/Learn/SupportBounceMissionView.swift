import SwiftUI
import JurinKit

/// 지지·저항 미션 (레슨 8) — 이평선까지 눌린 자리에서 사는 걸 배운다.
/// 배속으로 수십 캔들을 감아 "이평선 지지 후 반등"을 눈으로 보게 하는 게 핵심.
struct SupportBounceMissionView: View {
    let onSuccess: () -> Void

    private enum Phase: Equatable { case running, deciding, result }

    /// 상승 추세 속 눌림 → 지지 반등 시나리오 (미션 전용, 인라인)
    private static func scenario() -> ScenarioPreset {
        ScenarioPreset(
            id: "mission.support",
            seed: 20_260_808,
            initialPrice: 50_000,
            durationTicks: 560,
            anchorPull: 0.13,
            keyframes: [
                .init(tick: 0, value: 50_000),
                .init(tick: 180, value: 55_000),    // 1차 상승
                .init(tick: 280, value: 51_800),    // 눌림 (이평선 근처 — 결정 지점)
                .init(tick: 420, value: 57_500),    // 지지 후 반등
                .init(tick: 560, value: 56_500)
            ],
            overrides: [
                .init(agentId: "TREND", startTick: 60, endTick: 500,
                      params: AgentParams(activity: 0.55, minQty: 40, maxQty: 150))
            ],
            decisions: [
                .init(tick: 275,
                      prompt: "이동평균선까지 눌렸어요.",
                      options: [
                        .init(label: "지지에서 사기", tagRaw: "dip"),
                        .init(label: "관망", tagRaw: "wait")
                      ])
            ],
            timeScaleLabel: "1캔들 = 1일"
        )
    }

    @State private var engine = MarketEngine(scenario: SupportBounceMissionView.scenario())
    @State private var phase: Phase = .running
    @State private var boughtAtSupport = false
    @State private var buyPrice = 0
    @State private var loop: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line").font(.system(size: 11))
                Text("이동평균선(빨강)이 어디서 받쳐주는지 보세요 · 배속")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("D+\(engine.candles.count)")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(SeedTheme.violetDeep)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20).padding(.top, 14)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("한빛전자")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("\(engine.lastPrice.formatted())원")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SeedTheme.pnl(Double(engine.lastPrice - 50_000)))
                    .contentTransition(.numericText())
                Spacer()
                if buyPrice > 0 {
                    Text("내 평단 \(buyPrice.formatted())원")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12)

            // MA5·MA20이 보이도록 전체 해금 레벨로 렌더
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
                Text("시간을 감는 중… 이평선 근처를 지켜보세요")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)

        case .deciding:
            VStack(alignment: .leading, spacing: 12) {
                Text("오르던 가격이 이동평균선까지 눌렸어요. 어떻게 할까요?")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SeedTheme.inkText)
                Text("큰 흐름은 아직 위를 향해 있어요. 이 선이 받쳐줄까요?")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.inkText.opacity(0.75))
                HStack(spacing: 8) {
                    Button {
                        buyHere(atSupport: true)
                        phase = .running
                    } label: {
                        Text("지지에서 사기")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(SeedTheme.up, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        phase = .running
                    } label: {
                        Text("불안해서 관망")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SeedTheme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
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
        let pnl = boughtAtSupport && buyPrice > 0
            ? Double(engine.lastPrice - buyPrice) / Double(buyPrice) * 100 : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "message.circle.fill").font(.system(size: 12))
                Text("코치").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(SeedTheme.violetOnDark)
            if boughtAtSupport {
                HStack {
                    Text("지지 매수 성적")
                        .font(.system(size: 13)).foregroundStyle(SeedTheme.inkText.opacity(0.75))
                    Spacer()
                    Text("\(pnl >= 0 ? "+" : "")\(pnl.formatted(.number.precision(.fractionLength(1))))%")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(pnl >= 0 ? Color(hex: 0xFF8A93) : Color(hex: 0x8FBAFF))
                }
            }
            Text(boughtAtSupport
                 ? "이평선이 받쳐준 자리에서 샀고, 흐름이 이어졌어요. 눌림은 파는 자리가 아니라, 추세가 살아있다면 오히려 태우는 자리일 수 있어요."
                 : "관망했네요. 이평선 근처에서 반등하는 걸 눈으로 봤죠? 다만 지지가 항상 통하는 건 아니에요 — 선을 뚫고 내려가면 흐름이 바뀐 신호예요. 그래서 '선이 깨지면 손절'이 짝을 이뤄요.")
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

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task {
            while !Task.isCancelled {
                if phase == .running {
                    engine.step()
                    if engine.pendingDecision != nil {
                        engine.resolveDecision()
                        phase = .deciding
                    } else if engine.isScenarioFinished {
                        phase = .result
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    private func buyHere(atSupport: Bool) {
        guard let fill = try? engine.placeMarketOrder(side: .buy, qty: 100) else { return }
        boughtAtSupport = atSupport
        buyPrice = Int(fill.avgFillPrice)
    }
}
