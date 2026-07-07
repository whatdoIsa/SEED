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

// MARK: - 캔들 차트 (Canvas)

/// 차트 표시 방식 — 캔들 해금 후에는 사용자가 고를 수 있다 (피드백 #2).
/// 차트 표시 방식 — 캔들 해금 후에는 사용자가 고를 수 있다.
enum ChartStyle: String {
    case line, candle
}

/// 메인 차트 (토스급 디테일 + 핀치 줌).
/// detailed = true면 Y축 눈금·현재가/평단 배지·최고/최저 콜아웃·거래일 축·거래량 배지를 그린다.
/// 미션·비교 화면들은 detailed = false로 기존의 담백한 모습을 유지한다.
struct ChartCanvas: View {
    let candles: [Candle]
    let current: Candle
    var unlockLevel: Int = UnlockLevel.all
    var style: ChartStyle = .candle
    var visibleCount: Int = 40
    var detailed: Bool = false
    var referencePrice: Int? = nil
    var avgCost: Double? = nil
    var candlesPerDay: Int = 0

    private var showsCandles: Bool { unlockLevel >= UnlockLevel.candles && style == .candle }
    private var showsVolumeAndMA: Bool { unlockLevel >= UnlockLevel.volumeAndMA }

    // MARK: 좌표계

    private struct Metrics {
        let all: [Candle]
        let plotWidth: CGFloat
        let axisX: CGFloat
        let chartHeight: CGFloat
        let volumeTop: CGFloat
        let volumeHeight: CGFloat
        let timeAxisY: CGFloat
        let slot: CGFloat
        let bodyWidth: CGFloat
        let low: Int
        let high: Int
        let maxVolume: Int

        func y(_ price: Int) -> CGFloat { yD(Double(price)) }
        func yD(_ price: Double) -> CGFloat {
            let range = Double(max(high - low, 1))
            return chartHeight * (1 - CGFloat((price - Double(low)) / range))
        }
        func x(_ index: Int) -> CGFloat { slot * (CGFloat(index) + 0.5) }
    }

    private func metrics(for size: CGSize) -> Metrics? {
        let all = Array(candles.suffix(max(visibleCount - 1, 1))) + [current]
        guard !all.isEmpty else { return nil }

        let axisWidth: CGFloat = detailed ? 62 : 0
        let bottomAxis: CGFloat = (detailed && candlesPerDay > 0) ? 14 : 0
        let plotWidth = size.width - axisWidth
        let height = size.height - bottomAxis

        let chartHeight = showsVolumeAndMA ? height * (detailed ? 0.70 : 0.78) : height
        let volumeTop = height * (detailed ? 0.75 : 0.82)
        let volumeHeight = height - volumeTop

        var low = all.map(\.low).min() ?? 0
        var high = all.map(\.high).max() ?? 1
        if let avgCost, avgCost > 0 {
            low = min(low, Int(avgCost))
            high = max(high, Int(avgCost))
        }
        let slot = plotWidth / CGFloat(max(visibleCount, 1))
        return Metrics(
            all: all, plotWidth: plotWidth, axisX: plotWidth,
            chartHeight: chartHeight, volumeTop: volumeTop, volumeHeight: volumeHeight,
            timeAxisY: size.height - 7,
            slot: slot, bodyWidth: max(slot * 0.62, 1.5),
            low: low, high: high,
            maxVolume: max(all.map(\.volume).max() ?? 1, 1)
        )
    }

    var body: some View {
        Canvas { context, size in
            guard let m = metrics(for: size) else { return }
            if detailed {
                drawGridAndAxis(context, m)
                drawDaySeparators(context, m)
            }
            if showsCandles {
                drawCandles(context, m)
            } else {
                drawLine(context, m)
            }
            if showsVolumeAndMA {
                drawVolume(context, m)
                drawMA(m.all.movingAverage(period: 5), color: Color(hex: 0x22C55E), context, m)
                drawMA(m.all.movingAverage(period: 20), color: SeedTheme.up, context, m)
                if detailed {
                    drawMA(m.all.movingAverage(period: 60), color: Color(hex: 0xF59E0B), context, m)
                    drawMA(m.all.movingAverage(period: 120), color: Color(hex: 0x8B5CF6), context, m)
                }
            }
            if detailed {
                drawAvgCostLine(context, m)
                drawExtremeCallouts(context, m)
                drawCurrentPriceBadge(context, m)
            }
        }
    }

    // MARK: 가격·캔들·선

