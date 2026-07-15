import SwiftUI
import JurinKit

/// 전략 실험실 (퀀트 빌더 v1, §15.2) — 조건 블록을 조립해 시나리오에 백테스트.
/// 출력은 §11.1 원칙대로 통계(수익률·MDD·매매 수)뿐 — 목표가·점 예측은 없다.
struct QuantBuilderView: View {
    let store: SeedStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode = 0            // 0: 기술적 백테스트, 1: 가치 스크리너
    @State private var maxPER = 15.0
    @State private var maxPBR = 1.5
    @State private var minDividend = 0.0
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
    @State private var matrix: [(label: String, run: BotRun)]?
    @State private var strategyName = ""
    @State private var savedNotice = false
    @State private var removedNotice = false
    @State private var deepDive: LessonDef?

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
                Text(mode == 0
                     ? "조건을 조립하고, 감정 없는 규칙이 시나리오에서 어떤 성적을 내는지 확인해요."
                     : "가치 지표로 종목을 걸러내요. 조건에 맞는 종목만 순위로 보여줘요.")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)

                Picker("모드", selection: $mode) {
                    Text("기술적 백테스트").tag(0)
                    Text("가치 스크리너").tag(1)
                }
                .pickerStyle(.segmented)

                if mode == 0 {
                    technicalPanel
                } else {
                    valueScreenerPanel
                }

                Text("교육용 백테스트 · 백테스트 우수 ≠ 실전 수익 · 투자 권유 아님")
                    .font(.system(size: 10))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(SeedTheme.background)
        .fullScreenCover(item: $deepDive) { lesson in
            LessonFlowView(lesson: lesson, store: store)
        }
    }

    // MARK: 기술적 백테스트 패널 (기존)

    @ViewBuilder
    private var technicalPanel: some View {
        Picker("전략", selection: $template) {
            ForEach(Array(templates.enumerated()), id: \.offset) { index, name in
                Text(name).tag(index)
            }
        }
        .pickerStyle(.segmented)

        templateExplainer

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

        // 강건성 검증: 버튼 한 번에 네 개 장 전부
        Button {
            runMatrix()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 13, weight: .semibold))
                Text("모든 장에서 시험 — 장별 성적표")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(SeedTheme.violetDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(SeedTheme.violet.opacity(0.5), lineWidth: 1.2))
        }

        if let matrix {
            matrixSection(matrix)
        }

        arenaEntrySection
    }

    // MARK: 장별 성적표 — 전략의 강건성이 한 눈에

    private func runMatrix() {
        isRunning = true
        let strategy = currentStrategy
        // 백테스트 4회를 버튼 액션에서 동기 실행하면 UI가 그대로 얼어붙는다
        Task.detached(priority: .userInitiated) {
            let rows = DojoScenario.allCases.map { item in
                (item.label, BotComparison.run(strategy: strategy, scenario: item.preset))
            }
            await MainActor.run {
                matrix = rows
                isRunning = false
            }
        }
    }

    private func matrixSection(_ rows: [(label: String, run: BotRun)]) -> some View {
        let best = rows.max { $0.run.returnPct < $1.run.returnPct }
        let worst = rows.min { $0.run.returnPct < $1.run.returnPct }
        return VStack(alignment: .leading, spacing: 9) {
            Text("장별 성적표")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
            HStack {
                Text("장").frame(width: 64, alignment: .leading)
                Spacer()
                Text("수익률").frame(width: 72, alignment: .trailing)
                Text("최대 낙폭").frame(width: 72, alignment: .trailing)
                Text("매매").frame(width: 44, alignment: .trailing)
            }
            .font(.system(size: 11))
            .foregroundStyle(SeedTheme.textSecondary)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SeedTheme.textPrimary)
                        .frame(width: 64, alignment: .leading)
                    Spacer()
                    Text("\(row.run.returnPct >= 0 ? "+" : "")\(row.run.returnPct.formatted(.number.precision(.fractionLength(2))))%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SeedTheme.pnl(row.run.returnPct))
                        .frame(width: 72, alignment: .trailing)
                        .monospacedDigit()
                    Text("-\(row.run.maxDrawdownPct.formatted(.number.precision(.fractionLength(1))))%")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textSecondary)
                        .frame(width: 72, alignment: .trailing)
                        .monospacedDigit()
                    Text("\(row.run.tradeCount)회")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textSecondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 3)
            }
            if let best, let worst, best.label != worst.label {
                Text("\(best.label)에 강하고 \(worst.label)에서 약해요 — 전략은 장을 타요. 어느 장이 올지 모른다는 게 실전의 조건이에요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .lineSpacing(4)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: 아레나 출전 — 이 전략을 7번째 선수로

    private var arenaEntrySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("아레나 출전")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
            if let current = StrategyStore.load() {
                HStack(spacing: 8) {
                    Text("현재 출전: '\(current.name)' — 새로 저장하면 교체돼요.")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                    Spacer()
                    Button {
                        StrategyStore.clear()
                        savedNotice = false
                        removedNotice = true
                    } label: {
                        Text("출전 해제")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SeedTheme.down)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(SeedTheme.down.opacity(0.1), in: Capsule())
                    }
                }
            } else {
                Text("전략에 이름을 붙여 저장하면 아레나에서 거장들과 함께 뜁니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            if removedNotice {
                HStack(spacing: 5) {
                    Image(systemName: "minus.circle.fill").font(.system(size: 11))
                    Text("출전 해제 완료 — 다음 아레나부터 빠집니다")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(SeedTheme.textSecondary)
            }
            HStack(spacing: 8) {
                TextField("전략 이름 (예: 나의 RSI 역추세)", text: $strategyName)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(SeedTheme.background, in: RoundedRectangle(cornerRadius: 10))
                Button {
                    var strategy = currentStrategy
                    let trimmed = strategyName.trimmingCharacters(in: .whitespaces)
                    strategy.name = trimmed.isEmpty ? strategy.name : trimmed
                    StrategyStore.save(strategy)
                    savedNotice = true
                    removedNotice = false
                } label: {
                    Text("저장")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            if savedNotice {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11))
                    Text("저장 완료 — 다음 아레나부터 함께 뜁니다")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(SeedTheme.violetDeep)
            }
        }
        .padding(14)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: 가치 스크리너 패널 (신규 — 6종목 카탈로그를 재무 지표로 필터)

    /// 조건 통과 종목을 저평가 순(PER 낮은 순)으로. §11.1: 점 예측이 아니라 '조건 통과 + 순위'.
    private var screenedSymbols: [(spec: SymbolSpec, per: Double, pbr: Double, yield: Double, price: Int)] {
        SymbolCatalog.all.compactMap { spec in
            guard let f = spec.financials,
                  let per = f.per(at: spec.initialPrice),
                  let pbr = f.pbr(at: spec.initialPrice) else { return nil }
            let yield = f.dividendYieldPct(at: spec.initialPrice) ?? 0
            guard per <= maxPER, pbr <= maxPBR, yield >= minDividend else { return nil }
            return (spec, per, pbr, yield, spec.initialPrice)
        }
        .sorted { $0.per < $1.per }
    }

    @ViewBuilder
    private var valueScreenerPanel: some View {
        let totalWithFinancials = SymbolCatalog.all.filter { $0.financials != nil }.count

        VStack(alignment: .leading, spacing: 12) {
            screenSlider("PER 최대", value: $maxPER, range: 3...80, step: 1,
                         suffix: "배 이하")
            screenSlider("PBR 최대", value: $maxPBR, range: 0.4...8, step: 0.1,
                         suffix: "배 이하", fraction: 1)
            screenSlider("배당수익률 최소", value: $minDividend, range: 0...5, step: 0.5,
                         suffix: "% 이상", fraction: 1)
        }
        .padding(14)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))

        let results = screenedSymbols
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("통과 종목")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Spacer()
                Text("\(results.count) / \(totalWithFinancials)종목")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            if results.isEmpty {
                Text("조건에 맞는 종목이 없어요. 기준을 조금 느슨하게 해볼까요?")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(Array(results.enumerated()), id: \.element.spec.code) { index, r in
                    screenResultRow(rank: index + 1, r: r)
                }
                Text("PER이 낮은 순으로 정렬했어요. 단, 이건 '싸 보이는 순서'일 뿐 — 왜 싼지는 각 종목을 열어 확인하세요. (레슨 7)")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .lineSpacing(4)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 11))
            }
        }
    }

    private func screenSlider(_ label: String, value: Binding<Double>,
                              range: ClosedRange<Double>, step: Double,
                              suffix: String, fraction: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 13)).foregroundStyle(SeedTheme.textPrimary)
                Spacer()
                Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(fraction))))\(suffix)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeedTheme.violetDeep)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func screenResultRow(rank: Int,
                                 r: (spec: SymbolSpec, per: Double, pbr: Double, yield: Double, price: Int)) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SeedTheme.violetDeep)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.spec.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text(r.spec.oneLiner)
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("PER \(r.per.formatted(.number.precision(.fractionLength(1))))배")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("PBR \(r.pbr.formatted(.number.precision(.fractionLength(1)))) · 배당 \(r.yield.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
        }
        .padding(12)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 파라미터 (템플릿별)

    @ViewBuilder
    /// 이 전략이 무슨 아이디어인지 — 통하는 장과 죽는 장까지 정직하게.
    private var templateExplainer: some View {
        let info: (idea: String, works: String, fails: String) = {
            switch template {
            case 0:
                return ("\"떨어질 만큼 떨어졌다\"에 베팅해요. RSI는 최근 오른 힘과 내린 힘의 비율(0~100) — 30 아래면 팔 사람은 이미 판 과매도, 70 위면 과열로 봐요. 내려간 게 제자리로 돌아온다는 평균회귀 아이디어예요.",
                        "횡보장 — 박스 안에서 내려가면 사고 올라가면 파는 게 반복돼요",
                        "강한 하락 추세 — '과매도'가 며칠씩 계속되며 사자마자 더 빠져요")
            case 1:
                return ("추세의 방향 전환을 이평선 두 개로 감지해요. 짧은 선(최근 분위기)이 긴 선(큰 흐름)을 위로 뚫으면 골든크로스(상승 전환), 아래로 뚫으면 데드크로스(하락 전환)예요.",
                        "방향이 분명한 추세장 — 전환을 한 번 잡으면 길게 먹어요",
                        "횡보장 — 두 선이 계속 얽히며 가짜 신호에 사고팔기를 반복해요")
            default:
                return ("\"강한 것은 더 강해진다\"에 베팅해요. 최근 N캔들의 최고가를 뚫는 건 새 수요가 들어왔다는 신호 — 터틀·오닐이 쓰는 돌파 매매의 뼈대예요.",
                        "급등 초입 — 돌파 순간 올라타 추세를 끝까지 타요",
                        "데드캣·횡보 — 가짜 돌파에 타서 손절을 반복해요 (whipsaw)")
            }
        }()
        return VStack(alignment: .leading, spacing: 8) {
            Text(info.idea)
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.textPrimary)
                .lineSpacing(5)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sun.max.fill").font(.system(size: 10))
                    .foregroundStyle(SeedTheme.up)
                    .padding(.top, 2)
                Text(info.works)
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "cloud.rain.fill").font(.system(size: 10))
                    .foregroundStyle(SeedTheme.down)
                    .padding(.top, 2)
                Text(info.fails)
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            Button {
                // 템플릿에 맞는 심화 편으로: 돌파 → 터틀 규칙, 나머지 → 지표 정복
                deepDive = template == 2 ? DeepDiveCatalog.turtle2 : DeepDiveCatalog.quant2
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "book.pages.fill").font(.system(size: 10))
                    Text("더 깊이 배우기 — 심화 시리즈")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(SeedTheme.violetDeep)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeedTheme.violetTint.opacity(0.6), in: RoundedRectangle(cornerRadius: 13))
    }

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
                Text("N이 크면 신호가 드물지만 확실하고, 작으면 잦지만 가짜가 늘어요 — 이 균형이 파라미터 튜닝의 본질이에요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
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
        // MainActor 상속 Task는 메인 스레드를 그대로 막아 스피너가 한 프레임도 못 돈다
        Task.detached(priority: .userInitiated) {
            let result = BotComparison.run(strategy: strategy, scenario: scenario)
            await MainActor.run {
                run = result
                isRunning = false
            }
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

            Text("최대 낙폭은 도중 고점에서 가장 깊이 빠졌던 정도 — 이 전략을 따르며 견뎌야 했을 고통의 크기예요. 수익률이 같다면 낙폭이 작은 쪽이 좋은 전략이에요.")
                .font(.system(size: 11))
                .foregroundStyle(SeedTheme.textSecondary.opacity(0.8))
                .lineSpacing(4)

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
