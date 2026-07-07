import SwiftUI
import JurinKit

/// 슬리피지 튜토리얼 (M3-3, 부록 A-3) — 엔진의 존재 증명.
/// 감정 곡선: 도발 → 체결(호가 소진 연출) → 충격(평균가 공개) → 깨달음.
/// 숫자는 연출이 아니라 실제 OrderBook 매칭 결과다.
struct SlippageMissionView: View {
    let onSuccess: () -> Void

    private enum Stage {
        case provoke, filling, shock, insight
    }
    @State private var stage: Stage = .provoke
    @State private var consumedCount = 0

    /// 정본 케이스: 150@52,300 + 250@52,400 + 300@52,500 + 300@52,550
    private let result: FillResult
    private let ladder: [(price: Int, qty: Int)]

    init(onSuccess: @escaping () -> Void) {
        self.onSuccess = onSuccess
        // 진짜 호가창에 진짜 주문을 넣어 결과를 만든다 — 52,460원은 계산된 값이다.
        let book = OrderBook()
        let asks: [(Int, Int)] = [(52_300, 150), (52_400, 250), (52_500, 300), (52_550, 300)]
        for (price, qty) in asks {
            book.submitLimit(agentId: "S", side: .sell, price: price, qty: qty, tick: 0)
        }
        let displayed = book.bestAsk ?? 52_300
        let (fills, _) = book.executeMarket(agentId: "USER", side: .buy, qty: 1_000, tick: 1)
        self.result = FillResult(side: .buy, requestedQty: 1_000, fills: fills, displayedPrice: displayed)
        self.ladder = asks.reversed() // 위에서 아래로: 비싼 호가 → 최우선
    }

