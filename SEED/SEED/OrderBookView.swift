import SwiftUI
import JurinKit

/// 호가창 (부록 A-1) — 좌: 체결강도·테이프 / 우: 가격 사다리 + 잔량 막대.
/// 매도호가는 위(빨강 가격), 매수호가는 아래(파랑 가격) — 한국 증권앱 관례.
struct OrderBookView: View {
    let engine: MarketEngine
    private let levels = 4

    var body: some View {
        // engine.tick을 읽어 매 틱 뷰가 갱신되게 한다 (book은 참조라 관찰되지 않음)
        let _ = engine.tick
        let asks = engine.book.depth(side: .sell, levels: levels)
        let bids = engine.book.depth(side: .buy, levels: levels)
        let maxQty = max((asks + bids).map(\.qty).max() ?? 1, 1)

        HStack(alignment: .top, spacing: 12) {
            tapeColumn
                .frame(width: 118)
            VStack(spacing: 3) {
                ForEach(asks.reversed(), id: \.price) { level in
                    ladderRow(price: level.price, qty: level.qty, maxQty: maxQty, side: .sell)
                }
                currentPriceRow
                ForEach(bids, id: \.price) { level in
                    ladderRow(price: level.price, qty: level.qty, maxQty: maxQty, side: .buy)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: 사다리

    private func ladderRow(price: Int, qty: Int, maxQty: Int, side: Side) -> some View {
        let priceColor = side == .sell ? SeedTheme.up : SeedTheme.down
        let barTint = side == .sell ? SeedTheme.downTint : SeedTheme.upTint
        let qtyColor = side == .sell ? SeedTheme.down : SeedTheme.up
        return HStack(spacing: 8) {
            Text(price.formatted())
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(priceColor)
                .frame(width: 62, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barTint)
                        .frame(width: max(geo.size.width * CGFloat(qty) / CGFloat(maxQty), 2))
                    Text(qty.formatted())
                        .font(.system(size: 11))
                        .foregroundStyle(qtyColor)
                        .padding(.leading, 4)
                }
            }
            .frame(height: 16)
        }
        .padding(.vertical, 2)
    }

    private var currentPriceRow: some View {
        HStack {
            Text(engine.lastPrice.formatted())
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
            Spacer()
            Text("현재가")
                .font(.system(size: 11))
                .foregroundStyle(SeedTheme.textSecondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SeedTheme.textPrimary.opacity(0.35), lineWidth: 1))
        .padding(.vertical, 2)
    }

    // MARK: 체결 테이프 + 체결강도

    private var tapeColumn: some View {
        let recent = engine.tape.suffix(14).reversed()
        let buyVolume = engine.tape.filter { $0.aggressor == .buy }.reduce(0) { $0 + $1.qty }
        let sellVolume = max(engine.tape.filter { $0.aggressor == .sell }.reduce(0) { $0 + $1.qty }, 1)
        let strength = Double(buyVolume) / Double(sellVolume) * 100

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("체결강도")
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.textSecondary)
                Text("\(strength.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(strength >= 100 ? SeedTheme.up : SeedTheme.down)
            }
            .padding(.bottom, 3)
            ForEach(Array(recent.enumerated()), id: \.offset) { _, trade in
                HStack {
                    Text(trade.price.formatted())
                        .font(.system(size: 11))
                        .foregroundStyle(SeedTheme.textPrimary)
                    Spacer()
                    Text(trade.qty.formatted())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(trade.aggressor == .buy ? SeedTheme.up : SeedTheme.down)
                }
            }
        }
    }
}

/// 호가창 미해금 상태 (Lv2 미만).
struct OrderBookLockedView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 26))
                .foregroundStyle(SeedTheme.textSecondary.opacity(0.5))
            Text("호가창은 레슨 2에서 열려요")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SeedTheme.textSecondary)
            Text("가격 뒤에 줄 서 있는 진짜 시장을 보게 됩니다")
                .font(.system(size: 12))
                .foregroundStyle(SeedTheme.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
