import SwiftUI
import JurinKit

/// 전체화면 차트 (토스 '자세한 차트'의 확대 모드).
/// 기존 화면 위로 올라오는 모달 — 차트만 크게, 회전 버튼으로 가로 전환.
/// 세션을 공유하므로 시장은 계속 살아 움직인다.
struct FullScreenChartView: View {
    @Bindable var session: MarketSession
    let store: SeedStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("seed.chartStyle") private var chartStyleRaw = ChartStyle.candle.rawValue
    @AppStorage("seed.chartZoom") private var visibleCandles = 40
    @State private var pinchBaseCount: Int?
    @State private var isLandscape = false

    private var chartStyle: ChartStyle {
        ChartStyle(rawValue: chartStyleRaw) ?? .candle
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            chart
            controls
        }
        .background(SeedTheme.background)
        .onDisappear {
            // 닫을 때는 항상 세로로 복귀
            requestOrientation(.portrait)
        }
    }

    // MARK: 헤더 — 종목·현재가·회전·닫기

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SeedTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(SeedTheme.card, in: Circle())
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(session.activeSpec.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                HStack(spacing: 5) {
                    Text("\(session.engine.lastPrice.formatted())원")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SeedTheme.pnl(Double(session.change)))
                        .contentTransition(.numericText())
                    Text("\(session.change >= 0 ? "+" : "")\(session.changePercent.formatted(.number.precision(.fractionLength(1))))%")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.pnl(Double(session.change)))
                }
            }
            Spacer()
            Button {
                isLandscape.toggle()
                requestOrientation(isLandscape ? .landscapeRight : .portrait)
            } label: {
                Image(systemName: "rectangle.landscape.rotate")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SeedTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(SeedTheme.card, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 차트 — 화면 전부

    private var chart: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 10)
        .gesture(zoomGesture)
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBaseCount ?? visibleCandles
                pinchBaseCount = base
                visibleCandles = min(max(Int(Double(base) / value.magnification), 20), 160)
            }
            .onEnded { _ in pinchBaseCount = nil }
    }

    // MARK: 하단 컨트롤 — 배속·스킵·선/캔들

    private var controls: some View {
        HStack(spacing: 8) {
            ForEach(MarketSession.Speed.allCases) { speed in
                Button {
                    session.speed = speed
                } label: {
                    Text(speed.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(session.speed == speed ? SeedTheme.inverse : SeedTheme.textSecondary)
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .background(
                            session.speed == speed ? SeedTheme.textPrimary : SeedTheme.card,
                            in: Capsule()
                        )
                }
            }
            Button {
                session.skipToNextCandle()
            } label: {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(SeedTheme.card, in: Capsule())
            }
            Spacer()
            if store.progress.unlockLevel >= UnlockLevel.candles {
                Button {
                    chartStyleRaw = (chartStyle == .candle ? ChartStyle.line : .candle).rawValue
                } label: {
                    Image(systemName: chartStyle == .candle ? "chart.bar.fill" : "chart.xyaxis.line")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SeedTheme.textPrimary)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(SeedTheme.card, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 화면 회전

    private func requestOrientation(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}
