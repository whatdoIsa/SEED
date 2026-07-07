import XCTest
@testable import JurinKit

final class LimitOrderTests: XCTestCase {

    func testRestingLimitBuyReservesThenSettles() throws {
        let engine = MarketEngine(seed: 42)
        engine.advance(ticks: 20)
        let cashBefore = engine.portfolio.cash

        // 최우선 매수호가에 합류 — 교차하지 않고 호가창에 앉는다
        let price = engine.book.bestBid!
        let result = try engine.placeLimitOrder(side: .buy, price: price, qty: 100)
        let expectedReserve = price * 100 + engine.config.buyFee(on: price * 100)

        XCTAssertNil(result.immediateFill)
        XCTAssertNotNil(result.restingOrder)
        XCTAssertEqual(engine.openOrders.count, 1)
        XCTAssertEqual(engine.portfolio.reservedCash, expectedReserve)
        XCTAssertEqual(engine.portfolio.availableCash, cashBefore - expectedReserve)
        XCTAssertEqual(engine.portfolio.cash, cashBefore, "예약은 지출이 아니다")

        // 시장이 흐르면 노이즈·추세 봇의 시장가 매도가 결국 이 주문을 채운다
        var totalFilled = 0
        for _ in 0..<4_000 {
            engine.step()
            totalFilled += engine.drainUserFillEvents().reduce(0) { $0 + $1.qty }
            if engine.openOrders.isEmpty { break }
        }

        XCTAssertTrue(engine.openOrders.isEmpty, "대기 주문이 결국 체결되어야 한다")
        XCTAssertEqual(totalFilled, 100)
        XCTAssertEqual(engine.portfolio.qty, 100)
        XCTAssertEqual(engine.portfolio.reservedCash, 0, "체결 후 예약금은 전부 정산")
        XCTAssertEqual(engine.portfolio.avgCost, Double(price), accuracy: 0.001,
                       "지정가 대기 체결은 정확히 지정한 값에 산다 — 슬리피지 0")
        XCTAssertEqual(engine.portfolio.cash,
                       cashBefore - price * 100 - engine.portfolio.feesPaid)
    }

    func testImmediateCrossingLimitBuy() throws {
        let engine = MarketEngine(seed: 7)
        engine.advance(ticks: 20)
        let ask = engine.book.bestAsk!
        let limit = ask + engine.config.tickSize * 2

        let result = try engine.placeLimitOrder(side: .buy, price: limit, qty: 60)

        let immediate = try XCTUnwrap(result.immediateFill)
        XCTAssertGreaterThan(immediate.filledQty, 0)
        // 교차 체결은 지정가를 넘지 않는다
        XCTAssertTrue(immediate.fills.allSatisfy { $0.price <= limit })
        // 즉시분 + 대기분 = 주문 수량
        let resting = result.restingOrder?.restingQty ?? 0
        XCTAssertEqual(immediate.filledQty + resting, 60)
    }

    func testCancelReleasesReservation() throws {
        let engine = MarketEngine(seed: 5)
        engine.advance(ticks: 20)
        _ = try engine.placeMarketOrder(side: .buy, qty: 50)

        // 보유 주식을 시장 위쪽에 지정가 매도로 걸어둔다
        let sellPrice = engine.book.bestAsk! + engine.config.tickSize * 4
        let result = try engine.placeLimitOrder(side: .sell, price: sellPrice, qty: 50)
        let order = try XCTUnwrap(result.restingOrder)

        XCTAssertEqual(engine.portfolio.reservedShares, 50)
        XCTAssertEqual(engine.portfolio.availableShares, 0)

        engine.cancelOrder(id: order.id)

        XCTAssertEqual(engine.portfolio.reservedShares, 0)
        XCTAssertEqual(engine.portfolio.availableShares, 50)
        XCTAssertTrue(engine.openOrders.isEmpty)
        XCTAssertEqual(engine.book.remainingQty(orderId: order.id, side: .sell, price: sellPrice), 0)
    }

    func testReservationPreventsDoubleSpend() throws {
        let engine = MarketEngine(seed: 5, config: EngineConfig(initialCash: 600_000))
        engine.advance(ticks: 20)
        let bid = engine.book.bestBid!

        // 가용 현금 대부분을 대기 매수에 예약
        _ = try engine.placeLimitOrder(side: .buy, price: bid, qty: 10)

        // 남은 가용 현금으로 살 수 없는 시장가 매수는 거부되어야 한다
        XCTAssertThrowsError(try engine.placeMarketOrder(side: .buy, qty: 10)) { error in
            guard case OrderError.insufficientCash = error else {
                return XCTFail("예약이 이중 지출을 막아야 한다: \(error)")
            }
        }
    }

    func testReservedSharesCannotBeSoldTwice() throws {
        let engine = MarketEngine(seed: 5)
        engine.advance(ticks: 20)
        _ = try engine.placeMarketOrder(side: .buy, qty: 50)
        let sellPrice = engine.book.bestAsk! + engine.config.tickSize * 4
        _ = try engine.placeLimitOrder(side: .sell, price: sellPrice, qty: 50)

        XCTAssertThrowsError(try engine.placeLimitOrder(side: .sell, price: sellPrice, qty: 1)) { error in
            guard case OrderError.insufficientHoldings = error else {
                return XCTFail("예약 주식은 다시 팔 수 없어야 한다: \(error)")
            }
        }
    }

    func testRestoreFillRebuildsPortfolioOnly() {
        let engine = MarketEngine(seed: 9)
        engine.advance(ticks: 10)
        let candlesBefore = engine.candles

        engine.restoreFill(side: .buy, price: 52_000, qty: 30)

        XCTAssertEqual(engine.portfolio.qty, 30)
        XCTAssertEqual(engine.portfolio.avgCost, 52_000, accuracy: 0.001)
        XCTAssertEqual(engine.candles, candlesBefore, "복원은 시장을 건드리지 않는다")
    }
}
