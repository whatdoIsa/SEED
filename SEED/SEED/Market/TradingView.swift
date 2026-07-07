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
    @State private var marketTab = 0
    @State private var miniReviewText: String?
    @State private var hasTraded = true
    @State private var newsBanner: (text: String, positive: Bool, marketWide: Bool)?
    @State private var showsCryptoIntro = false
    /// 차트 스타일 (피드백 #2) — 캔들 해금 후 선/캔들 선택, 기기 단위로 기억
    @AppStorage("seed.chartStyle") private var chartStyleRaw = ChartStyle.candle.rawValue
    /// 차트 줌 (핀치) — 보이는 캔들 수, 기기 단위로 기억
    @AppStorage("seed.chartZoom") private var visibleCandles = 40
    @State private var pinchBaseCount: Int?

    private var chartStyle: ChartStyle {
        ChartStyle(rawValue: chartStyleRaw) ?? .candle
    }

    /// 핀치 줌: 벌리면 확대(캔들 수 감소), 오므리면 축소. 20~160캔들.
    private var chartZoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBaseCount ?? visibleCandles
                pinchBaseCount = base
                let scaled = Double(base) / value.magnification
                visibleCandles = min(max(Int(scaled), 20), 160)
            }
            .onEnded { _ in pinchBaseCount = nil }
    }

    /// 이동평균선 범례 (Lv3 해금 후) — 토스와 같은 색 매핑
    private var maLegend: some View {
        HStack(spacing: 6) {
            Text("이동평균선").foregroundStyle(SeedTheme.textSecondary)
            Text("5").foregroundStyle(Color(hex: 0x22C55E))
            Text("20").foregroundStyle(SeedTheme.up)
            Text("60").foregroundStyle(Color(hex: 0xF59E0B))
            Text("120").foregroundStyle(Color(hex: 0x8B5CF6))
            Spacer()
            Text("핀치로 확대·축소")
                .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            symbolPicker
            header
            marketTabPicker
            if marketTab == 0 {
                speedBar
                if store.progress.unlockLevel >= UnlockLevel.volumeAndMA {
                    maLegend
                }
                ChartCanvas(
                    candles: session.engine.candles,
                    current: session.engine.currentCandle,
                    unlockLevel: store.progress.unlockLevel,
                    style: chartStyle,
                    visibleCount: visibleCandles,
                    detailed: true,
                    referencePrice: session.engine.referencePrice,
                    avgCost: session.engine.portfolio.qty > 0 ? session.engine.portfolio.avgCost : nil,
                    candlesPerDay: session.engine.config.candlesPerDay
                )
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 12)
                .gesture(chartZoomGesture)
                lockedToolCards
                openOrdersSection
            } else {
                if store.progress.unlockLevel >= UnlockLevel.orderBook {
                    ScrollView {
                        OrderBookView(engine: session.engine)
                            .padding(.top, 8)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    OrderBookLockedView()
                }
            }
            if let text = miniReviewText {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                    Text(text)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(SeedTheme.violetDeep)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16).padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let news = newsBanner {
                HStack(spacing: 7) {
                    Image(systemName: news.marketWide
                          ? "globe.asia.australia.fill"
                          : (news.positive ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill"))
                        .font(.system(size: 12))
                    Text("\(news.marketWide ? "시장 속보" : "속보") · \(news.text)")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(news.positive ? SeedTheme.up : SeedTheme.down)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(news.positive ? SeedTheme.upTint : SeedTheme.downTint,
                            in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16).padding(.bottom, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let notice = session.limitFillNotice {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text(notice)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(SeedTheme.violetDeep)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16).padding(.bottom, 6)
            }
            if !hasTraded {
                Text("가격이 계속 움직여요. 누가 움직이는 걸까요? 일단 사보세요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
            }
            portfolioStrip
            orderButtons
        }
        .animation(.snappy(duration: 0.3), value: miniReviewText)
        .onAppear { hasTraded = store.tradeCount() > 0 }
        .onChange(of: session.activeSymbolCode) { _, _ in
            // 크립토 첫 진입: 색 규칙·제도 차이 교육 카드 (§16.4)
            if session.activeSpec.isCrypto,
               !UserDefaults.standard.bool(forKey: "seed.cryptoIntroSeen") {
                UserDefaults.standard.set(true, forKey: "seed.cryptoIntroSeen")
                showsCryptoIntro = true
            }
        }
        .sheet(isPresented: $showsCryptoIntro) {
            CryptoIntroSheet()
                .presentationDetents([.height(430)])
        }
        .onChange(of: session.engine.newsFeed.count) { _, _ in
            guard let event = session.engine.latestNews else { return }
            withAnimation(.snappy(duration: 0.3)) {
                newsBanner = (NewsHeadlines.text(for: event), event.isPositive, event.isMarketWide)
            }
            Task {
                try? await Task.sleep(for: .seconds(5))
                withAnimation(.easeOut(duration: 0.3)) { newsBanner = nil }
            }
        }
        .background(SeedTheme.background)
        .task { session.start() }
        .sheet(item: $orderSide) { side in
            OrderSheet(session: session, side: side,
                       allowsLimit: store.progress.unlockLevel >= UnlockLevel.orderBook) { result, tag, avgCostBefore in
                switch result {
                case .success(.market(let fill)):
                    store.record(fill: fill, tag: tag, symbol: session.activeSpec.name,
                                 avgCostBeforeOrder: avgCostBefore,
                                 atTick: session.engine.tick,
                                 atCandleIndex: session.engine.candles.count)
                    session.persistState()
                    lastFill = fill
                    if !hasTraded {
                        // 첫 매매 — 의미 있는 순간에 주간 복기 알림 권한을 묻는다 (B)
                        SeedNotifications.requestThenScheduleWeekly(
                            weeklyTradeCount: store.weeklyTradeCount())
                    }
                    hasTraded = true
                    showMiniReview(store.miniReview(for: tag))
                case .success(.limit(let limitResult)):
                    if let immediate = limitResult.immediateFill {
                        store.record(fill: immediate, tag: tag, symbol: session.activeSpec.name,
                                     avgCostBeforeOrder: avgCostBefore,
                                     atTick: session.engine.tick,
                                     atCandleIndex: session.engine.candles.count,
                                     wasLimit: true)
                        lastFill = immediate
                        hasTraded = true
                    }
                    if let resting = limitResult.restingOrder {
                        showMiniReview("지정가 접수 · \(resting.remainingQty)주 대기 중 — 체결되면 알려드릴게요")
                    }
                    session.persistState()
                case .failure(let error):
                    orderErrorMessage = message(for: error)
                }
            }
            .presentationDetents([.height(470)])
        }
        .sheet(item: $lastFill) { fill in
            FillResultSheet(
                fill: fill,
                fee: fill.side == .buy
                    ? session.engine.config.buyFee(on: fill.notional)
                    : session.engine.config.sellFee(on: fill.notional)
            )
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

    // MARK: 종목 선택 (다종목)

    private var symbolPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SymbolCatalog.all) { spec in
                    let selected = session.activeSymbolCode == spec.code
                    Button {
                        session.activeSymbolCode = spec.code
                    } label: {
                        Text(spec.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selected ? SeedTheme.inverse : SeedTheme.textSecondary)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(selected ? SeedTheme.textPrimary : SeedTheme.card, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(session.activeSpec.name)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("모의")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SeedTheme.violet)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .overlay(Capsule().stroke(SeedTheme.violet, lineWidth: 1))
                Text(session.activeSpec.isCrypto ? "24시간 시장" : "D+\(session.engine.tradingDay)일차")
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.textSecondary)
                Spacer()
                #if DEBUG
                Menu {
                    ForEach([0, 1, 2, 3, 9], id: \.self) { level in
                        Button("Lv\(level)") { store.debugSetUnlockLevel(level) }
                    }
                } label: {
                    Text("Lv\(store.progress.unlockLevel)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SeedTheme.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(SeedTheme.card, in: Capsule())
                }
                #endif
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

    // MARK: 미체결 주문 (① — 내 주문이 호가창에 앉아 기다린다)

    @ViewBuilder
    private var openOrdersSection: some View {
        let orders = session.engine.openOrders
        if !orders.isEmpty {
            VStack(spacing: 6) {
                ForEach(orders) { order in
                    HStack(spacing: 10) {
                        Text(order.side == .buy ? "매수 대기" : "매도 대기")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(order.side == .buy ? SeedTheme.up : SeedTheme.down)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(order.side == .buy ? SeedTheme.upTint : SeedTheme.downTint,
                                        in: RoundedRectangle(cornerRadius: 6))
                        Text("\(order.price.formatted())원 · \(order.remainingQty)주")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SeedTheme.textPrimary)
                        Spacer()
                        Button {
                            session.cancelOrder(id: order.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 11))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    // MARK: 차트 | 호가 전환

    private var marketTabPicker: some View {
        HStack(spacing: 16) {
            ForEach(Array(["차트", "호가"].enumerated()), id: \.offset) { index, title in
                Button {
                    marketTab = index
                } label: {
                    VStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: 14, weight: marketTab == index ? .semibold : .regular))
                            .foregroundStyle(marketTab == index ? SeedTheme.textPrimary : SeedTheme.textSecondary)
                        Rectangle()
                            .fill(marketTab == index ? SeedTheme.textPrimary : .clear)
                            .frame(height: 2)
                    }
                    .fixedSize()
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: 잠긴 도구 카드 (§10.1) — 존재를 보여줘 다음 레슨의 동기가 되게 한다

    private var lockedToolCards: some View {
        let level = store.progress.unlockLevel
        return VStack(spacing: 6) {
            if level < UnlockLevel.candles {
                lockedCard("캔들 차트", hint: "레슨 1에서 해금")
            }
            if level < UnlockLevel.orderBook {
                lockedCard("호가창 · 체결", hint: "레슨 2에서 해금")
            }
            if level < UnlockLevel.volumeAndMA {
                lockedCard("거래량 · 이동평균선", hint: "레슨 3에서 해금")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func lockedCard(_ title: String, hint: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
            Text(title)
                .font(.system(size: 13))
            Spacer()
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(SeedTheme.textSecondary.opacity(0.7))
        }
        .foregroundStyle(SeedTheme.textSecondary)
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
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
                        .foregroundStyle(session.speed == speed ? SeedTheme.inverse : SeedTheme.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(
                            session.speed == speed ? SeedTheme.textPrimary : SeedTheme.card,
                            in: Capsule()
                        )
                }
            }
            Button {
                session.skipToNextCandle()
            } label: {
                Label("다음 캔들", systemImage: "chevron.right.2")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(SeedTheme.card, in: Capsule())
            }
            Spacer()
            // 선/캔들 토글 (피드백 #2) — 캔들을 배운(해금한) 뒤에만 선택권이 생긴다
            if store.progress.unlockLevel >= UnlockLevel.candles {
                Button {
                    chartStyleRaw = (chartStyle == .candle ? ChartStyle.line : .candle).rawValue
                } label: {
                    Image(systemName: chartStyle == .candle
                          ? "chart.bar.fill"
                          : "chart.xyaxis.line")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SeedTheme.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(SeedTheme.card, in: Capsule())
                }
            }
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
    // 이 종목을 보유하기 전엔 팔기 버튼이 존재하지 않는다 — 팔 게 없으니까.

    private var orderButtons: some View {
        HStack(spacing: 8) {
            if session.engine.portfolio.qty > 0 {
                orderButton("팔기", color: SeedTheme.down, side: .sell)
            }
            orderButton("사기", color: SeedTheme.up, side: .buy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .animation(.snappy(duration: 0.25), value: session.engine.portfolio.qty > 0)
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

    private func showMiniReview(_ text: String) {
        miniReviewText = text
        Task {
            try? await Task.sleep(for: .seconds(4))
            miniReviewText = nil
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
        case .priceOutOfBand(let lower, let upper):
            return "오늘 주문 가능한 범위는 \(lower.formatted())원(하한가) ~ \(upper.formatted())원(상한가)이에요."
        }
    }
}
