import SwiftUI

/// 시즌 아카이브 — "눈이 생긴다"의 증명 화면.
/// 시즌별 수익률을 나란히 놓아 성장(또는 교훈)을 보여준다.
/// 최근 완결 시즌 1개는 무료, 그 이전 역사는 Pro.
struct SeasonArchiveView: View {
    let store: SeedStore
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var showsPaywall = false

    var body: some View {
        let seasons = store.pastSeasons()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("시즌 아카이브")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(SeedTheme.textPrimary)
                        Text("시즌이 쌓일수록, 눈이 생기는 게 보여요")
                            .font(.system(size: 13))
                            .foregroundStyle(SeedTheme.textSecondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SeedTheme.textSecondary)
                    }
                }

                if seasons.isEmpty {
                    emptyState
                } else {
                    growthChart(seasons)
                    ForEach(Array(seasons.enumerated().reversed()), id: \.element.number) { index, season in
                        // 가장 최근 완결 시즌은 무료, 이전 역사는 Pro
                        let locked = !purchases.isPro && index < seasons.count - 1
                        seasonRow(season, locked: locked)
                    }
                }
            }
            .padding(16)
        }
        .background(SeedTheme.background)
        .sheet(isPresented: $showsPaywall) {
            RefillSheet(purchases: purchases,
                        title: "성장의 전체 역사 보기",
                        subtitle: "지난 모든 시즌의 기록과 규칙은 Pro에서 열려요.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 30))
                .foregroundStyle(SeedTheme.violet)
            Text("아직 마감한 시즌이 없어요")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
            Text("계좌 부검으로 시즌을 마감하면 여기 역사가 쌓여요.\n이월되는 건 돈이 아니라 교훈이에요.")
                .font(.system(size: 12))
                .foregroundStyle(SeedTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    /// 시즌별 수익률 막대 — 손으로 그린 앱의 문법 그대로
    private func growthChart(_ seasons: [Season]) -> some View {
        let returns = seasons.map { season -> Double in
            guard let end = season.endEquity, season.startCash > 0 else { return 0 }
            return Double(end - season.startCash) / Double(season.startCash) * 100
        }
        let maxAbs = max(returns.map { abs($0) }.max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 8) {
            Text("시즌별 수익률")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SeedTheme.textSecondary)
            HStack(alignment: .center, spacing: 10) {
                ForEach(Array(returns.enumerated()), id: \.offset) { index, pct in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        Text("\(pct >= 0 ? "+" : "")\(pct.formatted(.number.precision(.fractionLength(1))))%")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(SeedTheme.pnl(pct))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(pct >= 0 ? SeedTheme.up : SeedTheme.down)
                            .frame(width: 26,
                                   height: max(CGFloat(abs(pct) / maxAbs) * 70, 4))
                        Text("S\(seasons[index].number)")
                            .font(.system(size: 10))
                            .foregroundStyle(SeedTheme.textSecondary)
                    }
                }
                Spacer()
            }
            .frame(height: 110)
        }
        .padding(14)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func seasonRow(_ season: Season, locked: Bool) -> some View {
        let pct: Double = {
            guard let end = season.endEquity, season.startCash > 0 else { return 0 }
            return Double(end - season.startCash) / Double(season.startCash) * 100
        }()

        return Button {
            if locked { showsPaywall = true }
        } label: {
            HStack(spacing: 12) {
                Text("S\(season.number)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .frame(width: 34, height: 34)
                    .background(SeedTheme.violetTint, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    if locked {
                        Text("시즌 \(season.number)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SeedTheme.textSecondary)
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill").font(.system(size: 10))
                            Text("Pro에서 열려요")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(SeedTheme.textSecondary)
                    } else {
                        HStack(spacing: 6) {
                            Text("시즌 \(season.number)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(SeedTheme.textPrimary)
                            Text("\(pct >= 0 ? "+" : "")\(pct.formatted(.number.precision(.fractionLength(1))))%")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SeedTheme.pnl(pct))
                        }
                        Text(season.carriedRule.flatMap { $0.isEmpty ? nil : "가져간 규칙 · \($0)" }
                             ?? "가져간 규칙 없음")
                            .font(.system(size: 12))
                            .foregroundStyle(SeedTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if locked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
            }
            .padding(13)
            .background(SeedTheme.card.opacity(locked ? 0.6 : 1),
                        in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }
}
