import SwiftUI
import JurinKit

/// 시장 레지스터(§10) 트레이딩 화면 — 부록 A-1의 첫 구현 슬라이스.
/// 흰 배경 · 빨/파 손익 · 하단 고정 매매 버튼. 바이올렛은 모의 배지에만 등장한다.
struct TradingView: View {
    @Bindable var session: MarketSession
    let store: SeedStore
    @State private var orderSide: Side?
    @State private var lastFill: FillResult?
    @State private var orderErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            speedBar
            ChartCanvas(
                candles: session.engine.candles,
                current: session.engine.currentCandle
            )
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 12)
            portfolioStrip
            orderButtons
        }
        .background(Color.white)
        .task { session.start() }
        .sheet(item: $orderSide) { side in
            OrderSheet(session: session, side: side) { result, tag, avgCostBefore in
                switch result {
                case .success(let fill):
                    store.record(fill: fill, tag: tag, avgCostBeforeOrder: avgCostBefore)
                    lastFill = fill
                case .failure(let error):
                    orderErrorMessage = message(for: error)
                }
            }
            .presentationDetents([.height(400)])
        }
        .sheet(item: $lastFill) { fill in
            FillResultSheet(fill: fill)
                .presentationDetents([.height(340)])
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

    // MARK: 헤더 (종목 · 현재가 · 등락)

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("한빛전자")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("모의")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SeedTheme.violet)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .overlay(Capsule().stroke(SeedTheme.violet, lineWidth: 1))
                Spacer()
            }
            Text("\(session.engine.lastPrice.formatted())원")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: session.engine.lastPrice)
            Text(changeText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SeedTheme.pnl(Double(session.change)))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var changeText: String {
        let arrow = session.change > 0 ? "▲" : session.change < 0 ? "▼" : ""
        return "\(arrow) \(abs(session.change).formatted())원 (\(session.changePercent.formatted(.number.precision(.fractionLength(2))))%)"
    }

    // MARK: 배속 (스펙 1)

    private var speedBar: some View {
        HStack(spacing: 6) {
            ForEach(MarketSession.Speed.allCases) { speed in
                Button {
                    session.speed = speed
                } label: {
                    Text(speed.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(session.speed == speed ? .white : SeedTheme.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(
                            session.speed == speed ? SeedTheme.textPrimary : SeedTheme.card,
                            in: Capsule()
                        )
                }
            }
            Button {
                session.engine.advanceToNextCandle()
            } label: {
                Label("다음 캔들", systemImage: "chevron.right.2")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(SeedTheme.card, in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 포트폴리오 스트립

    private var portfolioStrip: some View {
        let portfolio = session.engine.portfolio
        let unrealized = portfolio.unrealizedPnL(at: session.engine.lastPrice)
        return HStack(spacing: 16) {
            metric("현금", "\(portfolio.cash.formatted())원")
            metric("보유", "\(portfolio.qty)주")
            if portfolio.qty > 0 {
                metric("평가손익",
                       "\(Int(unrealized).formatted())원",
                       color: SeedTheme.pnl(unrealized))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SeedTheme.band)
    }

    private func metric(_ label: String, _ value: String, color: Color = SeedTheme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(SeedTheme.textSecondary)
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
        }
    }

    // MARK: 주문 버튼 (한국식: 매도 파랑 / 매수 빨강)

    private var orderButtons: some View {
        HStack(spacing: 8) {
            orderButton("팔기", color: SeedTheme.down, side: .sell)
            orderButton("사기", color: SeedTheme.up, side: .buy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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

    private func message(for error: OrderError) -> String {
        switch error {
        case .insufficientCash(let needed, let available):
            return "현금이 부족해요. 필요 \(needed.formatted())원 / 보유 \(available.formatted())원"
        case .insufficientHoldings(let requested, let held):
            return "보유한 주식이 부족해요. 주문 \(requested)주 / 보유 \(held)주"
        case .noLiquidity:
            return "지금은 살 수 있는 물량이 없어요. 잠시 뒤 다시 해봐요."
        case .invalidQuantity:
            return "수량을 확인해 주세요."
        }
    }
}

// MARK: - 캔들 차트 (Canvas)

struct ChartCanvas: View {
    let candles: [Candle]
    let current: Candle
    private let visibleCount = 40

    var body: some View {
        Canvas { context, size in
            let all = Array(candles.suffix(visibleCount - 1)) + [current]
            guard !all.isEmpty else { return }

            let priceHigh = all.map(\.high).max() ?? 0
            let priceLow = all.map(\.low).min() ?? 0
            let range = max(priceHigh - priceLow, 1)
            let maxVolume = max(all.map(\.volume).max() ?? 1, 1)

            let chartHeight = size.height * 0.78
            let volumeTop = size.height * 0.82
            let volumeHeight = size.height * 0.18
            let slot = size.width / CGFloat(visibleCount)
            let bodyWidth = slot * 0.62

            func y(_ price: Int) -> CGFloat {
                chartHeight * (1 - CGFloat(price - priceLow) / CGFloat(range))
            }

            for (i, candle) in all.enumerated() {
                let x = slot * (CGFloat(i) + 0.5)
                let color = candle.isBullish ? SeedTheme.up : SeedTheme.down

                // 꼬리
                var wick = Path()
                wick.move(to: CGPoint(x: x, y: y(candle.high)))
                wick.addLine(to: CGPoint(x: x, y: y(candle.low)))
                context.stroke(wick, with: .color(color), lineWidth: 1)

                // 몸통 (시가=종가여도 최소 두께)
                let top = y(max(candle.open, candle.close))
                let bottom = y(min(candle.open, candle.close))
                let bodyRect = CGRect(
                    x: x - bodyWidth / 2, y: top,
                    width: bodyWidth, height: max(bottom - top, 1.5)
                )
                context.fill(Path(roundedRect: bodyRect, cornerRadius: 1), with: .color(color))

                // 거래량
                let volumeBarHeight = volumeHeight * CGFloat(candle.volume) / CGFloat(maxVolume)
                let volumeRect = CGRect(
                    x: x - bodyWidth / 2, y: volumeTop + (volumeHeight - volumeBarHeight),
                    width: bodyWidth, height: volumeBarHeight
                )
                context.fill(Path(volumeRect), with: .color(color.opacity(0.35)))
            }
        }
    }
}

// MARK: - 주문 시트

struct OrderSheet: View {
    let session: MarketSession
    let side: Side
    let onComplete: (Result<FillResult, OrderError>, TradeReasonTag, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var qty = 10
    @State private var selectedTag: TradeReasonTag?

    private var accent: Color { side == .buy ? SeedTheme.up : SeedTheme.down }
    private var title: String { side == .buy ? "사기" : "팔기" }

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(SeedTheme.band).frame(width: 36, height: 4).padding(.top, 10)

            HStack {
                Text("시장가로 \(title)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Spacer()
                if let displayed = session.engine.displayedPrice(for: side) {
                    Text("지금 \(displayed.formatted())원")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
            }

            HStack(spacing: 8) {
                ForEach([10, 50, 100, 500], id: \.self) { preset in
                    Button {
                        qty = preset
                    } label: {
                        Text("\(preset)주")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(qty == preset ? .white : SeedTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                qty == preset ? SeedTheme.textPrimary : SeedTheme.card,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                }
            }

            Stepper("수량 \(qty)주", value: $qty, in: 1...10_000, step: 10)
                .font(.system(size: 14))

            // 매매 사유 태그 — 1탭 필수 (스펙 2). 텍스트 입력은 마찰이라 쓰지 않는다.
            VStack(alignment: .leading, spacing: 8) {
                Text(side == .buy ? "왜 사시나요?" : "왜 파시나요?")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SeedTheme.textSecondary)
                HStack(spacing: 6) {
                    ForEach(TradeReasonTag.tags(for: side), id: \.rawValue) { tag in
                        Button {
                            selectedTag = tag
                        } label: {
                            Text(tag.label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(selectedTag == tag ? .white : SeedTheme.textPrimary)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(
                                    selectedTag == tag ? SeedTheme.textPrimary : SeedTheme.card,
                                    in: Capsule()
                                )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                guard let tag = selectedTag else { return }
                let avgCostBefore = session.engine.portfolio.avgCost
                let result = session.placeOrder(side: side, qty: qty)
                session.orderSheetClosed()
                dismiss()
                onComplete(result, tag, avgCostBefore)
            } label: {
                Text(selectedTag == nil ? "이유를 하나 골라주세요" : "\(qty)주 \(title)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        selectedTag == nil ? SeedTheme.textSecondary : accent,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .disabled(selectedTag == nil)
        }
        .padding(.horizontal, 20)
        .onDisappear { session.orderSheetClosed() }
    }
}

// MARK: - 체결 결과 시트 (슬리피지가 보이는 순간 — 튜토리얼의 씨앗)

struct FillResultSheet: View {
    let fill: FillResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(SeedTheme.band).frame(width: 36, height: 4).padding(.top, 10)

            Text(fill.side == .buy ? "샀어요" : "팔았어요")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)

            VStack(spacing: 6) {
                row("화면에 보이던 가격", "\(fill.displayedPrice.formatted())원")
                row("평균 체결가", "\(fill.avgFillPrice.formatted(.number.precision(.fractionLength(0))))원")
                row("체결 수량", "\(fill.filledQty)주 / 주문 \(fill.requestedQty)주")
            }

            if fill.slippage >= 1 {
                Text("표시가보다 \(Int(fill.slippage).formatted())원 밀렸어요 (\(fill.slippagePercent.formatted(.number.precision(.fractionLength(2))))%) — 왜 그럴까요?")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(spacing: 4) {
                ForEach(Array(fill.fills.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text("\(item.price.formatted())원")
                        Spacer()
                        Text("\(item.qty)주")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)
                }
            }
            .padding(.horizontal, 4)

            Button {
                dismiss()
            } label: {
                Text("확인")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(SeedTheme.textPrimary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 20)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(SeedTheme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 14, weight: .medium)).foregroundStyle(SeedTheme.textPrimary)
        }
    }
}

// MARK: - sheet(item:) 어댑터

extension Side: @retroactive Identifiable {
    public var id: String { rawValue }
}

extension FillResult: @retroactive Identifiable {
    public var id: String { "\(side.rawValue)-\(requestedQty)-\(notional)" }
}
