import SwiftUI
import JurinKit

/// 복기 리포트 (M4-2, 부록 A-4) — 시그니처 화면. L1 룰베이스: 오프라인·무료.
/// 숫자보다 문장 먼저, 코치는 관찰 어조, 개선 과제는 딱 하나.
struct ReviewReportView: View {
    let store: SeedStore
    @Bindable var session: MarketSession

    var body: some View {
        if store.isLessonDone(LessonCatalog.chase.id) {
            report
        } else {
            lockedState
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

    private var report: some View {
        let stats = store.tagStats()
        let tradeCount = store.tradeCount()
        let winRate = store.winRate()
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

                HStack(spacing: 10) {
                    metricCard("매매", "\(tradeCount)건")
                    metricCard("승률", winRate.map { "\(Int($0))%" } ?? "—")
                    metricCard("확정 손익률",
                               avgRealizedText(stats),
                               color: avgRealizedColor(stats))
                }

                tradeMapSection

                if !stats.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("습관 분석")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SeedTheme.textPrimary)
                        Text("매수·매도할 때 고른 이유별 성적이에요.")
                            .font(.system(size: 12))
                            .foregroundStyle(SeedTheme.textSecondary)
                        ForEach(stats) { stat in
                            habitRow(stat)
                        }
                    }
                }

                coachCard(worst: worst, tradeCount: tradeCount)

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
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(SeedTheme.violet.opacity(0.5), lineWidth: 1))
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

    // MARK: 매매 지도 (부록 A-4의 aha 모먼트 — 어디서 사고 팔았는지 한눈에)

    @ViewBuilder
    private var tradeMapSection: some View {
        let marks = store.tradeMarks(symbolName: session.activeSpec.name)
        if !marks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("내 매매 지도")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("가격 위에 내가 사고 판 자리가 찍혀 있어요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                TradeMapCanvas(candles: session.engine.candles, marks: marks)
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

    // MARK: 룰베이스 문장 생성 (L1 — API 비용 0원)

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
        return SeedTheme.pnl(averages.reduce(0, +))
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
