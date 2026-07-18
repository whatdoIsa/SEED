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

    public init(side: Side, requestedQty: Int, fills: [Fill], displayedPrice: Int) {
        self.side = side
        self.requestedQty = requestedQty
        self.fills = fills
        self.displayedPrice = displayedPrice
    }

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

    // 구간 매핑·셔플은 stdlib(Double.random/Int.random/shuffled)에 맡기지 않고
    // 여기 고정 구현한다 — stdlib 알고리즘은 OS에 내장되어 iOS 업데이트로 바뀔 수 있고,
    // 바뀌는 순간 같은 시드의 리플레이(저장된 전 세션)가 통째로 다른 시장이 된다.

    /// [0, 1) 균등 — 상위 53비트를 가수로 사용하는 표준 기법.
    public mutating func double01() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    public mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * double01()
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        // 모듈로 방식 — span < 2^32에서 편향은 2^-32 미만으로 무시 가능. 결정론이 우선.
        let span = UInt64(bitPattern: Int64(range.upperBound &- range.lowerBound)) &+ 1
        guard span != 0 else { return Int(bitPattern: UInt(next())) } // 전체 Int 범위 (실사용 없음)
        return range.lowerBound &+ Int(next() % span)
    }

    public mutating func chance(_ p: Double) -> Bool {
        double01() < p
    }

    /// 자체 Fisher–Yates — stdlib shuffled(using:)의 알고리즘 변경으로부터 격리.
    public mutating func shuffled<T>(_ array: [T]) -> [T] {
        var result = array
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, through: 1, by: -1) {
            let j = int(in: 0...i)
            if i != j { result.swapAt(i, j) }
        }
        return result
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

    /// 특정 참여자의 주문만 남기고 전부 걷는다 — 거래일 경계의 봇 호가 리셋용.
    public func cancelAllExcept(agentId: String) {
        for (price, queue) in bids {
            let remaining = queue.filter { $0.agentId == agentId }
            if remaining.isEmpty { bids[price] = nil } else { bids[price] = remaining }
        }
        for (price, queue) in asks {
            let remaining = queue.filter { $0.agentId == agentId }
            if remaining.isEmpty { asks[price] = nil } else { asks[price] = remaining }
        }
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
        submitLimitTracked(agentId: agentId, side: side, price: price, qty: qty, tick: tick).trades
    }

    /// 지정가 주문 + 잔여분의 주문 ID 반환 — 사용자 미체결 추적용.
    /// excluding: 자기체결 방지(STP) — 이 참여자의 대기 주문은 건너뛰고 체결한다.
    public func submitLimitTracked(agentId: String, side: Side, price: Int, qty: Int, tick: Int,
                                   excluding excludedAgent: String? = nil)
    -> (trades: [Trade], restingOrderId: UInt64?, restingQty: Int) {
        var remaining = qty
        var trades: [Trade] = []

        while remaining > 0 {
            guard let touch = nextTouch(for: side, excluding: excludedAgent) else { break }
            let crossed = side == .buy ? touch <= price : touch >= price
            guard crossed else { break }
            let fills = consume(side: side.opposite, price: touch, upTo: remaining,
                                excluding: excludedAgent)
            for fill in fills {
                trades.append(Trade(price: fill.price, qty: fill.qty, tick: tick, aggressor: side))
                remaining -= fill.qty
            }
            if fills.isEmpty { break }
        }

        var restingId: UInt64?
        if remaining > 0 {
            let order = Order(id: nextOrderId, agentId: agentId, side: side, price: price, qty: remaining, tick: tick)
            restingId = nextOrderId
            nextOrderId += 1
            if side == .buy {
                bids[price, default: []].append(order)
            } else {
                asks[price, default: []].append(order)
            }
        }
        return (trades, restingId, remaining)
    }

    /// 특정 주문의 현재 잔량 (체결·취소로 사라졌으면 0).
    public func remainingQty(orderId: UInt64, side: Side, price: Int) -> Int {
        let queue = (side == .buy ? bids[price] : asks[price]) ?? []
        return queue.first { $0.id == orderId }?.qty ?? 0
    }

    /// 주문 잔량 부분 감소 (동시호가 배분용). 실제 감소량을 반환한다.
    @discardableResult
    public func reduce(orderId: UInt64, side: Side, price: Int, by qty: Int) -> Int {
        var queue = (side == .buy ? bids[price] : asks[price]) ?? []
        guard let index = queue.firstIndex(where: { $0.id == orderId }) else { return 0 }
        let taken = min(queue[index].qty, qty)
        queue[index].qty -= taken
        let cleaned = queue.filter { $0.qty > 0 }
        if side == .buy {
            bids[price] = cleaned.isEmpty ? nil : cleaned
        } else {
            asks[price] = cleaned.isEmpty ? nil : cleaned
        }
        return taken
    }

    /// 주문 취소. 남은 잔량을 반환한다.
    @discardableResult
    public func cancel(orderId: UInt64, side: Side, price: Int) -> Int {
        var queue = (side == .buy ? bids[price] : asks[price]) ?? []
        guard let index = queue.firstIndex(where: { $0.id == orderId }) else { return 0 }
        let remaining = queue[index].qty
        queue.remove(at: index)
        if side == .buy {
            bids[price] = queue.isEmpty ? nil : queue
        } else {
            asks[price] = queue.isEmpty ? nil : queue
        }
        return remaining
    }

    /// 시장가 미리보기: 호가창을 바꾸지 않고 체결 내역만 계산 (잔고 검증용).
    /// excluding: 자기체결 방지 — 실행(executeMarket)과 같은 기준으로 계산해야 검증이 정확하다.
    public func previewMarket(side: Side, qty: Int, excluding excludedAgent: String? = nil) -> [Fill] {
        var remaining = qty
        var fills: [Fill] = []
        let book = side == .buy ? asks : bids
        let prices = side == .buy ? book.keys.sorted() : book.keys.sorted(by: >)
        outer: for price in prices {
            for order in book[price]! {
                if let excludedAgent, order.agentId == excludedAgent { continue }
                let take = min(order.qty, remaining)
                fills.append(Fill(price: price, qty: take))
                remaining -= take
                if remaining == 0 { break outer }
            }
        }
        return mergeFills(fills)
    }

    /// 시장가 실행: 반대편 호가를 가격 순으로 먹는다. 슬리피지가 여기서 발생한다.
    /// excluding: 자기체결 방지(STP) — 자기 대기 주문은 건너뛰고 다음 호가로 넘어간다.
    public func executeMarket(agentId: String, side: Side, qty: Int, tick: Int,
                              excluding excludedAgent: String? = nil) -> ([Fill], [Trade]) {
        var remaining = qty
        var fills: [Fill] = []
        var trades: [Trade] = []

        while remaining > 0 {
            guard let touch = nextTouch(for: side, excluding: excludedAgent) else { break }
            let consumed = consume(side: side.opposite, price: touch, upTo: remaining,
                                   excluding: excludedAgent)
            if consumed.isEmpty { break }
            for fill in consumed {
                fills.append(fill)
                trades.append(Trade(price: fill.price, qty: fill.qty, tick: tick, aggressor: side))
                remaining -= fill.qty
            }
        }
        return (mergeFills(fills), trades)
    }

    /// 주문자(side) 기준 다음 체결 가능 반대 호가 — 제외 대상만 있는 레벨은 지나친다.
    /// 정렬 소비라 결정론이 유지된다.
    private func nextTouch(for side: Side, excluding excludedAgent: String?) -> Int? {
        let book = side == .buy ? asks : bids
        let prices = side == .buy ? book.keys.sorted() : book.keys.sorted(by: >)
        guard let excludedAgent else { return prices.first }
        return prices.first { price in
            book[price]!.contains { $0.agentId != excludedAgent }
        }
    }

    /// 한 가격 레벨에서 FIFO로 소진. excluding의 주문은 자리(우선순위)를 지킨 채 건너뛴다.
    private func consume(side: Side, price: Int, upTo qty: Int,
                         excluding excludedAgent: String? = nil) -> [Fill] {
        var remaining = qty
        var fills: [Fill] = []
        let isBidSide = side == .buy

        var queue = (isBidSide ? bids[price] : asks[price]) ?? []
        var index = 0
        while remaining > 0 && index < queue.count {
            if let excludedAgent, queue[index].agentId == excludedAgent {
                index += 1
                continue
            }
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
