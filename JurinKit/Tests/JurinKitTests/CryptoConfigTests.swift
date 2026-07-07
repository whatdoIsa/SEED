import XCTest
@testable import JurinKit

/// 크립토형 설정 (§16): 24시간·상하한가 없음·거래세 없음이 엔진에서 실제로 성립하는지.
final class CryptoConfigTests: XCTestCase {

    private var cryptoConfig: EngineConfig {
        EngineConfig(
            tickSize: 500,
            fairVolatility: 0.0028,
            commissionRate: 0.0005,
            sellTaxRate: 0,
            candlesPerDay: 0,
            priceBandRate: 0,
            usesKRXTickSize: false
        )
    }

    func testNoTradingDayRollover() {
        let engine = MarketEngine(seed: 11, initialPrice: 480_000, config: cryptoConfig)
        engine.advance(ticks: 2_000)
        XCTAssertEqual(engine.tradingDay, 1, "24시간 시장은 거래일이 넘어가지 않는다")
    }

    func testNoPriceBand() throws {
        let engine = MarketEngine(seed: 11, initialPrice: 480_000, config: cryptoConfig)
        engine.advance(ticks: 20)
        XCTAssertFalse(engine.hasPriceBand)
        // 상하한가가 없으니 기준가의 절반 아래 지정가도 접수된다 (주식이면 밴드 밖)
        let farBelow = engine.lastPrice / 2
        let result = try engine.placeLimitOrder(side: .buy, price: farBelow, qty: 1)
        XCTAssertNotNil(result.restingOrder, "밴드가 없으면 먼 가격도 대기 주문으로 앉는다")
    }

    func testNoSellTax() {
        let config = cryptoConfig
        let notional = 1_000_000
        XCTAssertEqual(config.sellFee(on: notional), config.buyFee(on: notional),
                       "거래세가 없으면 매수·매도 수수료가 같다")
    }

    func testFixedTickSizeWithoutKRXBrackets() {
        let config = cryptoConfig
        XCTAssertEqual(config.tickSize(at: 480_000), 500)
        XCTAssertEqual(config.tickSize(at: 5_000), 500, "KRX 구간을 쓰지 않는다")
    }
}
