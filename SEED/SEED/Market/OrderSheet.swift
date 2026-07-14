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
    /// 예상 금액의 기준 단가 — 지정가는 주문 가격, 시장가는 지금 보이는 최우선 호가
    private var estimatedUnitPrice: Int {
        isLimit ? limitPrice : (session.engine.displayedPrice(for: side) ?? session.engine.lastPrice)
    }
    /// 내용 실측 높이 — 시트가 내용만큼만 뜬다 (빈 공간 제거)
    @State private var measuredHeight: CGFloat = 470

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

            // 보유 현황 — 특히 팔 때 "내가 몇 주 갖고 있더라"를 시트 안에서 바로
            if session.engine.portfolio.qty > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "briefcase.fill")
                        .font(.system(size: 10))
                    Text("보유 \(session.engine.portfolio.qty)주 · 평단 \(Int(session.engine.portfolio.avgCost).formatted())원")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(SeedTheme.textSecondary)
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

            // 500주 프리셋은 뺐다 — 시작 자금 1,000만원으로 닿을 일이 없는 숫자라서
            HStack(spacing: 8) {
                ForEach([10, 50, 100], id: \.self) { preset in
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
                // 전량 매도 — 예약(대기 주문) 물량은 제외한 팔 수 있는 전부
                if side == .sell {
                    let sellable = session.engine.portfolio.availableShares
                    Button {
                        qty = max(sellable, 1)
                    } label: {
                        Text("전부")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(qty == sellable && sellable > 0
                                             ? SeedTheme.inverse : SeedTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                qty == sellable && sellable > 0
                                    ? SeedTheme.textPrimary : SeedTheme.card,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                }
            }

            Stepper("수량 \(qty)주", value: $qty,
                    in: 1...(side == .sell
                             ? max(session.engine.portfolio.availableShares, 1)
                             : 10_000),
                    step: 10)
                .font(.system(size: 14))

            // 수량을 고르는 순간 돈으로 보여준다 — "몇 주"가 아니라 "얼마"가 결정의 단위
            VStack(spacing: 4) {
                HStack {
                    Text(side == .buy ? "예상 주문 금액" : "예상 매도 금액")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textSecondary)
                    Spacer()
                    Text("약 \((estimatedUnitPrice * qty).formatted())원")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.2), value: qty)
                }
                if !isLimit {
                    Text("시장가는 체결 순간의 호가에 따라 조금 달라질 수 있어요 (수수료 별도)")
                        .font(.system(size: 11))
                        .foregroundStyle(SeedTheme.textSecondary.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))

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
        .padding(.vertical, 16)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            measuredHeight = height
        }
        .presentationDetents([.height(measuredHeight + 14)]) // 그랩바 여유
        .animation(.snappy(duration: 0.25), value: measuredHeight)
        .onAppear {
            limitPrice = session.engine.displayedPrice(for: side) ?? session.engine.lastPrice
        }
        .onDisappear { session.orderSheetClosed() }
    }
}

// MARK: - 체결 결과 시트 (슬리피지가 보이는 순간 — 튜토리얼의 씨앗)

struct FillResultSheet: View {
    @State private var measuredHeight: CGFloat = 340
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
        .padding(.vertical, 18)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            measuredHeight = height
        }
        .presentationDetents([.height(measuredHeight + 14)]) // 그랩바 여유
        .animation(.snappy(duration: 0.25), value: measuredHeight)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(SeedTheme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 14, weight: .medium)).foregroundStyle(SeedTheme.textPrimary)
        }
    }
}

// MARK: - 주문 오류 → 사용자 문구 (주식·ETF 화면 공용)

extension OrderError {
    /// unit: 주식 "주" / ETF "좌"
    func userMessage(unit: String = "주") -> String {
        switch self {
        case .insufficientCash(let needed, let available):
            return "현금이 부족해요. 필요 \(needed.formatted())원 / 보유 \(available.formatted())원"
        case .insufficientHoldings(let requested, let held):
            return "보유한 수량이 부족해요. 주문 \(requested)\(unit) / 보유 \(held)\(unit)"
        case .noLiquidity:
            return "지금은 살 수 있는 물량이 없어요. 잠시 뒤 다시 해봐요."
        case .invalidQuantity:
            return "수량을 확인해 주세요."
        case .priceOutOfBand(let lower, let upper):
            return "오늘 주문 가능한 범위는 \(lower.formatted())원(하한가) ~ \(upper.formatted())원(상한가)이에요."
        case .auctionInProgress:
            return "지금은 동시호가 시간이에요 — 주문을 모아 하나의 가격으로 체결해요. 지정가로 참여하거나 잠시 기다려주세요."
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
