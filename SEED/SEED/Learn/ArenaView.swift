import SwiftUI
import JurinKit

/// 아레나 (거장 도장 2단계) — 아무도 본 적 없는 무작위 장에서 나 vs 거장 5인.
/// 거장들은 같은 시드 시장을 결정론으로 미리 완주해두고, 캔들이 닫힐 때마다
/// 그 시점의 평가액으로 라이브 순위가 갈린다. 전적은 기기에 쌓인다.
struct ArenaView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case running, result }

    // 대결 상태 — 스탬프 하나가 장 전체를 결정한다
    @State private var stamp = Int.random(in: 10_000_000...99_999_999)
    @State private var engine: MarketEngine
    @State private var botRuns: [(profile: MasterProfile, run: BotRun)] = []
    @State private var phase: Phase = .running
    @State private var myTrades = 0
    @State private var loop = LiveLoop()

    init() {
        let initialStamp = Int.random(in: 10_000_000...99_999_999)
        _stamp = State(initialValue: initialStamp)
        _engine = State(initialValue: MarketEngine(
            scenario: DailyMarket.scenario(stamp: initialStamp, id: "arena.\(initialStamp)")))
    }

    private var preset: ScenarioPreset {
        DailyMarket.scenario(stamp: stamp, id: "arena.\(stamp)")
    }
    private var totalCandles: Int { preset.durationTicks / engine.config.ticksPerCandle }
    private var myEquity: Int { engine.portfolio.equity(at: engine.lastPrice) }
    private var myReturnPct: Double {
        Double(myEquity - engine.config.initialCash) / Double(engine.config.initialCash) * 100
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if phase == .running {
                liveBody
            } else {
                resultBody
            }
        }
        .background(SeedTheme.background)
        .task { startMatch() }
        .onDisappear { loop.cancel() }
    }

    // MARK: 헤더

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill").font(.system(size: 12))
                Text("아레나").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(SeedTheme.violetDeep)
            Text(ArenaRecord.summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SeedTheme.textSecondary)
            Spacer()
            if phase == .running {
                Text("D+\(engine.candles.count)/\(totalCandles)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .monospacedDigit()
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(SeedTheme.card, in: Circle())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: 진행

    private var liveBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(engine.lastPrice.formatted())원")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                    .contentTransition(.numericText())
                Spacer()
                if engine.portfolio.qty > 0 {
                    Text("\(engine.portfolio.qty)주 보유")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
            }
            .padding(.horizontal, 16)

            ChartCanvas(candles: engine.candles, current: engine.currentCandle,
                        unlockLevel: UnlockLevel.all)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 14)
                .padding(.top, 16) // 첫 캔들이 헤더에 붙지 않게

            liveStandings
                .padding(.horizontal, 16)
                .padding(.top, 8)

            SpeedControls(loop: loop)
                .padding(.horizontal, 16).padding(.top, 8)

            LiveTradeButtons(engine: engine) { _, _ in myTrades += 1 }
                .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    /// 라이브 순위 — 캔들이 닫힐 때마다 그 시점 평가액으로 정렬
    private var liveStandings: some View {
        let rows = currentStandings()
        return VStack(spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(index == 0 ? SeedTheme.violetDeep : SeedTheme.textSecondary)
                        .frame(width: 14)
                    Image(systemName: row.icon).font(.system(size: 10))
                        .foregroundStyle(row.isMe ? SeedTheme.violetDeep : SeedTheme.textSecondary)
                        .frame(width: 14)
                    Text(row.name)
                        .font(.system(size: 12, weight: row.isMe ? .bold : .medium))
                        .foregroundStyle(row.isMe ? SeedTheme.violetDeep : SeedTheme.textPrimary)
                    Spacer()
                    Text("\(row.returnPct >= 0 ? "+" : "")\(row.returnPct.formatted(.number.precision(.fractionLength(2))))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SeedTheme.pnl(row.returnPct))
                        .monospacedDigit()
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(row.isMe ? SeedTheme.violetTint : SeedTheme.card,
                            in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private struct StandingRow {
        /// ForEach 식별자 — 이름은 사용자 전략명이 거장·'나'와 겹칠 수 있어 못 쓴다
        let key: String
        let name: String
        let icon: String
        let returnPct: Double
        let isMe: Bool
    }

    private func currentStandings() -> [StandingRow] {
        let candleIndex = engine.candles.count
        var rows = [StandingRow(key: "me", name: "나", icon: "person.fill",
                                returnPct: myReturnPct, isMe: true)]
        for entry in botRuns {
            // 봇의 같은 시점 평가액 (완주 곡선에서 조회)
            let curve = entry.run.equityCurve
            let equity = curve.isEmpty ? entry.run.startCash
                : curve[min(max(candleIndex - 1, 0), curve.count - 1)]
            let pct = Double(equity - entry.run.startCash) / Double(entry.run.startCash) * 100
            rows.append(StandingRow(key: entry.profile.id,
                                    name: entry.profile.shortName,
                                    icon: entry.profile.icon,
                                    returnPct: pct, isMe: false))
        }
        return rows.sorted { $0.returnPct > $1.returnPct }
    }

    // MARK: 결과

    private var resultBody: some View {
        let rows = currentStandings()
        let myRank = (rows.firstIndex { $0.isMe } ?? (rows.count - 1)) + 1
        let pattern = DailyMarket.pattern(stamp: stamp)

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(myRank == 1 ? "우승! 🏆" : "\(myRank)위")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(SeedTheme.textPrimary)
                    .padding(.top, 6)
                Text("이번 장은 '\(pattern.revealName)'이었어요")
                    .font(.system(size: 14))
                    .foregroundStyle(SeedTheme.textSecondary)

                VStack(spacing: 5) {
                    ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
                        HStack(spacing: 8) {
                            Text(medal(for: index))
                                .font(.system(size: 14))
                                .frame(width: 24)
                            Image(systemName: row.icon).font(.system(size: 11))
                                .foregroundStyle(row.isMe ? SeedTheme.violetDeep : SeedTheme.textSecondary)
                                .frame(width: 16)
                            Text(row.name)
                                .font(.system(size: 14, weight: row.isMe ? .bold : .medium))
                                .foregroundStyle(row.isMe ? SeedTheme.violetDeep : SeedTheme.textPrimary)
                            Spacer()
                            Text("\(row.returnPct >= 0 ? "+" : "")\(row.returnPct.formatted(.number.precision(.fractionLength(2))))%")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SeedTheme.pnl(row.returnPct))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(row.isMe ? SeedTheme.violetTint : SeedTheme.card,
                                    in: RoundedRectangle(cornerRadius: 11))
                    }
                }

                AICoachCard(
                    cacheKey: "arena.\(stamp)",
                    fingerprint: "\(myRank)-\(myTrades)",
                    prompt: arenaPrompt(rows: rows, myRank: myRank),
                    maxTokens: 200
                )

                Text(resultInsight(rows: rows, myRank: myRank))
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .lineSpacing(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 11))

                Button {
                    newMatch()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                        Text("다시 겨루기 — 새로운 장")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 13))
                }

                Text("교육용 대결 · 한 판의 순위엔 운이 커요 — 전적이 쌓여야 스타일이 보여요")
                    .font(.system(size: 10))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func medal(for index: Int) -> String {
        switch index {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return "\(index + 1)위"
        }
    }

    private func arenaPrompt(rows: [StandingRow], myRank: Int) -> String {
        let pattern = DailyMarket.pattern(stamp: stamp)
        var lines = ["거장 봇들과의 모의 대결이 끝났어. 결과 해설을 두세 문장으로. 데이터:"]
        lines.append("- 이번 장의 패턴: \(pattern.revealName)")
        lines.append("- 내 순위: \(myRank)위 / \(rows.count)명, 내 매매 \(myTrades)회")
        for (index, row) in rows.enumerated() {
            lines.append("- \(index + 1)위 \(row.name): \(row.returnPct >= 0 ? "+" : "")\(row.returnPct.formatted(.number.precision(.fractionLength(2))))%")
        }
        lines.append("이 장의 성격과 승자의 철학이 왜 맞았는지, 내가 배울 점 하나를 짚어줘.")
        return lines.joined(separator: "\n")
    }

    private func resultInsight(rows: [StandingRow], myRank: Int) -> String {
        guard let winner = rows.first else { return "" }
        if winner.isMe {
            return "거장 다섯을 모두 이겼어요! 다만 정직하게 — 한 판의 승리엔 운이 커요. 이 순위가 반복되는지 전적으로 확인해보세요."
        }
        let mine = myTrades == 0
            ? "이번 판에서 당신은 매매하지 않았어요 — 그것도 하나의 전략이었죠."
            : "당신은 \(myTrades)번 매매해 \(myRank)위였어요."
        return "이번 장의 승자는 \(winner.name)(\(winner.returnPct >= 0 ? "+" : "")\(winner.returnPct.formatted(.number.precision(.fractionLength(1))))%). 이 장의 성격이 그 철학과 맞았던 거예요. \(mine)"
    }

    // MARK: 대결 진행

    private func startMatch() {
        // 거장 5인은 같은 시드 시장을 결정론으로 미리 완주 (즉시)
        botRuns = MasterCatalog.all.map { ($0, $0.run(preset)) }
        // 내가 만든 전략도 출전 (퀀트 빌더에서 저장한 슬롯)
        if let mine = StrategyStore.load() {
            let profile = MasterProfile(
                id: "myStrategy", shortName: mine.name,
                title: "\(mine.name) · 내 전략", icon: "wrench.and.screwdriver.fill",
                horizon: "규칙", quote: "", story: "", rules: [],
                strongMarkets: "", weakMarkets: "", mentalTrap: "",
                run: { BotComparison.run(strategy: mine, scenario: $0) })
            botRuns.append((profile, BotComparison.run(strategy: mine, scenario: preset)))
        }
        loop.start(engine: engine) { finishMatch() }
    }

    private func finishMatch() {
        phase = .result
        let rows = currentStandings()
        let myRank = (rows.firstIndex { $0.isMe } ?? (rows.count - 1)) + 1
        ArenaRecord.record(rank: myRank)
    }

    private func newMatch() {
        loop.cancel()
        loop.isPaused = false
        stamp = Int.random(in: 10_000_000...99_999_999)
        engine = MarketEngine(scenario: DailyMarket.scenario(stamp: stamp, id: "arena.\(stamp)"))
        myTrades = 0
        phase = .running
        startMatch()
    }
}

// MARK: - 전적 (기기 저장)

enum ArenaRecord {
    private static let matchesKey = "seed.arena.matches"
    private static let winsKey = "seed.arena.wins"
    private static let rankSumKey = "seed.arena.rankSum"

    static func record(rank: Int) {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: matchesKey) + 1, forKey: matchesKey)
        defaults.set(defaults.integer(forKey: rankSumKey) + rank, forKey: rankSumKey)
        if rank == 1 {
            defaults.set(defaults.integer(forKey: winsKey) + 1, forKey: winsKey)
        }
    }

    static var summary: String {
        let defaults = UserDefaults.standard
        let matches = defaults.integer(forKey: matchesKey)
        guard matches > 0 else { return "첫 대결" }
        let wins = defaults.integer(forKey: winsKey)
        let avgRank = Double(defaults.integer(forKey: rankSumKey)) / Double(matches)
        return "\(matches)전 \(wins)승 · 평균 \(avgRank.formatted(.number.precision(.fractionLength(1))))위"
    }
}
