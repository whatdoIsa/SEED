import SwiftUI
import SwiftData
import JurinKit

/// 내 주식 (M2-4) — 계좌 현황 + 매매 기록. 읽기는 @Query, 쓰기는 SeedStore 경유.
struct PortfolioView: View {
    @Bindable var session: MarketSession
    let store: SeedStore
    @Query(sort: \TradeLog.timestamp, order: .reverse) private var logs: [TradeLog]
    @State private var showsAutopsy = false

    var body: some View {
        let portfolio = session.engine.portfolio
        let last = session.engine.lastPrice
        let unrealized = portfolio.unrealizedPnL(at: last)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("내 주식")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    Spacer()
                    Text("시즌 \(store.currentSeason.number)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SeedTheme.violet)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(SeedTheme.violetTint, in: Capsule())
                }

                VStack(spacing: 10) {
                    HStack {
                        Text("총 평가")
                            .font(.system(size: 13))
                            .foregroundStyle(SeedTheme.textSecondary)
                        Spacer()
                        Text("\(portfolio.equity(at: last).formatted())원")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(SeedTheme.textPrimary)
                    }
                    Divider()
                    detailRow("현금", "\(portfolio.cash.formatted())원")
                    detailRow("보유", portfolio.qty > 0
                              ? "\(portfolio.qty)주 · 평단 \(Int(portfolio.avgCost).formatted())원"
                              : "없음")
                    if portfolio.qty > 0 {
                        detailRow("평가손익", "\(Int(unrealized).formatted())원",
                                  color: SeedTheme.pnl(unrealized))
                    }
                    detailRow("실현손익", "\(Int(portfolio.realizedPnL).formatted())원",
                              color: SeedTheme.pnl(portfolio.realizedPnL))
                }
                .padding(16)
                .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))

                if let rule = store.currentSeason.carriedRule {
                    HStack(spacing: 7) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 11))
                        Text("이번 시즌 규칙: \(rule)")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(SeedTheme.violetDeep)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 10))
                }

                Text("매매 기록")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)

                if seasonLogs.isEmpty {
                    Text("아직 매매가 없어요. 시장에서 첫 주문을 내보세요.")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                } else {
                    VStack(spacing: 8) {
                        ForEach(seasonLogs) { log in
                            logRow(log)
                        }
                    }
                }
                Button {
                    showsAutopsy = true
                } label: {
                    Text("계좌 리셋 (부검 후 시즌 \(store.currentSeason.number + 1) 시작)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SeedTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SeedTheme.band, lineWidth: 1))
                }
                .padding(.top, 8)
            }
            .padding(16)
        }
        .background(Color.white)
        .fullScreenCover(isPresented: $showsAutopsy) {
            AutopsyView(store: store, session: session)
        }
    }

    private var seasonLogs: [TradeLog] {
        logs.filter { $0.seasonNumber == store.currentSeason.number }
    }

    private func detailRow(_ label: String, _ value: String, color: Color = SeedTheme.textPrimary) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(SeedTheme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 14, weight: .medium)).foregroundStyle(color)
        }
    }

    private func logRow(_ log: TradeLog) -> some View {
        HStack(spacing: 10) {
            Text(log.side == .buy ? "매수" : "매도")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(log.side == .buy ? SeedTheme.up : SeedTheme.down, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(log.qty)주 · \(Int(log.avgFillPrice).formatted())원")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SeedTheme.textPrimary)
                HStack(spacing: 6) {
                    Text(log.reasonTag.label)
                        .font(.system(size: 11))
                        .foregroundStyle(SeedTheme.violetDeep)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(SeedTheme.violetTint, in: Capsule())
                    if log.slippage >= 1 {
                        Text("슬리피지 +\(Int(log.slippage))원")
                            .font(.system(size: 11))
                            .foregroundStyle(SeedTheme.textSecondary)
                    }
                }
            }
            Spacer()
            if let realized = log.realizedReturnPct {
                Text("\(realized >= 0 ? "+" : "")\(realized.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeedTheme.pnl(realized))
            }
        }
        .padding(12)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