    private func drawCandles(_ context: GraphicsContext, _ m: Metrics) {
        for (i, candle) in m.all.enumerated() {
            let x = m.x(i)
            let color = candle.isBullish ? SeedTheme.up : SeedTheme.down

            var wick = Path()
            wick.move(to: CGPoint(x: x, y: m.y(candle.high)))
            wick.addLine(to: CGPoint(x: x, y: m.y(candle.low)))
            context.stroke(wick, with: .color(color), lineWidth: 1)

            let top = m.y(max(candle.open, candle.close))
            let bottom = m.y(min(candle.open, candle.close))
            let body = CGRect(x: x - m.bodyWidth / 2, y: top,
                              width: m.bodyWidth, height: max(bottom - top, 1.5))
            context.fill(Path(roundedRect: body, cornerRadius: 1), with: .color(color))
        }
    }

    private func drawLine(_ context: GraphicsContext, _ m: Metrics) {
        var line = Path()
        for (i, candle) in m.all.enumerated() {
            let point = CGPoint(x: m.x(i), y: m.y(candle.close))
            if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
        }
        let rising = (m.all.last?.close ?? 0) >= (m.all.first?.close ?? 0)
        let color = rising ? SeedTheme.up : SeedTheme.down
        context.stroke(line, with: .color(color),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        if let last = m.all.last {
            let dot = CGRect(x: m.x(m.all.count - 1) - 4, y: m.y(last.close) - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: dot), with: .color(color))
        }
    }

    private func drawMA(_ values: [Double?], color: Color,
                        _ context: GraphicsContext, _ m: Metrics) {
        var path = Path()
        var started = false
        for (i, value) in values.enumerated() {
            guard let value else { continue }
            let point = CGPoint(x: m.x(i), y: m.yD(value))
            if started { path.addLine(to: point) } else { path.move(to: point); started = true }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.2)
    }

    // MARK: 거래량

    private func drawVolume(_ context: GraphicsContext, _ m: Metrics) {
        for (i, candle) in m.all.enumerated() {
            let color = candle.isBullish ? SeedTheme.up : SeedTheme.down
            let barHeight = m.volumeHeight * CGFloat(candle.volume) / CGFloat(m.maxVolume)
            let rect = CGRect(x: m.x(i) - m.bodyWidth / 2,
                              y: m.volumeTop + (m.volumeHeight - barHeight),
                              width: m.bodyWidth, height: barHeight)
            context.fill(Path(rect), with: .color(color.opacity(0.35)))
        }
        guard detailed else { return }

        // 거래량 이동평균 (초록 선) — 평소 대비 얼마나 뜨거운가
        let volumes = m.all.map(\.volume)
        var volMA = Path()
        var started = false
        let period = 20
        var windowSum = 0
        for (i, volume) in volumes.enumerated() {
            windowSum += volume
            if i >= period { windowSum -= volumes[i - period] }
            guard i >= period - 1 else { continue }
            let avg = Double(windowSum) / Double(period)
            let y = m.volumeTop + m.volumeHeight * (1 - CGFloat(avg / Double(m.maxVolume)))
            let point = CGPoint(x: m.x(i), y: y)
            if started { volMA.addLine(to: point) } else { volMA.move(to: point); started = true }
        }
        context.stroke(volMA, with: .color(Color(hex: 0x22C55E)), lineWidth: 1.2)

        context.draw(
            Text("거래량 (20)").font(.system(size: 9, weight: .medium))
                .foregroundStyle(SeedTheme.textSecondary),
            at: CGPoint(x: 6, y: m.volumeTop + 8), anchor: .leading
        )
        // 현재 거래량 배지
        let currentVolume = m.all.last?.volume ?? 0
        let barY = m.volumeTop + m.volumeHeight * (1 - CGFloat(currentVolume) / CGFloat(m.maxVolume))
        let color = (m.all.last?.isBullish ?? true) ? SeedTheme.up : SeedTheme.down
        drawBadge(context, text: compactVolume(currentVolume), color: color,
                  y: min(max(barY, m.volumeTop + 8), m.volumeTop + m.volumeHeight - 8), m: m)
    }

    private func compactVolume(_ volume: Int) -> String {
        volume >= 1_000 ? String(format: "%.1fK", Double(volume) / 1_000) : "\(volume)"
    }

    // MARK: 디테일 — 눈금·배지·콜아웃·거래일

