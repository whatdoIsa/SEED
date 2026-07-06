import Foundation

// MARK: - 기본 타입

public enum Side: String, Codable, Sendable {
    case buy, sell

    public var opposite: Side { self == .buy ? .sell : .buy }
}

/// 호가창에 놓이는 지정가 주문. 가격은 원 단위 정수.
public struct Order: Identifiable {
    public let id: UInt64
    public let agentId: String
    public let side: Side
    public let price: Int
    public var qty: Int
    public let tick: Int

    public init(id: UInt64, agentId: String, side: Side, price: Int, qty: Int, tick: Int) {
        self.id = id
        self.agentId = agentId
        self.side = side
        self.price = price
        self.qty = qty
        self.tick = tick
    }
}

/// 체결 1건. 테이프와 분봉 집계의 원료.
public struct Trade {
    public let price: Int
    public let qty: Int
    public let tick: Int
    public let aggressor: Side

    public init(price: Int, qty: Int, tick: Int, aggressor: Side) {
        self.price = price
        self.qty = qty
        self.tick = tick
        self.aggressor = aggressor
    }
}

public struct Candle: Equatable {
    public var open: Int
    public var high: Int
    public var low: Int
    public var close: Int
    public var volume: Int
    public let index: Int

    public init(open: Int, index: Int) {
        self.open = open
        self.high = open
        self.low = open
        self.close = open
        self.volume = 0
        self.index = index
    }

    public mutating func apply(_ trade: Trade) {
        high = max(high, trade.price)
        low = min(low, trade.price)
        close = trade.price
        volume += trade.qty
    }

    public var isBullish: Bool { close >= open }
}

// MARK: - 체결 결과 (슬리피지 튜토리얼의 원료)

public struct Fill: Equatable {
    public let price: Int
    public let qty: Int

    public init(price: Int, qty: Int) {
        self.price = price
        self.qty = qty
    }
}

/// 시장가 주문의 다단계 체결 내역. 표시가 대비 슬리피지를 계산한다.
public struct FillResult {
    public let side: Side
    public let requestedQty: Int
    public let fills: [Fill]
    /// 주문 제출 시점의 최우선 호가 (사용자 화면에 보이던 값)
    public let displayedPrice: Int

    public var filledQty: Int { fills.reduce(0) { $0 + $1.qty } }
    public var notional: Int { fills.reduce(0) { $0 + $1.price * $1.qty } }

    public var avgFillPrice: Double {
        guard filledQty > 0 else { return 0 }
        return Double(notional) / Double(filledQty)
    }

    /// 불리한 방향이 양수. 매수: 평균가 - 표시가 / 매도: 표시가 - 평균가.
    public var slippage: Double {
        guard filledQty > 0 else { return 0 }
        switch side {
        case .buy: return avgFillPrice - Double(displayedPrice)
        case .sell: return Double(displayedPrice) - avgFillPrice
        }
    }

    public var slippagePercent: Double {
        guard displayedPrice > 0 else { return 0 }
        return slippage / Double(displayedPrice) * 100
    }
}

// MARK: - 시드 고정 난수 (시나리오 재현성)

/// SplitMix64. 같은 시드면 항상 같은 시장이 나온다 — 시나리오·봇 비교·테스트의 전제.
public struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    public mutating func double(in range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    public mutating func chance(_ p: Double) -> Bool {
        double(in: 0...1) < p
    }
}

// MARK: - 호가창

/// 가격-시간 우선 매칭 호가창.
public final class OrderBook {
    public private(set) var bids: [Int: [Order]] = [:]
    public private(set) var asks: [Int: [Order]] = [:]
    private var nextOrderId: UInt64 = 1

    public init() {}

    public var bestBid: Int? { bids.keys.max() }
    public var bestAsk: Int? { asks.keys.min() }

    public func quotedQty(side: Side, price: Int) -> Int {
        let levels = side == .buy ? bids : asks
        return levels[price]?.reduce(0) { $0 + $1.qty } ?? 0
    }

    /// 상위 N개 호가 스냅샷 (UI용). 매도는 낮은 가격부터, 매수는 높은 가격부터.
    public func depth(side: Side, levels: Int) -> [(price: Int, qty: Int)] {
        let book = side == .buy ? bids : asks
        let prices = side == .buy
            ? book.keys.sorted(by: >).prefix(levels)
            : book.keys.sorted().prefix(levels)
        return prices.map { price in
            (price, book[price]!.reduce(0) { $0 + $1.qty })
        }
    }

