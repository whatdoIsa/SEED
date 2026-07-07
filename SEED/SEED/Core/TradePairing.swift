import Foundation
import JurinKit

/// 왕복 매매 1건 — 산 것과 판 것을 짝지은 결과.
/// "얼마나 벌었나"가 아니라 "얼마나 들고 있었나"를 처음으로 측정 가능하게 한다.
struct RoundTrip {
    let symbol: String
    let qty: Int
    let buyPrice: Double
    let sellPrice: Double
    let holdTicks: Int
    let sellTag: TradeReasonTag

    var returnPct: Double {
        guard buyPrice > 0 else { return 0 }
        return (sellPrice - buyPrice) / buyPrice * 100
    }
}

/// 보유 습관 요약 — 복기·부검의 원료.
struct HoldingStats {
    let tripCount: Int
    let avgHoldTicks: Int
    let winRate: Double
    let avgReturnPct: Double
    /// 3캔들 이내 단타의 평균 수익률 (2건 이상일 때만)
    let quickTripAvgPct: Double?
    /// 그보다 길게 든 매매의 평균 수익률 (2건 이상일 때만)
    let patientTripAvgPct: Double?
}

enum TradePairing {

    /// FIFO 페어링: 먼저 산 것부터 먼저 판 것과 짝짓는다 (종목별).
    /// 부분 체결·분할 매도도 수량 단위로 정확히 쪼개어 짝짓는다.
    static func roundTrips(logs: [TradeLog]) -> [RoundTrip] {
        var openLots: [String: [(qty: Int, price: Double, tick: Int)]] = [:]
        var trips: [RoundTrip] = []

        let ordered = logs
            .filter { $0.atTick != nil }
            .sorted { ($0.atTick ?? 0) < ($1.atTick ?? 0) }

        for log in ordered {
            guard let tick = log.atTick else { continue }
            if log.side == .buy {
                openLots[log.symbol, default: []].append((log.qty, log.avgFillPrice, tick))
            } else {
                var remaining = log.qty
                var lots = openLots[log.symbol] ?? []
                while remaining > 0 && !lots.isEmpty {
                    let lot = lots[0]
                    let matched = min(lot.qty, remaining)
                    trips.append(RoundTrip(
                        symbol: log.symbol,
                        qty: matched,
                        buyPrice: lot.price,
                        sellPrice: log.avgFillPrice,
                        holdTicks: max(tick - lot.tick, 0),
                        sellTag: log.reasonTag
                    ))
                    remaining -= matched
                    if lot.qty > matched {
                        lots[0] = (lot.qty - matched, lot.price, lot.tick)
                    } else {
                        lots.removeFirst()
                    }
                }
                openLots[log.symbol] = lots
            }
        }
        return trips
    }

    static func stats(from trips: [RoundTrip],
                      ticksPerCandle: Int = 20) -> HoldingStats? {
        guard !trips.isEmpty else { return nil }
        let wins = trips.filter { $0.returnPct > 0 }.count
        let quickThreshold = ticksPerCandle * 3
        let quick = trips.filter { $0.holdTicks <= quickThreshold }
        let patient = trips.filter { $0.holdTicks > quickThreshold }

        func average(_ items: [RoundTrip]) -> Double {
            items.reduce(0) { $0 + $1.returnPct } / Double(items.count)
        }

        return HoldingStats(
            tripCount: trips.count,
            avgHoldTicks: trips.reduce(0) { $0 + $1.holdTicks } / trips.count,
            winRate: Double(wins) / Double(trips.count) * 100,
            avgReturnPct: average(trips),
            quickTripAvgPct: quick.count >= 2 ? average(quick) : nil,
            patientTripAvgPct: patient.count >= 2 ? average(patient) : nil
        )
    }

    /// 틱 → 사람이 읽는 보유 시간. 20틱 = 1캔들, 20캔들 = 1거래일 기준.
    static func holdText(ticks: Int, ticksPerCandle: Int = 20, candlesPerDay: Int = 20) -> String {
        let ticksPerDay = ticksPerCandle * max(candlesPerDay, 1)
        if candlesPerDay > 0 && ticks >= ticksPerDay {
            let days = ticks / ticksPerDay
            let candles = (ticks % ticksPerDay) / ticksPerCandle
            return candles > 0 ? "\(days)일 \(candles)캔들" : "\(days)일"
        }
        return "\(max(ticks / ticksPerCandle, 1))캔들"
    }
}
