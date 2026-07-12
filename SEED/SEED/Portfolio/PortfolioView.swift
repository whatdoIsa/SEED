import SwiftUI
import SwiftData
import JurinKit

/// 내 주식 (M2-4) — 계좌 현황 + 매매 기록. 읽기는 @Query, 쓰기는 SeedStore 경유.
struct PortfolioView: View {
    @Bindable var session: MarketSession
    let store: SeedStore
    @Query(sort: \TradeLog.timestamp, order: .reverse) private var logs: [TradeLog]
    @State private var showsAutopsy = false
    @State private var showsSettings = false

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
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(SeedTheme.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(SeedTheme.card, in: Circle())
                    }
                }

                // 부검에서 가져온 이번 시즌 규칙 — 매일 눈에 밟히게
                if let rule = store.currentSeason.carriedRule, !rule.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(SeedTheme.violetDeep)
                        Text("이번 시즌 규칙 · \(rule)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SeedTheme.violetDeep)
                        Spacer()
                    }
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 12))
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
                let heldETFs = ETFCatalog.all.filter { ledger.qty(of: $0.code) > 0 }
                if !held.isEmpty || !heldETFs.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(held) { spec in
                            holdingRow(name: spec.name, code: spec.code, isETF: false,
                                       ledger: ledger, price: prices[spec.code] ?? 0)
                        }
                        ForEach(heldETFs) { spec in
                            holdingRow(name: spec.name, code: spec.code, isETF: true,
                                       ledger: ledger, price: prices[spec.code] ?? 0)
                        }
                    }
                }

                diversificationCard(ledger: ledger, prices: prices)

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
        .sheet(isPresented: $showsSettings) {
            SettingsView(session: session, store: store)
        }
        .fullScreenCover(isPresented: $showsAutopsy) {
            AutopsyView(store: store, session: session)
        }
    }

    private var seasonLogs: [TradeLog] {
        logs.filter { $0.seasonNumber == store.currentSeason.number }
    }

    // MARK: 분산 체감 지표 — 레슨 6(계란과 바구니)의 일상 연장

    @ViewBuilder
    private func diversificationCard(ledger: AccountLedger, prices: [String: Int]) -> some View {
        let equity = session.totalEquity
        if equity > 0 {
            // 계좌 β: 보유 평가액 가중 평균 (현금은 β 0 — 현금도 분산이다)
            // ETF는 바스켓 β(구성 가중 평균)로 계산 — 자산배분 ETF가 β를 낮추는 게 눈에 보인다.
            let stockWeighted = SymbolCatalog.all.reduce(0.0) { sum, spec in
                let value = Double(ledger.qty(of: spec.code) * (prices[spec.code] ?? 0))
                return sum + value * spec.config.marketBeta
            }
            let etfWeighted = ETFCatalog.all.reduce(0.0) { sum, spec in
                let value = Double(ledger.qty(of: spec.code) * (prices[spec.code] ?? 0))
                return sum + value * spec.basketBeta
            }
            let accountBeta = (stockWeighted + etfWeighted) / Double(equity)
            let shockPct = -3.0
            let impactPct = shockPct * accountBeta
            let impactWon = Int(Double(equity) * impactPct / 100)
            let biggest = (SymbolCatalog.all.map { (name: $0.name, code: $0.code) }
                           + ETFCatalog.all.map { (name: $0.name, code: $0.code) })
                .map { (name: $0.name, value: ledger.qty(of: $0.code) * (prices[$0.code] ?? 0)) }
                .max { $0.value < $1.value }
            let concentration = Double(biggest?.value ?? 0) / Double(equity) * 100
            let hasHoldings = (biggest?.value ?? 0) > 0

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("분산 점검")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    Spacer()
                    Text("내 계좌 β \(accountBeta.formatted(.number.precision(.fractionLength(2))))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SeedTheme.violetDeep)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(SeedTheme.violetTint, in: Capsule())
                }

                betaScale(accountBeta: accountBeta)

                if hasHoldings {
                    Text(impactSentence(impactPct: impactPct, impactWon: impactWon))
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textPrimary)
                        .lineSpacing(4)

                    if concentration >= 50, let biggest {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                            Text("\(biggest.name) 한 바구니에 계좌의 \(Int(concentration))%가 담겨 있어요.")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(SeedTheme.down)
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .background(SeedTheme.downTint, in: RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    Text("전부 현금이에요. 흔들림은 0% — 하지만 자라지도 않아요. 그것도 하나의 선택입니다.")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textSecondary)
                        .lineSpacing(4)
                }

                if !store.isLessonDone(LessonCatalog.diversify.id) {
                    Text("β가 뭔지 궁금하면 → 배우기 탭 레슨 6")
                        .font(.system(size: 11))
                        .foregroundStyle(SeedTheme.textSecondary.opacity(0.8))
                }
            }
            .padding(15)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func impactSentence(impactPct: Double, impactWon: Int) -> AttributedString {
        let direction = impactPct <= 0 ? "흔들려요" : "오히려 올라요"
        var text = AttributedString("시장이 -3% 빠지는 날, 내 계좌는 약 ")
        var number = AttributedString("\(impactPct.formatted(.number.precision(.fractionLength(1))))% (\(impactWon.formatted())원)")
        number.foregroundColor = impactPct <= 0 ? SeedTheme.down : SeedTheme.up
        number.font = .system(size: 13, weight: .semibold)
        text += number
        text += AttributedString(" \(direction).")
        return text
    }

    /// β 눈금자: 현금(0) — 시장(1) 기준선 위에 내 계좌 위치를 찍는다.
    private func betaScale(accountBeta: Double) -> some View {
        let minBeta = -0.6, maxBeta = 1.5
        func position(_ beta: Double, width: CGFloat) -> CGFloat {
            let clamped = min(max(beta, minBeta), maxBeta)
            return width * CGFloat((clamped - minBeta) / (maxBeta - minBeta))
        }
        return VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SeedTheme.band).frame(height: 6)
                        .frame(maxHeight: .infinity)
                    ForEach([0.0, 1.0], id: \.self) { mark in
                        Rectangle()
                            .fill(SeedTheme.textSecondary.opacity(0.5))
                            .frame(width: 1.5, height: 12)
                            .position(x: position(mark, width: geo.size.width), y: geo.size.height / 2)
                    }
                    Circle()
                        .fill(SeedTheme.violet)
                        .frame(width: 14, height: 14)
                        .position(x: position(accountBeta, width: geo.size.width), y: geo.size.height / 2)
                }
            }
            .frame(height: 16)
            GeometryReader { geo in
                ZStack {
                    Text("현금 0")
                        .position(x: position(0, width: geo.size.width), y: 6)
                    Text("시장 1.0")
                        .position(x: position(1.0, width: geo.size.width), y: 6)
                }
                .font(.system(size: 10))
                .foregroundStyle(SeedTheme.textSecondary.opacity(0.8))
            }
            .frame(height: 12)
        }
    }

    private func holdingRow(name: String, code: String, isETF: Bool,
                            ledger: AccountLedger, price: Int) -> some View {
        let qty = ledger.qty(of: code)
        let avgCost = ledger.avgCost(of: code)
        let unrealized = Double(qty) * (Double(price) - avgCost)
        let unit = isETF ? "좌" : "주"
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    if isETF {
                        Text("ETF")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SeedTheme.violetDeep)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(SeedTheme.violetTint, in: Capsule())
                    }
                }
                Text("\(qty)\(unit) · 평단 \(Int(avgCost).formatted())원")
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
