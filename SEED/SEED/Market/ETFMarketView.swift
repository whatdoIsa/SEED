import SwiftUI
import JurinKit

/// ETF 상세 (트랙 2) — 호가창 없는 NAV 시장.
/// 주식 화면과 다른 게 교육이다: 캔들 대신 NAV 라인, 호가 대신 구성 종목,
/// 거래세 대신 운용보수. "무엇이 없는지"가 ETF를 설명한다.
struct ETFDetailView: View {
    @Bindable var session: MarketSession
    let store: SeedStore
    let spec: ETFSpec
    @Environment(\.dismiss) private var dismiss
    @State private var orderSide: Side?
    @State private var lastFill: FillResult?
    @State private var orderErrorMessage: String?

    private var nav: Int { session.etfNAV(spec.code) }
    private var referenceNAV: Int { session.etfReferenceNAV(spec.code) }
    private var change: Int { nav - referenceNAV }
    private var changePercent: Double { session.etfChangePercent(spec.code) }
    private var fund: ETFFund? { session.etfFunds[spec.code] }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    navChart
                    feeCard
                    compositionCard
                    myHoldingCard
                    Text("교육용 모의투자 · 실제 투자 권유가 아닙니다")
                        .font(.system(size: 10))
                        .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            orderButtons
        }
        .background(SeedTheme.background)
        .sheet(item: $orderSide) { side in
            ETFOrderSheet(session: session, spec: spec, side: side) { result, _ in
                switch result {
                case .success(let fill): lastFill = fill
                case .failure(let error): orderErrorMessage = error.userMessage(unit: "좌")
                }
            }
        }
        .sensoryFeedback(.success, trigger: lastFill?.id)
        .sheet(item: $lastFill) { fill in
            FillResultSheet(fill: fill, fee: fund?.fee(on: fill.notional) ?? 0)
        }
        .alert("주문이 안 됐어요", isPresented: .init(
            get: { orderErrorMessage != nil },
            set: { if !$0 { orderErrorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(orderErrorMessage ?? "")
        }
    }

    // MARK: 헤더

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(spec.name)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("ETF")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(SeedTheme.violetTint, in: Capsule())
                Text("모의")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SeedTheme.violet)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .overlay(Capsule().stroke(SeedTheme.violet, lineWidth: 1))
                Spacer()
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
            Text(spec.oneLiner)
                .font(.system(size: 12))
                .foregroundStyle(SeedTheme.textSecondary)
            Text("\(nav.formatted())원")
                .accessibilityLabel("\(spec.name) 기준가 \(nav.formatted())원, 전일 대비 \(change >= 0 ? "상승" : "하락") \(abs(changePercent).formatted(.number.precision(.fractionLength(1))))퍼센트")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: nav)
                .padding(.top, 4)
            Text(changeText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SeedTheme.pnl(Double(change)))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private var changeText: String {
        let arrow = change > 0 ? "▲" : change < 0 ? "▼" : ""
        return "\(arrow) \(abs(change).formatted())원 (\(changePercent.formatted(.number.precision(.fractionLength(2))))%) · 1좌 = NAV"
    }

    // MARK: NAV 라인차트 — 구성 종목 종가에서 재구성

    private var navChart: some View {
        let series = session.etfNAVSeries(spec.code)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("NAV 흐름")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SeedTheme.textSecondary)
                Spacer()
                Text("캔들·호가창이 없어요 — ETF는 바스켓 가치(NAV)를 봐요")
                    .font(.system(size: 10))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.7))
            }
            NAVLineChart(values: series.map(Double.init),
                         reference: Double(referenceNAV),
                         lineColor: SeedTheme.pnl(Double(change)))
                .frame(height: 160)
        }
        .padding(14)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: 운용보수 — 보이지 않는 월세를 보이게

    private var feeCard: some View {
        let days = session.etfDaysElapsed
        let accrued = fund?.accruedFeePerShare(
            prices: session.engines.mapValues(\.lastPrice), daysElapsed: days) ?? 0
        let myQty = session.ledger.qty(of: spec.code)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("운용보수")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Spacer()
                Text(spec.expenseRatioLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SeedTheme.violetDeep)
            }
            Text("매 거래일 NAV에서 연보수의 1/252씩 조용히 빠져나가요. D+\(days)일 동안 1좌당 약 \(accrued.formatted(.number.precision(.fractionLength(1))))원이 차감됐어요\(myQty > 0 ? " (내 보유 기준 약 \(Int(accrued * Double(myQty)).formatted())원)" : "").")
                .font(.system(size: 12))
                .foregroundStyle(SeedTheme.textSecondary)
                .lineSpacing(3)
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.violet)
                Text("대신 팔 때 거래세가 없어요 — 주식과 다른 점이에요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textPrimary)
            }
        }
        .padding(15)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: 구성 — 바구니 안을 투명하게

    private var compositionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("바구니 구성")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Spacer()
                Text("바스켓 β \(spec.basketBeta.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(SeedTheme.violetTint, in: Capsule())
            }
            // 비중 바
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(spec.weights.enumerated()), id: \.offset) { index, entry in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(memberColor(index))
                            .frame(width: max(geo.size.width * entry.weight - 2, 4))
                    }
                }
            }
            .frame(height: 10)
            VStack(spacing: 6) {
                ForEach(Array(spec.weights.enumerated()), id: \.offset) { index, entry in
                    let member = SymbolCatalog.spec(code: entry.symbol)
                    HStack(spacing: 8) {
                        Circle().fill(memberColor(index)).frame(width: 8, height: 8)
                        Text(member?.name ?? entry.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SeedTheme.textPrimary)
                        Text("β \((member?.config.marketBeta ?? 0).formatted(.number.precision(.fractionLength(2))))")
                            .font(.system(size: 11))
                            .foregroundStyle(SeedTheme.textSecondary)
                        Spacer()
                        Text("\(Int(entry.weight * 100))%")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SeedTheme.textPrimary)
                    }
                }
            }
            Text("1좌를 사면 이 비율대로 전부를 조금씩 사는 거예요.")
                .font(.system(size: 11))
                .foregroundStyle(SeedTheme.textSecondary.opacity(0.8))
        }
        .padding(15)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func memberColor(_ index: Int) -> Color {
        let palette: [Color] = [
            SeedTheme.violet,
            Color(hex: 0x22C55E),
            Color(hex: 0xF59E0B),
            Color(hex: 0x3182F6),
            Color(hex: 0x8B5CF6)
        ]
        return palette[index % palette.count]
    }

    // MARK: 내 보유

    @ViewBuilder
    private var myHoldingCard: some View {
        let qty = session.ledger.qty(of: spec.code)
        if qty > 0 {
            let avgCost = session.ledger.avgCost(of: spec.code)
            let unrealized = Double(qty) * (Double(nav) - avgCost)
            VStack(alignment: .leading, spacing: 8) {
                Text("내 보유")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                HStack {
                    Text("\(qty)좌 · 평단 \(Int(avgCost).formatted())원")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textSecondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\((qty * nav).formatted())원")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SeedTheme.textPrimary)
                        Text("\(unrealized >= 0 ? "+" : "")\(Int(unrealized).formatted())원")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SeedTheme.pnl(unrealized))
                    }
                }
            }
            .padding(15)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: 주문

    private var orderButtons: some View {
        HStack(spacing: 8) {
            if session.ledger.qty(of: spec.code) > 0 {
                orderButton("팔기", color: SeedTheme.down, side: .sell)
            }
            orderButton("사기", color: SeedTheme.up, side: .buy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .animation(.snappy(duration: 0.25), value: session.ledger.qty(of: spec.code) > 0)
    }

    private func orderButton(_ title: String, color: Color, side: Side) -> some View {
        Button {
            session.orderSheetOpened()
            orderSide = side
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(color, in: RoundedRectangle(cornerRadius: 14))
        }
    }

}

// MARK: - ETF 주문 시트 — NAV 즉시 체결, 태그는 주식과 같은 습관 훈련

struct ETFOrderSheet: View {
    @Bindable var session: MarketSession
    let spec: ETFSpec
    let side: Side
    let onDone: (Result<FillResult, OrderError>, TradeReasonTag) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var qty = 1
    @State private var tag: TradeReasonTag?

    private var nav: Int { session.etfNAV(spec.code) }
    private var fee: Int { session.etfFunds[spec.code]?.fee(on: nav * qty) ?? 0 }
    private var maxQty: Int {
        switch side {
        case .buy:
            let unit = Double(nav) * 1.0002 // 수수료 여유
            return max(Int(Double(session.ledger.availableCash) / unit), 0)
        case .sell:
            return session.ledger.availableShares(of: spec.code)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(spec.name) \(side == .buy ? "사기" : "팔기")")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Spacer()
                Text("NAV \(nav.formatted())원")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SeedTheme.textSecondary)
            }

            // 수량
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("수량")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textSecondary)
                    Spacer()
                    Text("최대 \(maxQty)좌")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary.opacity(0.8))
                }
                HStack(spacing: 8) {
                    Stepper("\(qty)좌", value: $qty, in: 1...max(maxQty, 1))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    ForEach([10, 50], id: \.self) { step in
                        Button("+\(step)") { qty = min(qty + step, max(maxQty, 1)) }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SeedTheme.textPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(SeedTheme.card, in: Capsule())
                    }
                    Button("최대") { qty = max(maxQty, 1) }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SeedTheme.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(SeedTheme.card, in: Capsule())
                }
            }

            // 예상 금액
            VStack(spacing: 6) {
                HStack {
                    Text(side == .buy ? "주문 금액" : "매도 금액")
                        .font(.system(size: 13)).foregroundStyle(SeedTheme.textSecondary)
                    Spacer()
                    Text("\((nav * qty).formatted())원")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                }
                HStack {
                    Text("수수료 (거래세 없음)")
                        .font(.system(size: 13)).foregroundStyle(SeedTheme.textSecondary)
                    Spacer()
                    Text("\(fee.formatted())원")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SeedTheme.textPrimary)
                }
            }
            .padding(13)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))

            // 이유 태그 — 주식과 같은 복기 습관
            VStack(alignment: .leading, spacing: 8) {
                Text("왜 \(side == .buy ? "사나요" : "파나요")?")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)
                FlowTagRow(side: side, selected: $tag)
            }

            Spacer(minLength: 0)

            Button {
                let chosenTag = tag ?? (side == .buy ? .gutBuy : .gutSell)
                let result = side == .buy
                    ? session.buyETF(code: spec.code, qty: qty, tag: chosenTag)
                    : session.sellETF(code: spec.code, qty: qty, tag: chosenTag)
                onDone(result, chosenTag)
                dismiss()
            } label: {
                Text("\(qty)좌 \(side == .buy ? "사기" : "팔기")")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(side == .buy ? SeedTheme.up : SeedTheme.down,
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(maxQty < 1)
        }
        .padding(20)
        .background(SeedTheme.background)
        .presentationDetents([.height(440)])
        .onDisappear { session.orderSheetClosed() }
    }
}

