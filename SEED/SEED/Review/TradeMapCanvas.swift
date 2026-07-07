import SwiftUI
import JurinKit

/// 매매 지도 (⑧) — 종가 경로 위에 매수(빨강 B)/매도(파랑 S) 마커.
/// 세션 연속성(시드+리플레이) 덕분에 마커의 캔들 좌표가 재시작 후에도 유효하다.
struct TradeMapCanvas: View {
    let candles: [Candle]
    let marks: [(candleIndex: Int, price: Double, side: Side)]
    private let maxVisible = 120

    var body: some View {
        Canvas { context, size in
            guard !candles.isEmpty else { return }

            // 표시 구간: 최근 maxVisible 캔들, 단 첫 마커가 보이도록 확장
            let firstMarkIndex = marks.map(\.candleIndex).min() ?? candles.count
            let windowStart = max(min(candles.count - maxVisible, firstMarkIndex - 4), 0)
            let visible = Array(candles[windowStart...])
            guard !visible.isEmpty else { return }

            let closes = visible.map { Double($0.close) }
            let markPrices = marks
                .filter { $0.candleIndex >= windowStart }
                .map(\.price)
            let high = max(closes.max() ?? 1, markPrices.max() ?? 1)
            let low = min(closes.min() ?? 0, markPrices.min() ?? 0)
            let range = max(high - low, 1)
            let slot = size.width / CGFloat(visible.count)

            func y(_ price: Double) -> CGFloat {
                size.height * (1 - CGFloat((price - low) / range)) * 0.92 + size.height * 0.04
            }
            func x(_ candleIndex: Int) -> CGFloat {
                slot * (CGFloat(candleIndex - windowStart) + 0.5)
            }

            // 가격 경로
            var path = Path()
            for (i, close) in closes.enumerated() {
                let point = CGPoint(x: slot * (CGFloat(i) + 0.5), y: y(close))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(SeedTheme.textSecondary.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

            // 마커 — 꼭지 매수가 시각적으로 자명해지는 순간
            for mark in marks where mark.candleIndex >= windowStart {
                let center = CGPoint(x: min(x(mark.candleIndex), size.width - 10), y: y(mark.price))
                let color = mark.side == .buy ? SeedTheme.up : SeedTheme.down
                let circle = CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)
                context.fill(Path(ellipseIn: circle), with: .color(color))
                context.draw(
                    Text(mark.side == .buy ? "B" : "S")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white),
                    at: center
                )
            }
        }
    }
}