    public func totalQty(side: Side) -> Int {
        let book = side == .buy ? bids : asks
        return book.values.flatMap { $0 }.reduce(0) { $0 + $1.qty }
    }

    public func cancelAll(agentId: String) {
        for (price, queue) in bids {
            let remaining = queue.filter { $0.agentId != agentId }
            if remaining.isEmpty { bids[price] = nil } else { bids[price] = remaining }
        }
        for (price, queue) in asks {
            let remaining = queue.filter { $0.agentId != agentId }
            if remaining.isEmpty { asks[price] = nil } else { asks[price] = remaining }
        }
    }

    /// 지정가 주문: 반대편과 교차하면 먼저 체결하고, 남으면 호가창에 앉는다.
    @discardableResult
    public func submitLimit(agentId: String, side: Side, price: Int, qty: Int, tick: Int) -> [Trade] {
        var remaining = qty
        var trades: [Trade] = []

        while remaining > 0 {
            guard let touch = (side == .buy ? bestAsk : bestBid) else { break }
            let crossed = side == .buy ? touch <= price : touch >= price
            guard crossed else { break }
            let fills = consume(side: side.opposite, price: touch, upTo: remaining)
            for fill in fills {
                trades.append(Trade(price: fill.price, qty: fill.qty, tick: tick, aggressor: side))
                remaining -= fill.qty
            }
            if fills.isEmpty { break }
        }

        if remaining > 0 {
            let order = Order(id: nextOrderId, agentId: agentId, side: side, price: price, qty: remaining, tick: tick)
            nextOrderId += 1
            if side == .buy {
                bids[price, default: []].append(order)
            } else {
                asks[price, default: []].append(order)
            }
        }
        return trades
    }

    /// 시장가 미리보기: 호가창을 바꾸지 않고 체결 내역만 계산 (잔고 검증용).
    public func previewMarket(side: Side, qty: Int) -> [Fill] {
        var remaining = qty
        var fills: [Fill] = []
        let book = side == .buy ? asks : bids
        let prices = side == .buy ? book.keys.sorted() : book.keys.sorted(by: >)
        outer: for price in prices {
            for order in book[price]! {
                let take = min(order.qty, remaining)
                fills.append(Fill(price: price, qty: take))
                remaining -= take
                if remaining == 0 { break outer }
            }
        }
        return mergeFills(fills)
    }

    /// 시장가 실행: 반대편 호가를 가격 순으로 먹는다. 슬리피지가 여기서 발생한다.
    public func executeMarket(agentId: String, side: Side, qty: Int, tick: Int) -> ([Fill], [Trade]) {
        var remaining = qty
        var fills: [Fill] = []
        var trades: [Trade] = []

        while remaining > 0 {
            guard let touch = (side == .buy ? bestAsk : bestBid) else { break }
            let consumed = consume(side: side.opposite, price: touch, upTo: remaining)
            if consumed.isEmpty { break }
            for fill in consumed {
                fills.append(fill)
                trades.append(Trade(price: fill.price, qty: fill.qty, tick: tick, aggressor: side))
                remaining -= fill.qty
            }
        }
        return (mergeFills(fills), trades)
    }

    /// 한 가격 레벨에서 FIFO로 소진.
    private func consume(side: Side, price: Int, upTo qty: Int) -> [Fill] {
        var remaining = qty
        var fills: [Fill] = []
        let isBidSide = side == .buy

        var queue = (isBidSide ? bids[price] : asks[price]) ?? []
        var index = 0
        while remaining > 0 && index < queue.count {
            let take = min(queue[index].qty, remaining)
            fills.append(Fill(price: price, qty: take))
            queue[index].qty -= take
            remaining -= take
            if queue[index].qty == 0 { index += 1 }
        }
        let cleaned = queue.filter { $0.qty > 0 }
        if isBidSide {
            bids[price] = cleaned.isEmpty ? nil : cleaned
        } else {
            asks[price] = cleaned.isEmpty ? nil : cleaned
        }
        return fills
    }

    /// 같은 가격의 연속 체결을 합쳐 UI가 읽기 쉽게.
    private func mergeFills(_ fills: [Fill]) -> [Fill] {
        var merged: [Fill] = []
        for fill in fills {
            if let last = merged.last, last.price == fill.price {
                merged[merged.count - 1] = Fill(price: last.price, qty: last.qty + fill.qty)
            } else {
                merged.append(fill)
            }
        }
        return merged
    }
}
