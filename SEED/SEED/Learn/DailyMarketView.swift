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

    private let scenarioId = DailyMarket.id()
    private let pattern = DailyMarket.pattern()

    /// 시작 기준가 — 첫 캔들이 마감되기 전에도 안전하게 (강제 언랩 크래시 수정)
    private var startPrice: Int {
        engine.candles.first?.open ?? engine.currentCandle.open
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 11))
                    Text("오늘의 장 · 1캔들 = 1일 · 모의")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(SeedTheme.violetDeep)
                Spacer()
                Text("D+\(engine.candles.count)일")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SeedTheme.violetDeep)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("오늘의 종목")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("\(engine.lastPrice.formatted())원")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SeedTheme.pnl(Double(engine.lastPrice - startPrice)))
                    .contentTransition(.numericText())
                Spacer()
                let portfolio = engine.portfolio
                if portfolio.qty > 0 {
                    Text("\(portfolio.qty)주 · 평단 \(Int(portfolio.avgCost).formatted())")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
            }
            .padding(.horizontal, 16).padding(.top, 10)

            ChartCanvas(candles: engine.candles, current: engine.currentCandle,
                        unlockLevel: UnlockLevel.all)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 14)
                .padding(.top, 6)

            if isFinished {
                resultCard
                    .padding(.horizontal, 16).padding(.bottom, 16)
            } else {
                HStack(spacing: 8) {
                    if engine.portfolio.qty > 0 {
                        dailyOrderButton("팔기", color: SeedTheme.down, side: .sell)
                    }
                    dailyOrderButton("사기", color: SeedTheme.up, side: .buy)
                }
                .padding(.horizontal, 14).padding(.bottom, 14)
                .animation(.snappy(duration: 0.25), value: engine.portfolio.qty > 0)
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

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task {
            while !Task.isCancelled {
                if orderSide == nil && !isFinished {
                    engine.step()
                    if engine.isScenarioFinished {
                        isFinished = true
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(28))
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
