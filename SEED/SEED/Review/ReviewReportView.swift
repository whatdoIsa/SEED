import SwiftUI
import JurinKit

/// 복기 리포트 (M4-2, 부록 A-4) — 시그니처 화면. L1 룰베이스: 오프라인·무료.
/// 숫자보다 문장 먼저, 코치는 관찰 어조, 개선 과제는 딱 하나.
struct ReviewReportView: View {
    let store: SeedStore
    @Bindable var session: MarketSession

    @State private var showsArchive = false
    /// 상세(지도·습관) 접기 — 첫 화면의 정보량을 문장·숫자·행동 하나로 절제한다
    @State private var showsDetail = false
    @Environment(PurchaseStore.self) private var purchases
    /// 방문 시점 스냅샷 — 복기는 회고 화면이라 실시간 갱신이 필요 없다.
    /// body에서 store 집계·session.engine.candles를 직접 읽으면 캔들 마감마다
    /// SwiftData 페치 ~8회가 재실행된다. 탭 재방문(onAppear) 때만 새로 계산한다.
    @State private var snap: ReportSnapshot?

    struct ReportSnapshot {
        let stats: [SeedStore.TagStat]
        let tradeCount: Int
        let winRate: Double?
        let holdingStats: HoldingStats?
        let marks: [(candleIndex: Int, price: Double, side: Side)]
        let candles: [Candle]
        let pastSeasonCount: Int
    }

    private func makeSnapshot() -> ReportSnapshot {
        ReportSnapshot(
            stats: store.tagStats(),
            tradeCount: store.tradeCount(),
            winRate: store.winRate(),
            holdingStats: store.holdingStats(),
            marks: store.tradeMarks(symbolName: session.activeSpec.name),
            candles: session.engine.candles,
            pastSeasonCount: store.pastSeasons().count
        )
    }

    var body: some View {
        Group {
            if store.isLessonDone(LessonCatalog.chase.id) {
                if let snap {
                    report(snap)
                } else {
                    SeedTheme.background // onAppear가 즉시 스냅샷을 채운다
                }
            } else {
                lockedState
            }
        }
        .onAppear { snap = makeSnapshot() }
        .sheet(isPresented: $showsArchive) {
            SeasonArchiveView(store: store)
        }
    }

    // MARK: 잠금 상태 (레슨 3 전)

