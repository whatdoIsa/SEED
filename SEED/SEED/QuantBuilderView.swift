import SwiftUI
import JurinKit

/// 전략 실험실 (퀀트 빌더 v1, §15.2) — 조건 블록을 조립해 시나리오에 백테스트.
/// 출력은 §11.1 원칙대로 통계(수익률·MDD·매매 수)뿐 — 목표가·점 예측은 없다.
struct QuantBuilderView: View {
    let store: SeedStore
    @Environment(\.dismiss) private var dismiss

    @State private var template = 0
    @State private var rsiEntry = 30.0
    @State private var rsiExit = 65.0
    @State private var maShort = 3
    @State private var maLong = 8
    @State private var breakoutLookback = 5
    @State private var breakdownLookback = 3
    @State private var scenarioIndex = 0
    @State private var run: BotRun?
    @State private var isRunning = false

    private let templates = ["RSI 역추세", "이평선 교차", "돌파 추세"]
    private let scenarios: [(name: String, make: () -> ScenarioPreset)] = [
        ("급등장", { .chaseRally() }),
        ("급락장", { .panicCrash() }),
        ("오늘의 장", { DailyMarket.scenario() })
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("전략 실험실")
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
                Text("조건을 조립하고, 감정 없는 규칙이 시나리오에서 어떤 성적을 내는지 확인해요.")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)

                Picker("전략", selection: $template) {
                    ForEach(Array(templates.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(index)
                    }
                }
                .pickerStyle(.segmented)

                parameterCard

                VStack(alignment: .leading, spacing: 8) {
                    Text("어느 장에서 시험할까요?")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SeedTheme.textSecondary)
                    HStack(spacing: 6) {
                        ForEach(Array(scenarios.enumerated()), id: \.offset) { index, item in
                            Button {
                                scenarioIndex = index
                                run = nil
                            } label: {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(scenarioIndex == index ? SeedTheme.inverse : SeedTheme.textPrimary)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(scenarioIndex == index ? SeedTheme.textPrimary : SeedTheme.card,
                                                in: Capsule())
                            }
                        }
                    }
                }

                Button {
                    runBacktest()
                } label: {
                    HStack(spacing: 8) {
                        if isRunning { ProgressView().tint(.white) }
                        Text("백테스트 실행")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isRunning)

                if let run {
                    resultSection(run)
                }

                Text("교육용 백테스트 · 백테스트 우수 ≠ 실전 수익 · 투자 권유 아님")
                    .font(.system(size: 10))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(SeedTheme.background)
    }

    // MARK: 파라미터 (템플릿별)

    @ViewBuilder
    private var parameterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch template {
            case 0:
                paramRow("이만큼 과매도면 사기 (RSI <)") {
                    Slider(value: $rsiEntry, in: 15...40, step: 1)
                } value: { "\(Int(rsiEntry))" }
                paramRow("이만큼 과열되면 팔기 (RSI >)") {
                    Slider(value: $rsiExit, in: 55...85, step: 1)
                } value: { "\(Int(rsiExit))" }
            case 1:
                stepperRow("단기 이평선", value: $maShort, range: 2...6)
                stepperRow("장기 이평선", value: $maLong, range: 7...15)
                Text("단기선이 장기선을 위로 뚫으면 사고, 아래로 뚫으면 팔아요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
            default:
                stepperRow("N캔들 최고가 돌파 시 매수", value: $breakoutLookback, range: 3...10)
                stepperRow("N캔들 최저가 이탈 시 매도", value: $breakdownLookback, range: 2...8)
            }
        }
        .padding(14)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .onChange(of: template) { _, _ in run = nil }
    }

    private func paramRow(_ label: String,
                          @ViewBuilder control: () -> some View,
                          value: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 13)).foregroundStyle(SeedTheme.textPrimary)
                Spacer()
                Text(value()).font(.system(size: 14, weight: .semibold)).foregroundStyle(SeedTheme.violetDeep)
            }
            control()
        }
    }

    private func stepperRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(SeedTheme.textPrimary)
            Spacer()
            Stepper("\(value.wrappedValue)", value: value, in: range)
                .font(.system(size: 14, weight: .semibold))
                .fixedSize()
        }
    }

    // MARK: 실행·결과

    private var currentStrategy: QuantStrategy {
        switch template {
        case 0:
            return QuantStrategy(name: "RSI 역추세",
                                 entry: .rsiBelow(threshold: rsiEntry, period: 6),
                                 exit: .rsiAbove(threshold: rsiExit, period: 6))
        case 1:
            return QuantStrategy(name: "이평선 교차",
                                 entry: .goldenCross(short: maShort, long: maLong),
                                 exit: .deadCross(short: maShort, long: maLong))
        default:
            return QuantStrategy(name: "돌파 추세",
                                 entry: .breakoutHigh(lookback: breakoutLookback),
                                 exit: .breakdownLow(lookback: breakdownLookback))
        }
    }

    private func runBacktest() {
        isRunning = true
        let strategy = currentStrategy
        let scenario = scenarios[scenarioIndex].make()
        Task {
            let result = BotComparison.run(strategy: strategy, scenario: scenario)
            run = result
            isRunning = false
        }
    }

    private func resultSection(_ run: BotRun) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("'\(run.botName)' × \(scenarios[scenarioIndex].name)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)

            TradeMapCanvas(
                candles: run.candles,
                marks: run.actions.map { ($0.candleIndex, $0.price, $0.side) }
            )
            .frame(height: 160)
            .padding(12)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 10) {
                statCard("수익률",
                         "\(run.returnPct >= 0 ? "+" : "")\(run.returnPct.formatted(.number.precision(.fractionLength(2))))%",
                         color: SeedTheme.pnl(run.returnPct))
                statCard("최대 낙폭", "-\(run.maxDrawdownPct.formatted(.number.precision(.fractionLength(1))))%")
                statCard("매매", "\(run.tradeCount)회")
            }

            if run.tradeCount == 0 {
                Text("이 조건은 이 장에서 한 번도 발동하지 않았어요. 조건을 느슨하게 바꿔볼까요?")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 11))
            }
        }
    }

    private func statCard(_ label: String, _ value: String, color: Color = SeedTheme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(SeedTheme.textSecondary)
            Text(value).font(.system(size: 17, weight: .semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
