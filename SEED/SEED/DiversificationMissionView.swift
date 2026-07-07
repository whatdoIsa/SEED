import SwiftUI
import JurinKit

/// 분산 미션 (레슨 6) — 같은 시장 급락을 두 계좌로 동시에 맞는다.
/// 예측(어느 쪽이 덜 다칠까) → 체험(β별로 다르게 맞는 급락) → 반전(숫자로 확인).
struct DiversificationMissionView: View {
    let onSuccess: () -> Void

    private enum Phase: Equatable {
        case predict, running, result
    }

    private struct MissionSymbol {
        let name: String
        let beta: Double
        let engine: MarketEngine
        var entryPrice: Int = 0
    }

    @State private var phase: Phase = .predict
    @State private var pickedDiversified: Bool?
    @State private var symbols: [MissionSymbol] = []
    @State private var crashed = false
    @State private var loop: Task<Void, Never>?

    private let startCash = 10_000_000
    private let crashTick = 400
    private let endTick = 720
    /// 시장 전체 충격 (β=1 기준 -20%)
    private let marketShock = -0.20

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .predict:
                predictStage
            case .running, .result:
                runStage
            }
        }
        .onDisappear { loop?.cancel() }
    }

    // MARK: 1. 예측 — 먼저 걸게 한다

    private var predictStage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("1,000만원을 담습니다.\n어느 쪽이 덜 다칠까요?")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
                .lineSpacing(4)
                .padding(.top, 22)
            Text("곧 시장에 무슨 일이 일어날지는 아무도 몰라요.")
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.textSecondary)
                .padding(.top, 6)

            VStack(spacing: 10) {
                predictChoice(
                    title: "한빛바이오에 전부",
                    subtitle: "가장 화끈한 테마주 몰빵 (β 1.4)",
                    diversified: false
                )
                predictChoice(
                    title: "바이오 + 식품 + 골드 3등분",
                    subtitle: "성격이 다른 세 바구니 (β 1.4 / 0.45 / -0.5)",
                    diversified: true
                )
            }
            .padding(.top, 20)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func predictChoice(title: String, subtitle: String, diversified: Bool) -> some View {
        Button {
            pickedDiversified = diversified
            startSimulation()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
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
                Text("압축 시간 · 두 계좌가 같은 시장을 삽니다")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundStyle(SeedTheme.violetDeep)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20).padding(.top, 14)

            if crashed && phase == .running {
                HStack(spacing: 7) {
                    Image(systemName: "globe.asia.australia.fill").font(.system(size: 12))
                    Text("시장 속보 · 신용 경색 우려 — 시장 전체 급락")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(SeedTheme.down)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(SeedTheme.downTint, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 20).padding(.top, 8)
            }

            // 두 계좌 실시간 비교 — 이 화면의 심장
            HStack(spacing: 10) {
                accountCard(title: "몰빵", value: concentratedEquity, picked: pickedDiversified == false)
                accountCard(title: "3등분 분산", value: diversifiedEquity, picked: pickedDiversified == true)
            }
            .padding(.horizontal, 20).padding(.top, 12)

            VStack(spacing: 6) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, item in
                    symbolRow(item)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12)

            Spacer()

            if phase == .result {
                resultCard
                    .padding(.horizontal, 20).padding(.bottom, 16)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(crashed ? "충격이 계좌를 통과하는 중…" : "평화로운 시장…")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func accountCard(title: String, value: Int, picked: Bool) -> some View {
        let pnl = value - startCash
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SeedTheme.textSecondary)
                if picked {
                    Text("내 선택")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SeedTheme.violetDeep)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(SeedTheme.violetTint, in: Capsule())
                }
            }
            Text("\(value.formatted())원")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
                .contentTransition(.numericText())
            Text("\(pnl >= 0 ? "+" : "")\(pnl.formatted())원")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SeedTheme.pnl(Double(pnl)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .stroke(picked ? SeedTheme.violet.opacity(0.6) : .clear, lineWidth: 1.5))
    }

    private func symbolRow(_ item: MissionSymbol) -> some View {
        let change = item.entryPrice > 0
            ? Double(item.engine.lastPrice - item.entryPrice) / Double(item.entryPrice) * 100
            : 0
        return HStack {
            Text(item.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SeedTheme.textPrimary)
                .frame(width: 76, alignment: .leading)
            Text("β \(item.beta.formatted(.number.precision(.fractionLength(2))))")
                .font(.system(size: 11))
                .foregroundStyle(SeedTheme.textSecondary)
            Spacer()
            Text("\(item.engine.lastPrice.formatted())원")
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.textPrimary)
            Text("\(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(1))))%")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SeedTheme.pnl(change))
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 11))
    }

    private var resultCard: some View {
        let concentrated = concentratedEquity - startCash
        let diversified = diversifiedEquity - startCash
        let pickedBetter = (pickedDiversified == true && diversified > concentrated)
            || (pickedDiversified == false && concentrated > diversified)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "message.circle.fill").font(.system(size: 12))
                Text("코치").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(SeedTheme.violetOnDark)
            Text(pickedBetter
                 ? "맞았어요. 같은 날, 같은 뉴스였는데 두 계좌의 상처가 달랐죠."
                 : "이번엔 예측이 빗나갔어요. 같은 날, 같은 뉴스 — 그런데 두 계좌의 상처가 달랐죠.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SeedTheme.inkText)
            Text("바이오는 시장의 1.4배로 맞았고, 식품은 절반만 맞았고, 골드는 오히려 올랐어요. 이게 상관관계와 β예요.\n\n단, 정직하게 — 분산은 수익을 보장하지 않아요. 흔들림을 줄일 뿐이에요. 시장이 오르는 날엔 몰빵이 부럽습니다. 그게 트레이드오프예요.")
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.inkText.opacity(0.9))
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

    // MARK: 하니스 — 스크립트된 시장 충격을 β별로 맞는 3개 시장

    private var concentratedEquity: Int {
        guard let bio = symbols.first else { return startCash }
        guard bio.entryPrice > 0 else { return startCash }
        let qty = startCash / bio.entryPrice
        let cash = startCash - qty * bio.entryPrice
        return cash + qty * bio.engine.lastPrice
    }

    private var diversifiedEquity: Int {
        guard symbols.count == 3, symbols.allSatisfy({ $0.entryPrice > 0 }) else { return startCash }
        let alloc = startCash / 3
        var equity = startCash - alloc * 3
        for item in symbols {
            let qty = alloc / item.entryPrice
            equity += (alloc - qty * item.entryPrice) + qty * item.engine.lastPrice
        }
        return equity
    }

    private func startSimulation() {
        // 미션 전용 설정: 뉴스·갭·거래일 끄고, 앵커 추종을 높여 충격이 빠르게 반영되게
        func missionConfig(base: EngineConfig) -> EngineConfig {
            var config = base
            config.newsTickProbability = 0
            config.openingGapRange = 0...0
            config.candlesPerDay = 0
            config.meanReversion = 0.05
            return config
        }
        let specs: [(code: String, seed: UInt64)] = [("HBB", 61), ("HBF", 62), ("GLD", 63)]
        symbols = specs.compactMap { item in
            guard let spec = SymbolCatalog.spec(code: item.code) else { return nil }
            let engine = MarketEngine(seed: item.seed,
                                      initialPrice: spec.initialPrice,
                                      config: missionConfig(base: spec.config))
            engine.advance(ticks: 200)
            var symbol = MissionSymbol(name: spec.name,
                                       beta: spec.config.marketBeta,
                                       engine: engine)
            symbol.entryPrice = engine.lastPrice
            return symbol
        }
        phase = .running
        loop = Task {
            while !Task.isCancelled {
                guard phase == .running, let first = symbols.first else { return }
                for item in symbols { item.engine.step() }

                if !crashed && first.engine.tick >= crashTick {
                    crashed = true
                    // 시장 전체 충격: 각 종목이 β만큼 다르게 맞는다
                    for item in symbols {
                        item.engine.fairAnchor *= (1 + marketShock * item.beta)
                    }
                }
                if first.engine.tick >= endTick {
                    phase = .result
                    return
                }
                try? await Task.sleep(for: .milliseconds(22))
            }
        }
    }
}
