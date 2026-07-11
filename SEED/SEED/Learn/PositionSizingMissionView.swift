import SwiftUI
import JurinKit

/// 자금 관리 미션 (레슨 11) — 같은 하락을 몰빵 계좌 vs 절반 계좌로 겪는다.
/// 타이밍이 같아도 크기가 운명을 가른다. 손절 미션과 같은 두-계좌 구조.
struct PositionSizingMissionView: View {
    let onSuccess: () -> Void

    private enum Phase: Equatable { case predict, running, result }

    @State private var phase: Phase = .predict
    @State private var myChoiceAllIn: Bool?
    @State private var allInEngine = MarketEngine(scenario: .deadCatBounce())
    @State private var halfEngine = MarketEngine(scenario: .deadCatBounce())
    @State private var loop: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .predict: predictStage
            case .running, .result: runStage
            }
        }
        .onDisappear { loop?.cancel() }
    }

    // MARK: 1. 선택

    private var predictStage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("좋아 보이는 종목이 있어요.\n얼마나 살까요?")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
                .lineSpacing(4)
                .padding(.top, 22)
            Text("타이밍은 같아요 — 크기만 다릅니다.")
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.textSecondary)
                .padding(.top, 6)

            VStack(spacing: 10) {
                choice(title: "전 재산 몰빵",
                       subtitle: "확신 있으니까 1,000만원 전부",
                       allIn: true)
                choice(title: "절반만",
                       subtitle: "틀릴 수 있으니 500만원 + 현금 500만원",
                       allIn: false)
            }
            .padding(.top, 20)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func choice(title: String, subtitle: String, allIn: Bool) -> some View {
        Button {
            myChoiceAllIn = allIn
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
                Image(systemName: "scalemass.fill").font(.system(size: 11))
                Text("같은 종목 · 같은 타이밍 · 크기만 다르게")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("D+\(allInEngine.candles.count)").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(SeedTheme.violetDeep)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20).padding(.top, 14)

            HStack(spacing: 10) {
                accountCard(title: "몰빵 계좌", engine: allInEngine, picked: myChoiceAllIn == true)
                accountCard(title: "절반 계좌", engine: halfEngine, picked: myChoiceAllIn == false)
            }
            .padding(.horizontal, 20).padding(.top, 12)

            Spacer()

            if phase == .result {
                resultCard.padding(.horizontal, 20).padding(.bottom, 16)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("같은 하락이 두 계좌를 통과하는 중…")
                        .font(.system(size: 13)).foregroundStyle(SeedTheme.textSecondary)
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func equity(_ engine: MarketEngine) -> Int {
        engine.portfolio.equity(at: engine.lastPrice)
    }

    private func accountCard(title: String, engine: MarketEngine, picked: Bool) -> some View {
        let value = equity(engine)
        let pnl = value - engine.config.initialCash
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
            Text("\(value.formatted())원")
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
        let allInPnl = equity(allInEngine) - allInEngine.config.initialCash
        let halfPnl = equity(halfEngine) - halfEngine.config.initialCash
        let halfCash = halfEngine.portfolio.cash
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "message.circle.fill").font(.system(size: 12))
                Text("코치").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(SeedTheme.violetOnDark)
            Text("같은 판단, 같은 타이밍 — 손실은 \(allInPnl.formatted())원 vs \(halfPnl.formatted())원.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SeedTheme.inkText)
            Text("절반 계좌엔 두 가지가 남았어요: 절반의 손실, 그리고 **현금 \(halfCash.formatted())원** — 바닥에서 주울 수 있는 다음 기회요.\n\n사기 전에 물으세요. \"이번에 틀리면 얼마나 잃는가?\" 그 답이 감당되는 수량이 올바른 수량이에요. 터틀은 이 답을 계좌의 1%로 정했어요.")
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

    private func startSimulation() {
        // 같은 시드 = 같은 시장. 워밍업 후 몰빵/절반 매수.
        for engine in [allInEngine, halfEngine] {
            engine.advance(ticks: 100)
        }
        let price = max(allInEngine.lastPrice, 1)
        _ = try? allInEngine.placeMarketOrder(side: .buy, qty: max(1, 9_800_000 / price))
        _ = try? halfEngine.placeMarketOrder(side: .buy, qty: max(1, 4_900_000 / price))
        phase = .running
        loop = Task {
            while !Task.isCancelled {
                guard phase == .running else { return }
                allInEngine.step()
                halfEngine.step()
                if allInEngine.pendingDecision != nil { allInEngine.resolveDecision() }
                if halfEngine.pendingDecision != nil { halfEngine.resolveDecision() }
                if allInEngine.isScenarioFinished {
                    phase = .result
                    return
                }
                try? await Task.sleep(for: .milliseconds(18))
            }
        }
    }
}
