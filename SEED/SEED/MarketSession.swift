import Foundation
import Observation
import JurinKit

/// 엔진과 UI 사이의 드라이버. 엔진에는 Timer가 없으므로(설계 결정)
/// 배속에 맞춰 step을 호출하는 책임이 여기 있다 — 스펙 1(배속)의 UI 측 절반.
@Observable
@MainActor
final class MarketSession {

    enum Speed: Int, CaseIterable, Identifiable {
        case x1 = 1, x5 = 5, x30 = 30
        var id: Int { rawValue }
        var label: String { "\(rawValue)x" }
    }

    private(set) var engine: MarketEngine
    private(set) var engineSeed: UInt64
    var speed: Speed = .x1
    private(set) var isRunning = false
    /// 세션 시작 기준가 — 등락 표시의 기준.
    private(set) var startPrice: Int

    private weak var store: SeedStore?
    private var loop: Task<Void, Never>?
    /// 1x에서 1틱 ≈ 1초. 배속은 간격을 줄인다.
    private let baseTickInterval: Duration = .seconds(1)
    /// 백그라운드 경과를 따라잡는 상한 — 최대 30분치.
    private let catchUpCap = 1_800

    init(store: SeedStore?) {
        let seed: UInt64
        let engine: MarketEngine
        var isFreshMarket = false

        if let state = store?.marketState() {
            // 연속성: 같은 시드로 엔진을 만들고, 과거 주문을 원래 틱에 재실행하면
            // 결정론에 의해 완전히 같은 시장·포트폴리오가 복원된다.
            seed = state.seed
            engine = MarketEngine(seed: seed)
            for log in store?.replayableLogs() ?? [] {
                guard let atTick = log.atTick, atTick <= state.tick else { continue }
                engine.advance(ticks: max(atTick - engine.tick, 0))
                if log.isLimitFill == true {
                    // 지정가 체결은 정산 틱이 기록되지 않으므로 포트폴리오만 복원
                    engine.restoreFill(side: log.side, price: Int(log.avgFillPrice), qty: log.qty)
                } else {
                    _ = try? engine.placeMarketOrder(side: log.side, qty: log.qty)
                }
            }
            engine.advance(ticks: max(state.tick - engine.tick, 0))
        } else {
            // 첫 실행 (또는 리플레이 좌표가 없는 구버전 데이터 → 포트폴리오 스냅샷 폴백)
            seed = .random(in: 0...UInt64.max)
            engine = MarketEngine(seed: seed, portfolio: store?.restorePortfolio())
            engine.advance(ticks: engine.config.ticksPerCandle * 30)
            isFreshMarket = true
        }

        self.store = store
        self.engineSeed = seed
        self.engine = engine
        self.startPrice = engine.candles.last?.close ?? engine.lastPrice
        if isFreshMarket {
            store?.persistMarketState(seed: seed, tick: engine.tick)
        }
    }

    // MARK: 연속성

    func persistState() {
        store?.persistMarketState(seed: engineSeed, tick: engine.tick)
    }

    /// 씬 전환 처리: 백그라운드 진입 시 상태 저장, 복귀 시 경과분 따라잡기 (P1 catch-up).
    func handleScenePhase(active: Bool) {
        if active {
            catchUpAfterBackground()
            start()
        } else {
            stop()
            persistState()
            store?.persistPortfolio(engine.portfolio)
        }
    }

    private func catchUpAfterBackground() {
        guard let lastActive = store?.lastActiveAt else { return }
        let elapsed = Int(Date.now.timeIntervalSince(lastActive))
        guard elapsed > 2 else { return }
        engine.advance(ticks: min(elapsed, catchUpCap))
        processUserFills()
        persistState()
    }

    // MARK: 등락 (기준가 대비)

    var change: Int { engine.lastPrice - startPrice }
    var changePercent: Double {
        guard startPrice > 0 else { return 0 }
        return Double(change) / Double(startPrice) * 100
    }

    // MARK: 루프 제어

