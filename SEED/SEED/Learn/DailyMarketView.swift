import SwiftUI
import JurinKit

/// 오늘의 장 (⑦) — 압축 시간 자유 매매. 끝나면 패턴 이름과 한 줄 교훈이 공개된다.
struct DailyMarketView: View {
    let store: SeedStore
    @Environment(\.dismiss) private var dismiss

    @State private var engine = MarketEngine(scenario: DailyMarket.scenario())
    @State private var isFinished = false
    @State private var orderSide: Side?
    @State private var loop: Task<Void, Never>?
    @State private var isPaused = false
    @State private var speed = 1  // 1x/2x/4x

    private let scenarioId = DailyMarket.id()
    private let pattern = DailyMarket.pattern()
    private let preset = DailyMarket.scenario()

    private var totalCandles: Int { preset.durationTicks / engine.config.ticksPerCandle }
    private var tickDelayMs: Int { [1: 45, 2: 24, 4: 12][speed] ?? 45 }

    /// 시작 기준가 — 첫 캔들이 마감되기 전에도 안전하게 (강제 언랩 크래시 수정)
    private var startPrice: Int {
        engine.candles.first?.open ?? engine.currentCandle.open
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더: 제목 + 진행바 + 닫기
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 11))
                    Text("오늘의 장")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(SeedTheme.violetDeep)
                // 진행바: 오늘 장이 어디까지 왔는지 한눈에
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(SeedTheme.band).frame(height: 4)
                        Capsule().fill(SeedTheme.violet)
                            .frame(width: geo.size.width
                                   * CGFloat(min(engine.candles.count, totalCandles))
                                   / CGFloat(totalCandles),
                                   height: 4)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 14)
                Text("D+\(engine.candles.count)/\(totalCandles)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .monospacedDigit()
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
            .padding(.horizontal, 16).padding(.top, 12)

            // 가격 + 내 포지션 (평가손익 포함)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(engine.lastPrice.formatted())원")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(SeedTheme.pnl(Double(engine.lastPrice - startPrice)))
                    .contentTransition(.numericText())
                let changePct = startPrice > 0
                    ? Double(engine.lastPrice - startPrice) / Double(startPrice) * 100 : 0
                Text("\(changePct >= 0 ? "+" : "")\(changePct.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SeedTheme.pnl(changePct))
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 8)

            let portfolio = engine.portfolio
            if portfolio.qty > 0 {
                let unrealizedPct = portfolio.avgCost > 0
                    ? (Double(engine.lastPrice) - portfolio.avgCost) / portfolio.avgCost * 100 : 0
                HStack(spacing: 8) {
                    Text("\(portfolio.qty)주 · 평단 \(Int(portfolio.avgCost).formatted())원")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SeedTheme.textSecondary)
                    Text("\(unrealizedPct >= 0 ? "+" : "")\(unrealizedPct.formatted(.number.precision(.fractionLength(1))))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SeedTheme.pnl(unrealizedPct))
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 2)
            }

            // 상세 차트 (축·기준선·평단선)
            ChartCanvas(candles: engine.candles, current: engine.currentCandle,
                        unlockLevel: UnlockLevel.all,
                        detailed: true,
                        referencePrice: startPrice,
                        avgCost: portfolio.qty > 0 ? portfolio.avgCost : nil,
                        candlesPerDay: 0)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 14)
                .padding(.top, 16) // 최고 콜아웃·첫 캔들이 헤더 가격과 겹치지 않게

            if isFinished {
                resultCard
                    .padding(.horizontal, 16).padding(.bottom, 16)
            } else {
                // 시간 컨트롤: 일시정지 + 배속 — 생각할 시간은 사용자가 정한다
                HStack(spacing: 8) {
                    Button {
                        isPaused.toggle()
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SeedTheme.inverse)
                            .frame(width: 40, height: 32)
                            .background(SeedTheme.textPrimary, in: Capsule())
                    }
                    ForEach([1, 2, 4], id: \.self) { value in
                        Button {
                            speed = value
                            isPaused = false
                        } label: {
                            Text("\(value)x")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(speed == value && !isPaused
                                                 ? SeedTheme.inverse : SeedTheme.textSecondary)
                                .padding(.horizontal, 13).padding(.vertical, 7)
                                .background(speed == value && !isPaused
                                            ? SeedTheme.textPrimary : SeedTheme.card,
                                            in: Capsule())
                        }
                    }
                    Spacer()
                    if isPaused {
                        Text("멈춤 — 차트를 천천히 보세요")
                            .font(.system(size: 11))
                            .foregroundStyle(SeedTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 4)

                HStack(spacing: 8) {
                    if portfolio.qty > 0 {
                        dailyOrderButton("팔기", color: SeedTheme.down, side: .sell)
                    }
                    dailyOrderButton("사기", color: SeedTheme.up, side: .buy)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .animation(.snappy(duration: 0.25), value: portfolio.qty > 0)
            }
        }
        .background(SeedTheme.background)
        .task { startLoop() }
        .onDisappear { loop?.cancel() }
        .sheet(item: $orderSide) { side in
            DailyOrderSheet(engine: engine, side: side) { fill, tag, avgCostBefore in
                store.record(fill: fill, tag: tag, avgCostBeforeOrder: avgCostBefore,
                             scenarioId: scenarioId)
            }
            .presentationDetents([.height(340)])
        }
    }

    private func dailyOrderButton(_ title: String, color: Color, side: Side) -> some View {
        Button {
            orderSide = side
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(color, in: RoundedRectangle(cornerRadius: 13))
        }
    }

    // MARK: 결과 — 패턴 공개 + 교훈 한 줄

    private var resultCard: some View {
        let pnl = engine.portfolio.equity(at: engine.lastPrice) - engine.config.initialCash
        return VStack(alignment: .leading, spacing: 10) {
            Text("오늘의 장은 '\(pattern.revealName)'이었어요")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SeedTheme.inkText)
            HStack {
                Text("오늘의 손익")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.inkText.opacity(0.75))
                Spacer()
                Text("\(pnl >= 0 ? "+" : "")\(pnl.formatted())원")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(pnl >= 0 ? Color(hex: 0xFF8A93) : Color(hex: 0x8FBAFF))
            }
            Text(pattern.lessonLine)
                .font(.system(size: 14))
                .foregroundStyle(SeedTheme.inkText)
                .lineSpacing(5)
            // AI 해설: 장 완료 시 1회, 날짜 키 캐시 (재방문 무료)
            AICoachCard(
                cacheKey: "daily.\(DailyMarket.dayStamp())",
                fingerprint: "\(pnl)",
                prompt: dailyPrompt(pnl: pnl),
                maxTokens: 200
            )
            // 공유 카드 — 오늘 판을 포함한 스트릭으로 렌더
            if let card = DailyShareCard.render(
                patternName: pattern.revealName,
                lessonLine: pattern.lessonLine,
                pnl: pnl,
                streak: DailyMarket.streak(
                    completed: store.completedLessonIds.union([scenarioId]))
            ) {
                ShareLink(item: card,
                          preview: SharePreview("오늘의 장 · \(pattern.revealName)", image: card)) {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                        Text("오늘 결과 공유하기")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(SeedTheme.violetOnDark)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(SeedTheme.violetOnDark.opacity(0.5), lineWidth: 1.2))
                }
            }
            Button {
                store.completeLesson(scenarioId, unlocksLevel: nil)
                SeedNotifications.cancelTodayEveningReminder()
                // 3일 연속 달성 — 출시 초기 가장 빨리 오는 만족 순간에 평가 요청
                if DailyMarket.streak(completed: store.completedLessonIds) >= 3 {
                    ReviewPrompt.askIfEligible(.streak3)
                }
                dismiss()
            } label: {
                Text("오늘 장 마감 · 내일 또 열려요")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SeedTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(SeedTheme.inkText, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(SeedTheme.ink, in: RoundedRectangle(cornerRadius: 16))
    }

    private func dailyPrompt(pnl: Int) -> String {
        let myTrades = store.scenarioLogs(scenarioId: scenarioId)
        var lines = ["오늘의 학습 장이 끝났어. 오늘 장 해설을 두세 문장으로 해줘. 데이터:"]
        lines.append("- 오늘 장의 패턴: \(pattern.revealName)")
        lines.append("- 내 손익: \(pnl >= 0 ? "+" : "")\(pnl.formatted())원, 매매 \(myTrades.count)건")
        for log in myTrades.prefix(5) {
            lines.append("- \(log.side == .buy ? "매수" : "매도") \(log.qty)주 @\(Int(log.avgFillPrice).formatted())원 (이유: \(log.reasonTag.label))")
        }
        if myTrades.isEmpty { lines.append("- 오늘은 매매하지 않고 지켜봤음") }
        lines.append("이 패턴에서 내 행동이 어땠는지 짚어줘.")
        return lines.joined(separator: "\n")
    }

    private func startLoop() {
        guard loop == nil else { return }
        // 워밍업: 과거 캔들을 그린 상태로 시작 — 빈 차트에 거대 막대가 쌓이는 혼란 방지
        if engine.tick == 0 { engine.advance(ticks: 160) }
        loop = Task {
            while !Task.isCancelled {
                // 주문 시트가 열려 있거나 일시정지면 시장도 멈춘다 — 생각할 시간 보장
                if orderSide == nil && !isFinished && !isPaused {
                    engine.step()
                    if engine.isScenarioFinished {
                        isFinished = true
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(tickDelayMs))
            }
        }
    }
}

// MARK: - 오늘의 장 전용 주문 시트 (시장가 + 태그 1탭)

struct DailyOrderSheet: View {
    let engine: MarketEngine
    let side: Side
    let onFill: (FillResult, TradeReasonTag, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var qty = 50
    @State private var selectedTag: TradeReasonTag?
    @State private var errorMessage: String?

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
                if let displayed = engine.displayedPrice(for: side) {
                    Text("지금 \(displayed.formatted())원")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
            }

            HStack(spacing: 8) {
                ForEach([50, 100, 300], id: \.self) { preset in
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

            HStack(spacing: 6) {
                ForEach(TradeReasonTag.tags(for: side), id: \.rawValue) { tag in
                    Button {
                        selectedTag = tag
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
            .frame(maxWidth: .infinity, alignment: .leading)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.down)
            }

            Button {
                guard let tag = selectedTag else { return }
                let avgCostBefore = engine.portfolio.avgCost
                do {
                    let fill = try engine.placeMarketOrder(side: side, qty: qty)
                    onFill(fill, tag, avgCostBefore)
                    dismiss()
                } catch {
                    errorMessage = "주문이 안 됐어요. 현금·보유 수량을 확인해요."
                }
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
    }
}
