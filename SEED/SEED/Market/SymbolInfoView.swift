import SwiftUI
import JurinKit

/// 종목정보 탭 (C) — 시세·종목 성격·오늘 지표·뉴스 히스토리.
/// "이 종목에 무슨 일이 있었나"를 돌아보는 화면. 토스의 종목정보 문법을 따른다.
struct SymbolInfoView: View {
    @Bindable var session: MarketSession

    private var engine: MarketEngine { session.engine }
    private var spec: SymbolSpec { session.activeSpec }

    /// 오늘(현 거래일)의 캔들. 크립토(거래일 없음)는 최근 30캔들.
    private var todayCandles: [Candle] {
        let candlesPerDay = engine.config.candlesPerDay
        if candlesPerDay > 0 {
            let dayStart = (engine.tradingDay - 1) * candlesPerDay
            return engine.candles.filter { $0.index >= dayStart } + [engine.currentCandle]
        }
        return Array(engine.candles.suffix(30)) + [engine.currentCandle]
    }

    var body: some View {
        let _ = engine.tick // 관찰 트리거
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                priceSection
                characterSection
                todaySection
                newsSection
            }
            .padding(16)
        }
        .background(SeedTheme.background)
    }

    // MARK: 시세

    private var priceSection: some View {
        let today = todayCandles
        let todayHigh = today.map(\.high).max() ?? engine.lastPrice
        let todayLow = today.map(\.low).min() ?? engine.lastPrice
        let allHigh = (engine.candles.map(\.high).max() ?? engine.lastPrice)
        let allLow = (engine.candles.map(\.low).min() ?? engine.lastPrice)
        let periodLabel = engine.config.candlesPerDay > 0 ? "오늘" : "최근"

        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("시세")
            VStack(spacing: 8) {
                rangeBar(label: "\(periodLabel) 최저 · 최고",
                         low: todayLow, high: todayHigh, current: engine.lastPrice)
                rangeBar(label: "전체 기간 최저 · 최고",
                         low: allLow, high: allHigh, current: engine.lastPrice)
            }
            VStack(spacing: 7) {
                infoRow("시가 (\(periodLabel))", "\(today.first?.open.formatted() ?? "—")원")
                infoRow("현재가", "\(engine.lastPrice.formatted())원")
                if engine.hasPriceBand {
                    infoRow("상한가", "\(engine.upperLimitPrice.formatted())원",
                            valueColor: SeedTheme.up)
                    infoRow("하한가", "\(engine.lowerLimitPrice.formatted())원",
                            valueColor: SeedTheme.down)
                } else {
                    infoRow("가격 제한", "없음 (24시간 시장)")
                }
            }
            .padding(13)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 13))
        }
    }

    /// 토스식 범위 바 — 현재가가 구간의 어디쯤인지.
    private func rangeBar(label: String, low: Int, high: Int, current: Int) -> some View {
        let fraction = high > low
            ? CGFloat(current - low) / CGFloat(high - low) : 0.5
        return VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SeedTheme.band).frame(height: 5)
                        .frame(maxHeight: .infinity)
                    Circle()
                        .fill(SeedTheme.textPrimary)
                        .frame(width: 11, height: 11)
                        .position(x: max(min(geo.size.width * fraction, geo.size.width - 6), 6),
                                  y: geo.size.height / 2)
                }
            }
            .frame(height: 12)
            HStack {
                Text(low.formatted()).foregroundStyle(SeedTheme.down)
                Spacer()
                Text(label).foregroundStyle(SeedTheme.textSecondary)
                Spacer()
                Text(high.formatted()).foregroundStyle(SeedTheme.up)
            }
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.vertical, 3)
    }

    // MARK: 종목 성격 (β · 변동성)

    private var characterSection: some View {
        let beta = spec.config.marketBeta
        let volatility = spec.config.fairVolatility
        let volLabel = volatility >= 0.0015 ? "높음" : (volatility >= 0.0008 ? "보통" : "낮음")

        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("종목 성격")
            VStack(alignment: .leading, spacing: 9) {
                Text(spec.oneLiner)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                infoRow("시장 민감도 β",
                        beta.formatted(.number.precision(.fractionLength(2))),
                        valueColor: SeedTheme.violetDeep)
                infoRow("변동성", volLabel,
                        valueColor: volLabel == "높음" ? SeedTheme.up : SeedTheme.textPrimary)
                Text(betaSentence(beta))
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .lineSpacing(4)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 13))
        }
    }

    private func betaSentence(_ beta: Double) -> String {
        if beta < 0 {
            return "시장이 빠지는 날 오히려 오르는 경향이 있어요 — 분산의 재료가 되는 이유예요."
        }
        if beta >= 1.2 {
            return "시장이 1 움직일 때 약 \(beta.formatted(.number.precision(.fractionLength(1))))배로 움직여요. 오를 땐 화끈하고, 빠질 땐 더 아파요."
        }
        if beta <= 0.6 {
            return "시장이 흔들려도 절반 이하로만 흔들리는 방어적 성격이에요."
        }
        return "시장과 비슷한 리듬으로 움직이는 종목이에요."
    }

    // MARK: 오늘 지표

    private var todaySection: some View {
        let today = todayCandles
        let volumeSum = today.reduce(0) { $0 + $1.volume }
        let buyVolume = engine.tape.filter { $0.aggressor == .buy }.reduce(0) { $0 + $1.qty }
        let sellVolume = max(engine.tape.filter { $0.aggressor == .sell }.reduce(0) { $0 + $1.qty }, 1)
        let strength = Double(buyVolume) / Double(sellVolume) * 100

        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("오늘 지표")
            VStack(spacing: 7) {
                infoRow("거래량", "\(volumeSum.formatted())주")
                infoRow("체결강도",
                        "\(strength.formatted(.number.precision(.fractionLength(1))))%",
                        valueColor: strength >= 100 ? SeedTheme.up : SeedTheme.down)
                infoRow("거래일", engine.config.candlesPerDay > 0 ? "D+\(engine.tradingDay)" : "24시간 연속")
            }
            .padding(13)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 13))
        }
    }

    // MARK: 뉴스 히스토리

    private var newsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("뉴스")
            if engine.newsFeed.isEmpty {
                Text("아직 이 종목에 뉴스가 없어요. 조용한 것도 정보예요.")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                    .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 13))
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(engine.newsFeed.reversed().enumerated()), id: \.offset) { _, event in
                        newsRow(event)
                    }
                }
            }
        }
    }

    private func newsRow(_ event: NewsEvent) -> some View {
        let color = event.isPositive ? SeedTheme.up : SeedTheme.down
        let ticksPerDay = engine.config.ticksPerCandle * max(engine.config.candlesPerDay, 1)
        let dayLabel = engine.config.candlesPerDay > 0
            ? "D+\(event.tick / ticksPerDay + 1)"
            : "#\(event.tick / engine.config.ticksPerCandle)캔들"

        return HStack(spacing: 10) {
            Image(systemName: event.isMarketWide ? "globe.asia.australia.fill" : "newspaper.fill")
                .font(.system(size: 13))
                .foregroundStyle(event.isMarketWide ? SeedTheme.violetDeep : color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(NewsHeadlines.text(for: event))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("\(event.isMarketWide ? "시장 전체 · " : "")\(dayLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            Spacer()
            Text("\(event.isPositive ? "+" : "-")\(abs(event.magnitudePct).formatted(.number.precision(.fractionLength(1))))%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 11))
    }

    // MARK: 공통

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(SeedTheme.textPrimary)
    }

    private func infoRow(_ label: String, _ value: String,
                         valueColor: Color = SeedTheme.textPrimary) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(SeedTheme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(valueColor)
        }
    }
}