    func start() {
        guard loop == nil else { return }
        isRunning = true
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRunning else { return }
                self.engine.step()
                self.processUserFills()
                let interval = self.baseTickInterval / self.speed.rawValue
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        isRunning = false
        loop?.cancel()
        loop = nil
    }

    /// 계좌 부검 통과 후: 새 시드머니로 새 시장을 연다 (M4-3).
    func resetForNewSeason() {
        stop()
        engineSeed = .random(in: 0...UInt64.max)
        let fresh = MarketEngine(seed: engineSeed)
        fresh.advance(ticks: fresh.config.ticksPerCandle * 30)
        engine = fresh
        startPrice = fresh.candles.last?.close ?? fresh.lastPrice
        speed = .x1
        persistState()
        start()
    }

    /// 주문 시트가 열리면 1x로 낮춰 정밀 매매를 방해하지 않는다 (스펙 1).
    private var speedBeforeOrder: Speed?

    func orderSheetOpened() {
        speedBeforeOrder = speed
        speed = .x1
    }

    func orderSheetClosed() {
        if let restored = speedBeforeOrder {
            speed = restored
            speedBeforeOrder = nil
        }
    }

    // MARK: 주문

    func placeOrder(side: Side, qty: Int) -> Result<FillResult, OrderError> {
        do {
            let fill = try engine.placeMarketOrder(side: side, qty: qty)
            return .success(fill)
        } catch let error as OrderError {
            return .failure(error)
        } catch {
            return .failure(.noLiquidity)
        }
    }

    // MARK: 지정가 (①)

    /// 대기 주문 ID → 주문 시 고른 태그 (사후 체결 기록용)
    private var limitTags: [UInt64: TradeReasonTag] = [:]
    /// 방금 체결된 대기 주문 알림 (UI 배너)
    private(set) var limitFillNotice: String?

    func placeLimitOrder(side: Side, price: Int, qty: Int, tag: TradeReasonTag)
    -> Result<MarketEngine.LimitOrderResult, OrderError> {
        do {
            let result = try engine.placeLimitOrder(side: side, price: price, qty: qty)
            if let resting = result.restingOrder {
                limitTags[resting.id] = tag
            }
            return .success(result)
        } catch let error as OrderError {
            return .failure(error)
        } catch {
            return .failure(.noLiquidity)
        }
    }

    func cancelOrder(id: UInt64) {
        engine.cancelOrder(id: id)
        limitTags[id] = nil
        persistState()
        store?.persistPortfolio(engine.portfolio)
    }

    /// 대기 체결 이벤트를 기록·영속·알림으로 처리. 루프와 스킵·복귀 후에 호출된다.
    func processUserFills() {
        let events = engine.drainUserFillEvents()
        guard !events.isEmpty else { return }
        for event in events {
            let fallback: TradeReasonTag = event.side == .buy ? .gutBuy : .gutSell
            let tag = limitTags[event.orderId] ?? fallback
            let fill = FillResult(side: event.side, requestedQty: event.qty,
                                  fills: [Fill(price: event.price, qty: event.qty)],
                                  displayedPrice: event.price)
            store?.record(fill: fill, tag: tag,
                          avgCostBeforeOrder: event.avgCostBefore,
                          atTick: engine.tick,
                          atCandleIndex: engine.candles.count,
                          wasLimit: true)
            if !engine.openOrders.contains(where: { $0.id == event.orderId }) {
                limitTags[event.orderId] = nil
            }
            limitFillNotice = "지정가 체결 · \(event.side == .buy ? "매수" : "매도") \(event.qty)주 @ \(event.price.formatted())원"
        }
        store?.persistPortfolio(engine.portfolio)
        persistState()
        Task {
            try? await Task.sleep(for: .seconds(4))
            limitFillNotice = nil
        }
    }

    /// 다음 캔들로 스킵 — 스킵 중 발생한 대기 체결도 처리한다.
    func skipToNextCandle() {
        engine.advanceToNextCandle()
        processUserFills()
    }
}
