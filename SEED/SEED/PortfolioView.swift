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
        let ledger = session.ledger
        let prices = session.currentPrices

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
                        Text("\(session.totalEquity.formatted())원")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(SeedTheme.textPrimary)
                    }
                    Divider()
                    detailRow("현금", "\(ledger.cash.formatted())원")
                    if ledger.reservedCash > 0 {
                        detailRow("주문 예약금", "\(ledger.reservedCash.formatted())원")
                    }
                    detailRow("실현손익", "\(Int(ledger.realizedPnL).formatted())원",
                              color: SeedTheme.pnl(ledger.realizedPnL))
                    if ledger.feesPaid > 0 {
                        detailRow("누적 수수료·세금", "\(ledger.feesPaid.formatted())원")
                    }
                }
                .padding(16)
                .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))

                // 종목별 보유 — 분산의 첫 화면
                let held = SymbolCatalog.all.filter { ledger.qty(of: $0.code) > 0 }
                if !held.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(held) { spec in
                            holdingRow(spec: spec, ledger: ledger, price: prices[spec.code] ?? 0)
                        }
                    }
                }

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

                #if DEBUG
                DisclosureGroup {
                    ForEach(Analytics.eventCounts(), id: \.event) { entry in
                        HStack {
                            Text(entry.event).font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Text("\(entry.count)").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(SeedTheme.textSecondary)
                        .padding(.vertical, 1)
                    }
                } label: {
                    Text("KPI 이벤트 (DEBUG)")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
                .padding(.top, 6)
                #endif

                Text("교육용 모의투자 · 실제 투자 권유가 아닙니다")
                    .font(.system(size: 10))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .background(SeedTheme.background)
        .fullScreenCover(isPresented: $showsAutopsy) {
            AutopsyView(store: store, session: session)
        }
    }

    private var seasonLogs: [TradeLog] {
        logs.filter { $0.seasonNumber == store.currentSeason.number }
    }

    private func holdingRow(spec: SymbolSpec, ledger: AccountLedger, price: Int) -> some View {
        let qty = ledger.qty(of: spec.code)
        let avgCost = ledger.avgCost(of: spec.code)
        let unrealized = Double(qty) * (Double(price) - avgCost)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("\(qty)주 · 평단 \(Int(avgCost).formatted())원")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\((qty * price).formatted())원")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("\(unrealized >= 0 ? "+" : "")\(Int(unrealized).formatted())원")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SeedTheme.pnl(unrealized))
            }
        }
        .padding(12)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
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
