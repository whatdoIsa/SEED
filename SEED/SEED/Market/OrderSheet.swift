import SwiftUI
import JurinKit

// MARK: - 주문 시트

enum OrderOutcome {
    case market(FillResult)
    case limit(MarketEngine.LimitOrderResult)
}

struct OrderSheet: View {
    let session: MarketSession
    let side: Side
    var allowsLimit: Bool = false
    let onComplete: (Result<OrderOutcome, OrderError>, TradeReasonTag, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var qty = 10
    @State private var selectedTag: TradeReasonTag?
    @State private var orderType = 0
    @State private var limitPrice = 0

    private var accent: Color { side == .buy ? SeedTheme.up : SeedTheme.down }
    private var title: String { side == .buy ? "사기" : "팔기" }
    private var isLimit: Bool { orderType == 1 }

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(SeedTheme.band).frame(width: 36, height: 4).padding(.top, 10)

            HStack {
                Text("\(isLimit ? "지정가" : "시장가")로 \(title)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Spacer()
                if let displayed = session.engine.displayedPrice(for: side) {
                    Text("지금 \(displayed.formatted())원")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
            }

            if allowsLimit {
                Picker("주문 방식", selection: $orderType) {
                    Text("시장가").tag(0)
                    Text("지정가").tag(1)
                }
                .pickerStyle(.segmented)
            }

            if isLimit {
                HStack {
                    Text("주문 가격")
                        .font(.system(size: 14))
                        .foregroundStyle(SeedTheme.textSecondary)
                    Spacer()
                    Stepper("\(limitPrice.formatted())원",
                            value: $limitPrice,
                            in: 1_000...1_000_000,
                            step: session.engine.config.tickSize)
                        .font(.system(size: 15, weight: .semibold))
                        .fixedSize()
                }
                Text(side == .buy
                     ? "이 값 이하로만 사요. 그때까지 주문이 호가창에서 기다려요 — 슬리피지가 없어요."
                     : "이 값 이상으로만 팔아요. 그때까지 주문이 호가창에서 기다려요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                ForEach([10, 50, 100, 500], id: \.self) { preset in
                    Button {
                        qty = preset
                    } label: {
                        Text("\(preset)주")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(qty == preset ? SeedTheme.inverse : SeedTheme.textPrimary)
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
                            Analytics.log(.tagSelected, ["tag": tag.rawValue])
                        } label: {
                            Text(tag.label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(selectedTag == tag ? SeedTheme.inverse : SeedTheme.textPrimary)
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
                let result: Result<OrderOutcome, OrderError>
                if isLimit {
                    result = session.placeLimitOrder(side: side, price: limitPrice, qty: qty, tag: tag)
                        .map { .limit($0) }
                } else {
                    result = session.placeOrder(side: side, qty: qty)
                        .map { .market($0) }
                }
                session.orderSheetClosed()
                dismiss()
                onComplete(result, tag, avgCostBefore)
            } label: {
                Text(selectedTag == nil ? "이유를 하나 골라주세요" : "\(qty)주 \(isLimit ? "지정가 " : "")\(title)")
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
        .onAppear {
            limitPrice = session.engine.displayedPrice(for: side) ?? session.engine.lastPrice
        }
        .onDisappear { session.orderSheetClosed() }
    }
}

// MARK: - 체결 결과 시트 (슬리피지가 보이는 순간 — 튜토리얼의 씨앗)

struct FillResultSheet: View {
    let fill: FillResult
    var fee: Int = 0
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
                if fill.side == .buy {
                    row("수수료", "\(fee.formatted())원")
                } else {
                    row("수수료 + 세금", "\(fee.formatted())원")
                }
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
                    .foregroundStyle(SeedTheme.inverse)
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