    var body: some View {
        VStack(spacing: 0) {
            switch stage {
            case .provoke, .filling:
                ladderStage
            case .shock:
                shockStage
            case .insight:
                insightStage
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: 1·2단계 — 호가 사다리와 소진 연출

    private var ladderStage: some View {
        VStack(spacing: 0) {
            HStack {
                Text("매도호가 · 잔량")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                Spacer()
                if stage == .filling {
                    Text("호가를 먹으며 올라가는 중")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SeedTheme.up)
                }
            }
            .padding(.top, 18)

            VStack(spacing: 6) {
                ForEach(Array(ladder.enumerated()), id: \.offset) { index, level in
                    // ladder는 비싼 것부터이므로 소진 순서(싼 것부터)는 뒤에서부터
                    let consumeOrder = ladder.count - 1 - index
                    let consumed = consumeOrder < consumedCount
                    ladderRow(price: level.price, qty: level.qty,
                              highlight: consumeOrder == 0 && stage == .provoke,
                              consumed: consumed)
                }
            }
            .padding(.top, 10)

            if stage == .provoke {
                coachCard {
                    Text("겁내지 말고 ")
                    + Text("크게").bold()
                    + Text(" 질러봐요. 진짜 돈 아니에요.\n최우선 호가는 ")
                    + Text("150주").foregroundStyle(SeedTheme.violetOnDark).bold()
                    + Text("뿐인데, 1,000주를 사면 어떻게 될까요?")
                }
                .padding(.top, 18)
            }

            if stage == .filling && consumedCount >= ladder.count {
                Text("한 가격에 다 못 샀어요. 나머지는 더 비싼 위 호가까지 올라가며 샀습니다.")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textPrimary.opacity(0.85))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                    .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 18)
            }

            Spacer()

            if stage == .provoke {
                Button {
                    startFilling()
                } label: {
                    Text("1,000주 시장가로 사기")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(SeedTheme.up, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.bottom, 18)
            } else if consumedCount >= ladder.count {
                Button {
                    stage = .shock
                } label: {
                    Text("체결 결과 보기")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SeedTheme.inverse)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(SeedTheme.textPrimary, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.bottom, 18)
            }
        }
    }

    private func ladderRow(price: Int, qty: Int, highlight: Bool, consumed: Bool) -> some View {
        HStack(spacing: 10) {
            Text(price.formatted())
                .font(.system(size: 15, weight: highlight ? .semibold : .medium))
                .foregroundStyle(consumed ? SeedTheme.textSecondary.opacity(0.5) : SeedTheme.up)
                .strikethrough(consumed, color: SeedTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(consumed ? SeedTheme.band : SeedTheme.downTint)
                        .frame(width: max(geo.size.width * CGFloat(qty) / 320, 8))
                    Text(consumed ? "✓ \(qty)" : "\(qty)")
                        .font(.system(size: 12))
                        .foregroundStyle(consumed ? SeedTheme.textSecondary : SeedTheme.down)
                        .padding(.leading, 6)
                }
            }
            .frame(height: 20)
            if highlight {
                Text("최우선")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(SeedTheme.violetTint, in: Capsule())
            }
        }
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.25), value: consumed)
    }

    private func startFilling() {
        stage = .filling
        Task {
            for i in 1...ladder.count {
                try? await Task.sleep(for: .milliseconds(600))
                consumedCount = i
            }
        }
    }

    // MARK: 3단계 — 충격

    private var shockStage: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("화면에 보이던 가격")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                Text("\(result.displayedPrice.formatted())원")
                    .font(.system(size: 19))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .strikethrough(color: SeedTheme.textSecondary)
                Image(systemName: "arrow.down")
                    .font(.system(size: 15))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .padding(.vertical, 2)
                Text("내 평균 체결가")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                Text("\(Int(result.avgFillPrice).formatted())원")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(SeedTheme.up)
                Text("슬리피지 +\(Int(result.slippage))원 (\(result.slippagePercent.formatted(.number.precision(.fractionLength(2))))%)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SeedTheme.up)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(SeedTheme.upTint, in: Capsule())
                    .padding(.top, 6)
            }
            .padding(.top, 26)

            VStack(spacing: 5) {
                ForEach(Array(result.fills.enumerated()), id: \.offset) { _, fill in
                    HStack {
                        Text("\(fill.qty)주")
                        Spacer()
                        Text("\(fill.price.formatted())원")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)
                }
            }
            .padding(14)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 20)

            coachCard {
                Text("52,300원이라 적혀 있었는데, 왜 ")
                + Text("\(Int(result.avgFillPrice).formatted())원").foregroundStyle(SeedTheme.violetOnDark).bold()
                + Text("에 샀을까요?")
            }
            .padding(.top, 16)

            Spacer()

            Button {
                stage = .insight
            } label: {
                Text("왜 그럴까?")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.bottom, 18)
        }
    }

    // MARK: 4단계 — 깨달음

    private var insightStage: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(SeedTheme.violet).frame(width: 40, height: 40)
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
            }
            .padding(.top, 26)

            Text("이게 슬리피지예요")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
                .padding(.top, 14)

            Text("화면의 가격은 **지금 살 수 있는 가장 싼 '한 주'**일 뿐이에요. 크게 사면 그 위 호가까지 먹으면서 평균가가 밀립니다.")
                .font(.system(size: 15))
                .foregroundStyle(SeedTheme.textPrimary.opacity(0.85))
                .lineSpacing(5)
                .padding(.top, 10)

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(SeedTheme.violet)
                Text("미리 그려진 차트 앱에선 절대 일어나지 않아요. 여긴 진짜 호가창이 살아 움직이니까요.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .lineSpacing(4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 16)

            Spacer()

            Button {
                Analytics.log(.slippageTutorialCompleted,
                              ["avgSlippage": "\(Int(result.slippage))"])
                onSuccess()
            } label: {
                Text("다음")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.bottom, 18)
        }
    }

    // MARK: 공용 코치 카드 (잉크)

    private func coachCard(@ViewBuilder content: () -> Text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11))
                Text("코치")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(SeedTheme.violetOnDark)
            content()
                .font(.system(size: 14))
                .foregroundStyle(SeedTheme.inkText)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(SeedTheme.ink, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// 레슨 2 개념 카드용 미니 호가 사다리.
struct OrderBookIntroVisual: View {
    var body: some View {
        VStack(spacing: 5) {
            introRow("52,400", "이 값에 팔게요", SeedTheme.up)
            introRow("52,350", "이 값에 팔게요", SeedTheme.up)
            HStack {
                Text("52,300")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Spacer()
                Text("← 화면에 보이는 값")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SeedTheme.violetDeep)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 8))
            introRow("52,250", "이 값에 살게요", SeedTheme.down)
            introRow("52,200", "이 값에 살게요", SeedTheme.down)
        }
        .padding(14)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func introRow(_ price: String, _ label: String, _ color: Color) -> some View {
        HStack {
            Text(price)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
            Spacer()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(SeedTheme.textSecondary)
        }
        .padding(.horizontal, 12)
    }
}