    private func drawGridAndAxis(_ context: GraphicsContext, _ m: Metrics) {
        let range = max(m.high - m.low, 1)
        let step = niceStep(for: range)
        var price = (m.low / step + 1) * step
        while price < m.high {
            let y = m.y(price)
            if y > 8 && y < m.chartHeight - 4 {
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: m.plotWidth, y: y))
                context.stroke(grid, with: .color(SeedTheme.band), lineWidth: 1)
                context.draw(
                    Text(price.formatted()).font(.system(size: 10))
                        .foregroundStyle(SeedTheme.textSecondary),
                    at: CGPoint(x: m.axisX + 6, y: y), anchor: .leading
                )
            }
            price += step
        }
    }

    private func niceStep(for range: Int) -> Int {
        let target = max(range / 4, 1)
        var magnitude = 1
        while magnitude * 10 <= target { magnitude *= 10 }
        for multiplier in [1, 2, 5, 10] where multiplier * magnitude >= target {
            return multiplier * magnitude
        }
        return magnitude * 10
    }

    private func drawBadge(_ context: GraphicsContext, text: String, color: Color,
                           y: CGFloat, m: Metrics) {
        let rect = CGRect(x: m.axisX + 2, y: y - 9, width: 58, height: 18)
        context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(color))
        context.draw(
            Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white),
            at: CGPoint(x: rect.midX, y: rect.midY)
        )
    }

    private func drawCurrentPriceBadge(_ context: GraphicsContext, _ m: Metrics) {
        guard let last = m.all.last else { return }
        let reference = referencePrice ?? last.open
        let color = last.close >= reference ? SeedTheme.up : SeedTheme.down
        // 현재가까지 점선 가이드
        var guide = Path()
        let y = m.y(last.close)
        guide.move(to: CGPoint(x: 0, y: y))
        guide.addLine(to: CGPoint(x: m.plotWidth, y: y))
        context.stroke(guide, with: .color(color.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        drawBadge(context, text: last.close.formatted(), color: color,
                  y: min(max(y, 9), m.chartHeight - 9), m: m)
    }

    private func drawAvgCostLine(_ context: GraphicsContext, _ m: Metrics) {
        guard let avgCost, avgCost > 0 else { return }
        let y = m.yD(avgCost)
        guard y > 0 && y < m.chartHeight else { return }

        var line = Path()
        line.move(to: CGPoint(x: 0, y: y))
        line.addLine(to: CGPoint(x: m.plotWidth, y: y))
        context.stroke(line, with: .color(SeedTheme.textSecondary),
                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        context.draw(
            Text("내 주식 평균").font(.system(size: 9, weight: .medium))
                .foregroundStyle(SeedTheme.textSecondary),
            at: CGPoint(x: 6, y: y - 8), anchor: .leading
        )
        // 현재가 배지와 겹치면 아래로 비켜난다
        var badgeY = min(max(y, 9), m.chartHeight - 9)
        if let last = m.all.last, abs(m.y(last.close) - badgeY) < 19 {
            badgeY = m.y(last.close) + 19
        }
        drawBadge(context, text: Int(avgCost).formatted(),
                  color: SeedTheme.textSecondary, y: badgeY, m: m)
    }

    private func drawExtremeCallouts(_ context: GraphicsContext, _ m: Metrics) {
        guard m.all.count > 3 else { return }
        let highest = m.all.enumerated().max { $0.element.high < $1.element.high }
        let lowest = m.all.enumerated().min { $0.element.low < $1.element.low }
        if let highest {
            let x = min(max(m.x(highest.offset), 30), m.plotWidth - 30)
            context.draw(
                Text("최고 \(highest.element.high.formatted())")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(SeedTheme.up),
                at: CGPoint(x: x, y: max(m.y(highest.element.high) - 9, 6))
            )
        }
        if let lowest {
            let x = min(max(m.x(lowest.offset), 30), m.plotWidth - 30)
            context.draw(
                Text("최저 \(lowest.element.low.formatted())")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(SeedTheme.down),
                at: CGPoint(x: x, y: min(m.y(lowest.element.low) + 9, m.chartHeight - 6))
            )
        }
    }

    private func drawDaySeparators(_ context: GraphicsContext, _ m: Metrics) {
        guard candlesPerDay > 0 else { return }
        for (i, candle) in m.all.enumerated()
        where candle.index > 0 && candle.index % candlesPerDay == 0 {
            let x = m.x(i)
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: m.volumeTop + m.volumeHeight))
            context.stroke(line, with: .color(SeedTheme.band), lineWidth: 1)
            context.draw(
                Text("D+\(candle.index / candlesPerDay + 1)")
                    .font(.system(size: 9)).foregroundStyle(SeedTheme.textSecondary),
                at: CGPoint(x: x, y: m.timeAxisY)
            )
        }
    }
}

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