    private var lockedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 26))
                .foregroundStyle(SeedTheme.textSecondary.opacity(0.5))
            Text("복기는 레슨 3을 마치면 열려요")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SeedTheme.textSecondary)
            Text("급등주를 한 번 쫓아본 다음에, 내 습관을 봅니다.")
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeedTheme.background)
    }

    // MARK: 리포트 본문

    private func report(_ snap: ReportSnapshot) -> some View {
        let stats = snap.stats
        let tradeCount = snap.tradeCount
        let winRate = snap.winRate
        let worst = worstStat(in: stats)

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("시즌 \(store.currentSeason.number) 복기")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SeedTheme.violetDeep)
                    Text(headline(worst: worst, tradeCount: tradeCount))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                        .lineSpacing(3)
                    Text("매매 \(tradeCount)건 기록")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textSecondary)
                }

                if tradeCount == 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(SeedTheme.violet)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("복기는 기록에서 시작해요")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(SeedTheme.textPrimary)
                                Text("시장 탭에서 첫 매매를 하면, 태그·매매 지도·보유 습관이 여기 쌓여요. 잘한 매매보다 이유를 적은 매매가 복기엔 더 값져요.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SeedTheme.textSecondary)
                                    .lineSpacing(4)
                            }
                        }
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
                }

                if tradeCount > 0 {
                    // AI 코치: 주 1회 생성, 매매 5건마다 갱신 허용 (캐시 정책)
                    AICoachCard(
                        cacheKey: weeklyCacheKey,
                        fingerprint: weeklyFingerprint(tradeCount: tradeCount),
                        prompt: reviewPrompt(snap: snap),
                        maxTokens: 300,
                        offersTrial: true
                    )
                    // 룰 코치는 AI 코멘트가 보이는 상황에선 숨긴다 — 같은 얘기 두 번 금지.
                    // (비Pro·미지원 기기에선 이 카드가 유일한 코칭이므로 유지)
                    if !aiCoachShowsComment(tradeCount: tradeCount) {
                        coachCard(worst: worst, tradeCount: tradeCount)
                    }

                    HStack(spacing: 10) {
                        metricCard("매매", "\(tradeCount)건")
                        metricCard("승률", winRate.map { "\(Int($0))%" } ?? "—")
                        metricCard("확정 손익률",
                                   avgRealizedText(stats),
                                   color: avgRealizedColor(stats))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("다음, 딱 한 가지")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SeedTheme.violetDeep)
                        Text(nextOneThing(worst: worst))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(SeedTheme.textPrimary)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13)
                                .stroke(SeedTheme.violet.opacity(0.5), lineWidth: 1))
                    }

                    // 상세(지도·습관)는 접어둔다 — 첫 화면은 문장·숫자·행동 하나면 충분하다
                    detailToggle
                    if showsDetail {
                        tradeMapSection(snap)
                        habitSection(stats)
                        holdingHabitSection(snap.holdingStats)
                    }
                }

                // 시즌 아카이브 진입 (마감 시즌이 있을 때)
                if snap.pastSeasonCount > 0 {
                    Button {
                        showsArchive = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(SeedTheme.violet)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("시즌 아카이브")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(SeedTheme.textPrimary)
                                                Text("지난 시즌 \(snap.pastSeasonCount)개 — 성장의 기록")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SeedTheme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(SeedTheme.textSecondary)
                        }
                        .padding(14)
                        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }

                Text("교육용 복기 · 투자 권유 아님")
                    .font(.system(size: 10))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .background(SeedTheme.background)
        .onAppear { Analytics.log(.reviewReportOpened) }
    }

    // MARK: AI 코치 가시성 (룰 코치와의 중복 판정)

    private var weeklyCacheKey: String {
        "weekly.\(Calendar.current.component(.year, from: .now))-\(Calendar.current.component(.weekOfYear, from: .now))"
    }

    private func weeklyFingerprint(tradeCount: Int) -> String { "\(tradeCount / 5)" }

    /// AICoachCard가 실제 코멘트를 그리는 상황인가 — Pro+지원 기기, 또는 체험 캐시 보유.
    /// (비Pro의 체험 제안 카드는 '판매'지 코칭이 아니므로 룰 코치와 중복이 아니다)
    private func aiCoachShowsComment(tradeCount: Int) -> Bool {
        guard AICoach.isAvailable else { return false }
        if purchases.isPro { return true }
        return AICommentCache.load(key: weeklyCacheKey,
                                   fingerprint: weeklyFingerprint(tradeCount: tradeCount)) != nil
    }

    // MARK: 상세 접기

    private var detailToggle: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { showsDetail.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 14))
                    .foregroundStyle(SeedTheme.violet)
                Text(showsDetail ? "상세 접기" : "자세히 보기 — 매매 지도·습관 분석")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SeedTheme.textPrimary)
                Spacer()
                Image(systemName: showsDetail ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            .padding(14)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: 습관 분석 (상세)

    @ViewBuilder
    private func habitSection(_ stats: [SeedStore.TagStat]) -> some View {
        if !stats.isEmpty {
            // 매수 이유는 '분포'가 정보고, 손익은 매도에서만 확정된다 —
            // 한 리스트에 섞으면 매수 행이 영원히 빈 막대·미확정으로 남는다.
            let buyStats = stats
                .filter { TradeReasonTag.tags(for: .buy).contains($0.tag) }
                .sorted { $0.count > $1.count }
            let sellStats = stats
                .filter { TradeReasonTag.tags(for: .sell).contains($0.tag) }
                .sorted { $0.count > $1.count }
            VStack(alignment: .leading, spacing: 10) {
                Text("습관 분석")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                if !buyStats.isEmpty {
                    Text("사는 이유 — 어떤 마음으로 샀나")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                    let totalBuys = buyStats.reduce(0) { $0 + $1.count }
                    ForEach(buyStats) { stat in
                        buyHabitRow(stat, totalBuys: totalBuys)
                    }
                }
                if !sellStats.isEmpty {
                    Text("파는 이유 — 매도가 손익을 확정해요")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                        .padding(.top, buyStats.isEmpty ? 0 : 6)
                    ForEach(sellStats) { stat in
                        habitRow(stat)
                    }
                }
            }
        }
    }

    // MARK: 매매 지도 (부록 A-4의 aha 모먼트 — 어디서 사고 팔았는지 한눈에)

    @ViewBuilder
    private func tradeMapSection(_ snap: ReportSnapshot) -> some View {
        let marks = snap.marks
        if !marks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("내 매매 지도")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("가격 위에 내가 사고 판 자리가 찍혀 있어요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                TradeMapCanvas(candles: snap.candles, marks: marks)
                    .frame(height: 170)
                    .padding(12)
                    .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
                HStack(spacing: 14) {
                    legendDot(color: SeedTheme.up, label: "매수")
                    legendDot(color: SeedTheme.down, label: "매도")
                    Spacer()
                }
                .font(.system(size: 11))
                .foregroundStyle(SeedTheme.textSecondary)
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    // MARK: 보유 습관 (A — 매수·매도 페어링)

    @ViewBuilder
    private func holdingHabitSection(_ holdingStats: HoldingStats?) -> some View {
        if let stats = holdingStats {
            VStack(alignment: .leading, spacing: 10) {
                Text("보유 습관")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("산 것과 판 것을 짝지어 본 왕복 \(stats.tripCount)건의 기록이에요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)

                // 왕복 승률·평균은 상단 지표(승률·확정 손익률)와 사실상 중복이라 뺐다 —
                // 여기서만 알 수 있는 '평균 보유 기간'만 남긴다
                holdingMetric("평균 보유", TradePairing.holdText(ticks: stats.avgHoldTicks))

                if let quick = stats.quickTripAvgPct, let patient = stats.patientTripAvgPct {
                    Text(quick < patient
                         ? "3캔들 안에 판 매매는 평균 \(quick.formatted(.number.precision(.fractionLength(1))))%, 길게 든 매매는 \(patient.formatted(.number.precision(.fractionLength(1))))% — 급하게 팔수록 성적이 나빴어요."
                         : "짧게 든 매매(\(quick.formatted(.number.precision(.fractionLength(1))))%)가 길게 든 매매(\(patient.formatted(.number.precision(.fractionLength(1))))%)보다 나았어요 — 지금 스타일이 단타에 맞는 걸 수도 있어요. 다만 표본이 쌓여야 믿을 수 있는 숫자예요.")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.violetDeep)
                        .lineSpacing(4)
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func holdingMetric(_ label: String, _ value: String, color: Color = SeedTheme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(SeedTheme.textSecondary)
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 룰베이스 문장 생성 (L1 — API 비용 0원)

    /// AI 입력: 원시 로그가 아니라 미리 계산한 요약만 (토큰 다이어트)
    private func reviewPrompt(snap: ReportSnapshot) -> String {
        var lines = ["이번 주까지의 매매 기록을 복기해줘. 데이터:"]
        lines.append("- 총 매매 \(snap.tradeCount)건, 승률 \(snap.winRate.map { "\(Int($0))%" } ?? "미확정")")
        for stat in snap.stats.prefix(5) {
            let avg = stat.avgRealizedReturnPct.map { "\($0 >= 0 ? "+" : "")\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "미확정"
            lines.append("- '\(stat.tag.label)' 태그: \(stat.count)건, 평균 \(avg)")
        }
        if let habits = snap.holdingStats {
            lines.append("- 평균 보유 \(habits.avgHoldTicks)틱, 왕복 승률 \(Int(habits.winRate))%")
        }
        lines.append("가장 아픈 습관 하나와 잘한 것 하나를 짚고, 다음 주의 한 가지를 제안해줘.")
        return lines.joined(separator: "\n")
    }

    private func worstStat(in stats: [SeedStore.TagStat]) -> SeedStore.TagStat? {
        stats
            .filter { ($0.avgRealizedReturnPct ?? 0) < 0 && $0.lossCount >= 1 }
            .min { ($0.avgRealizedReturnPct ?? 0) < ($1.avgRealizedReturnPct ?? 0) }
    }

    private func headline(worst: SeedStore.TagStat?, tradeCount: Int) -> String {
        if tradeCount == 0 {
            return "첫 매매가 곧\n첫 복기예요"
        }
        if let worst {
            return "'\(worst.tag.label)' 매매가\n가장 아팠어요"
        }
        return "지금 습관,\n나쁘지 않아요"
    }

    private func coachCard(worst: SeedStore.TagStat?, tradeCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "message.circle.fill").font(.system(size: 12))
                Text("코치").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(SeedTheme.violetOnDark)
            Text(coachText(worst: worst, tradeCount: tradeCount))
                .font(.system(size: 14))
                .foregroundStyle(SeedTheme.inkText)
                .lineSpacing(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(SeedTheme.ink, in: RoundedRectangle(cornerRadius: 15))
    }

    private func coachText(worst: SeedStore.TagStat?, tradeCount: Int) -> String {
        guard tradeCount > 0 else {
            return "시장 탭에서 사고팔 때마다 '왜'를 함께 기록해요. 그 기록이 쌓이면 여기서 당신의 패턴이 보입니다."
        }
        if let worst, let avg = worst.avgRealizedReturnPct {
            let settled = worst.winCount + worst.lossCount
            return "'\(worst.tag.label)'로 산 매매 중 확정된 \(settled)건에서 \(worst.lossCount)건이 손실이에요. 평균 \(avg.formatted(.number.precision(.fractionLength(1))))%. 이 이유로 살 때의 나를 한 번 의심해봐도 좋겠어요."
        }
        return "아직 뚜렷한 나쁜 습관이 안 보여요. 다만 판단은 확정(매도)된 매매가 더 쌓인 뒤에요 — 팔아봐야 진짜 성적이 나옵니다."
    }

    private func nextOneThing(worst: SeedStore.TagStat?) -> String {
        switch worst?.tag {
        case .chase: return "급등을 봐도 첫 눌림까지 기다렸다가 사보기"
        case .gutBuy, .gutSell: return "사기 전에 이유를 딱 하나만 정해보기"
        case .fear: return "손절선을 미리 정해두고 사보기"
        case .boredom: return "지루할 땐 팔지 말고 배속을 올려보기"
        case .news: return "뉴스를 본 뒤 5캔들만 기다렸다 판단하기"
        default: return "지금 페이스 유지 — 매도까지 마쳐서 성적 확정해보기"
        }
    }

    // MARK: 구성 요소

    private func metricCard(_ label: String, _ value: String, color: Color = SeedTheme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(SeedTheme.textSecondary)
            Text(value).font(.system(size: 18, weight: .semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func avgRealizedText(_ stats: [SeedStore.TagStat]) -> String {
        let averages = stats.compactMap(\.avgRealizedReturnPct)
        guard !averages.isEmpty else { return "—" }
        let avg = averages.reduce(0, +) / Double(averages.count)
        return "\(avg >= 0 ? "+" : "")\(avg.formatted(.number.precision(.fractionLength(1))))%"
    }

    private func avgRealizedColor(_ stats: [SeedStore.TagStat]) -> Color {
        let averages = stats.compactMap(\.avgRealizedReturnPct)
        guard !averages.isEmpty else { return SeedTheme.textPrimary }
        return SeedTheme.pnl(averages.reduce(0, +) / Double(averages.count))
    }

    /// 매수 이유 행 — 성적이 아니라 비중을 보여준다 ("내 매수의 44%가 돌파 기대")
    private func buyHabitRow(_ stat: SeedStore.TagStat, totalBuys: Int) -> some View {
        let share = totalBuys > 0 ? Double(stat.count) / Double(totalBuys) : 0
        return HStack(spacing: 10) {
            Text(stat.tag.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SeedTheme.textPrimary)
                .frame(width: 72, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SeedTheme.band)
                    Capsule()
                        .fill(SeedTheme.violet.opacity(0.55))
                        .frame(width: max(geo.size.width * share, 6))
                }
            }
            .frame(height: 7)
            Text("\(stat.count)건 · \(Int((share * 100).rounded()))%")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SeedTheme.textSecondary)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private func habitRow(_ stat: SeedStore.TagStat) -> some View {
        HStack(spacing: 10) {
            Text(stat.tag.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SeedTheme.textPrimary)
                .frame(width: 72, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SeedTheme.band)
                    if let avg = stat.avgRealizedReturnPct {
                        Capsule()
                            .fill(SeedTheme.pnl(avg))
                            .frame(width: max(geo.size.width * min(abs(avg) / 5, 1), 6))
                    }
                }
            }
            .frame(height: 7)
            Text(statText(stat))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(stat.avgRealizedReturnPct.map { SeedTheme.pnl($0) } ?? SeedTheme.textSecondary)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private func statText(_ stat: SeedStore.TagStat) -> String {
        if let avg = stat.avgRealizedReturnPct {
            return "\(stat.count)건 \(avg >= 0 ? "+" : "")\(avg.formatted(.number.precision(.fractionLength(1))))%"
        }
        return "\(stat.count)건 · 미확정"
    }
}