/// 태그 칩 한 줄 — OrderSheet의 태그 UX 축약판.
private struct FlowTagRow: View {
    let side: Side
    @Binding var selected: TradeReasonTag?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TradeReasonTag.tags(for: side), id: \.self) { tag in
                    let isSelected = selected == tag
                    Button {
                        selected = tag
                    } label: {
                        Text(tag.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isSelected ? SeedTheme.inverse : SeedTheme.textSecondary)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(isSelected ? SeedTheme.textPrimary : SeedTheme.card,
                                        in: Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - NAV 라인차트 (미니)

struct NAVLineChart: View {
    let values: [Double]
    let reference: Double
    let lineColor: Color

    var body: some View {
        GeometryReader { geo in
            if values.count > 1 {
                chart(in: geo.size)
            } else {
                Text("데이터를 모으는 중이에요")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func chart(in size: CGSize) -> some View {
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let span = max(maxValue - minValue, max(maxValue * 0.002, 1))
        let lower = minValue - span * 0.08
        let upper = maxValue + span * 0.08
        let range = upper - lower

        func point(_ index: Int) -> CGPoint {
            CGPoint(
                x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                y: size.height * (1 - CGFloat((values[index] - lower) / range))
            )
        }

        return ZStack {
            // 기준선 (전일 NAV)
            if reference > lower && reference < upper {
                let refY = size.height * (1 - CGFloat((reference - lower) / range))
                Path { path in
                    path.move(to: CGPoint(x: 0, y: refY))
                    path.addLine(to: CGPoint(x: size.width, y: refY))
                }
                .stroke(SeedTheme.textSecondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            // NAV 선 + 은은한 채움
            Path { path in
                path.move(to: point(0))
                for index in 1..<values.count { path.addLine(to: point(index)) }
            }
            .stroke(lineColor, style: StrokeStyle(lineWidth: 1.8,
                                                  lineCap: .round, lineJoin: .round))
            Path { path in
                path.move(to: CGPoint(x: 0, y: size.height))
                path.addLine(to: point(0))
                for index in 1..<values.count { path.addLine(to: point(index)) }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [lineColor.opacity(0.14), .clear],
                                 startPoint: .top, endPoint: .bottom))
        }
    }
}
