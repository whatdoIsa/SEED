import SwiftUI
import JurinKit


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
        // 구간(세그먼트) 단위 색상: 오르는 구간은 빨강, 내리는 구간은 파랑 —
        // 방향이 꺾이는 즉시 색이 바뀐다. 마지막 구간은 형성 중인 캔들이라
        // 틱마다 방향·색이 실시간으로 반응한다.
        let style = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        var upPath = Path()
        var downPath = Path()

        if m.all.count > 1 {
            for i in 1..<m.all.count {
                let from = CGPoint(x: m.x(i - 1), y: m.y(m.all[i - 1].close))
                let to = CGPoint(x: m.x(i), y: m.y(m.all[i].close))
                if m.all[i].close >= m.all[i - 1].close {
                    upPath.move(to: from)
                    upPath.addLine(to: to)
                } else {
                    downPath.move(to: from)
                    downPath.addLine(to: to)
                }
            }
            context.stroke(downPath, with: .color(SeedTheme.down), style: style)
            context.stroke(upPath, with: .color(SeedTheme.up), style: style)
        }

        // 끝점 도트는 마지막 구간의 방향색
        if let last = m.all.last {
            let lastRising = m.all.count < 2
                || last.close >= m.all[m.all.count - 2].close
            let dot = CGRect(x: m.x(m.all.count - 1) - 4, y: m.y(last.close) - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: dot),
                         with: .color(lastRising ? SeedTheme.up : SeedTheme.down))
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
