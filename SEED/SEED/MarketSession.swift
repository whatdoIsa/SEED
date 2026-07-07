import Foundation
import Observation
import JurinKit

/// 엔진들과 UI 사이의 드라이버 (다종목).
/// 모든 종목의 시장이 함께 흐르고(같은 시간), 계좌 원장은 하나를 공유한다.
/// 엔진에는 Timer가 없으므로 배속에 맞춰 step을 호출하는 책임이 여기 있다.
@Observable
@MainActor
final class MarketSession {

    enum Speed: Int, CaseIterable, Identifiable {
        case x1 = 1, x5 = 5, x30 = 30
        var id: Int { rawValue }
        var label: String { "\(rawValue)x" }
    }

    private(set) var ledger: AccountLedger
    private(set) var engines: [String: MarketEngine] = [:]
    var activeSymbolCode: String = SymbolCatalog.all[0].code
    var speed: Speed = .x1
    private(set) var isRunning = false
    /// 종목별 세션 시작 기준가 — 등락 표시의 기준.
    private(set) var startPrices: [String: Int] = [:]
    /// 종목별 시드 (영속용)
    private(set) var engineSeeds: [String: UInt64] = [:]

    private weak var store: SeedStore?
    private var loop: Task<Void, Never>?
    /// 1x에서 1틱 ≈ 1초. 배속은 간격을 줄인다.
    private let baseTickInterval: Duration = .seconds(1)
    /// 백그라운드 경과를 따라잡는 상한 — 최대 30분치.
    private let catchUpCap = 1_800
    private let warmupCandles = 30

    var activeSpec: SymbolSpec { SymbolCatalog.spec(code: activeSymbolCode) ?? SymbolCatalog.all[0] }
    var engine: MarketEngine { engines[activeSymbolCode] ?? enginesList[0] }
    var enginesList: [MarketEngine] { SymbolCatalog.all.compactMap { engines[$0.code] } }

    init(store: SeedStore?) {
        let ledger = AccountLedger(cash: 10_000_000)
        // 시장 기후: 시즌 고정 시드 — 모든 종목이 같은 기후를 공유해 상관되어 움직인다.
        let climate = MarketClimate(seed: store?.climateSeed() ?? .random(in: 0...UInt64.max))
        var engines: [String: MarketEngine] = [:]
        var seeds: [String: UInt64] = [:]
        var freshCodes: [String] = []
        var restoredTargets: [String: Int] = [:]

        for spec in SymbolCatalog.all {
            if let state = store?.symbolState(code: spec.code) {
                // 연속성: 같은 시드 → 리플레이로 같은 시장·계좌 복원
                seeds[spec.code] = state.seed
                restoredTargets[spec.code] = state.tick
                engines[spec.code] = MarketEngine(
                    seed: state.seed, initialPrice: spec.initialPrice,
                    config: spec.config, symbol: spec.code, ledger: ledger, climate: climate)
            } else {
                let seed = UInt64.random(in: 0...UInt64.max)
                seeds[spec.code] = seed
                let engine = MarketEngine(
                    seed: seed, initialPrice: spec.initialPrice,
                    config: spec.config, symbol: spec.code, ledger: ledger, climate: climate)
                engine.advance(ticks: spec.config.ticksPerCandle * warmupCandles)
                engines[spec.code] = engine
                freshCodes.append(spec.code)
            }
        }

        // 전 종목 주문을 틱 순으로 리플레이 — 현금 흐름의 시간 순서를 보존한다
        if !restoredTargets.isEmpty {
            for log in store?.replayableLogs() ?? [] {
                guard let code = SymbolCatalog.code(forName: log.symbol),
                      let target = restoredTargets[code],
                      let engine = engines[code],
                      let atTick = log.atTick, atTick <= target else { continue }
                engine.advance(ticks: max(atTick - engine.tick, 0))
                if log.isLimitFill == true {
                    engine.restoreFill(side: log.side, price: Int(log.avgFillPrice), qty: log.qty)
                } else {
                    _ = try? engine.placeMarketOrder(side: log.side, qty: log.qty)
                }
            }
            for (code, target) in restoredTargets {
                engines[code]?.advance(ticks: max(target - (engines[code]?.tick ?? 0), 0))
            }
        }

        self.ledger = ledger
        self.engines = engines
        self.engineSeeds = seeds
        self.startPrices = engines.mapValues { $0.candles.last?.close ?? $0.lastPrice }
        self.store = store

        for code in freshCodes {
            persistSymbol(code)
        }
    }

    // MARK: 등락·자산

    var startPrice: Int { startPrices[activeSymbolCode] ?? engine.lastPrice }
    var change: Int { engine.lastPrice - startPrice }
    var changePercent: Double {
        guard startPrice > 0 else { return 0 }
        return Double(change) / Double(startPrice) * 100
    }

    var currentPrices: [String: Int] {
        engines.mapValues(\.lastPrice)
    }

    /// 전 종목 통합 평가액 — 진짜 내 자산.
    var totalEquity: Int {
        ledger.totalEquity(prices: currentPrices)
    }

    // MARK: 연속성

    private func persistSymbol(_ code: String) {
        guard let engine = engines[code], let seed = engineSeeds[code] else { return }
        store?.persistSymbolState(code: code, seed: seed, tick: engine.tick)
    }

    func persistState() {
        for code in engines.keys { persistSymbol(code) }
    }

    /// 씬 전환 처리: 백그라운드 진입 시 상태 저장, 복귀 시 경과분 따라잡기 (catch-up).
    func handleScenePhase(active: Bool) {
        if active {
            catchUpAfterBackground()
            start()
        } else {
            stop()
            persistState()
        }
    }

    private func catchUpAfterBackground() {
        guard let lastActive = store?.lastActiveAt else { return }
        let elapsed = Int(Date.now.timeIntervalSince(lastActive))
        guard elapsed > 2 else { return }
        let ticks = min(elapsed, catchUpCap)
        for engine in enginesList { engine.advance(ticks: ticks) }
        processUserFills()
        persistState()
    }

    // MARK: 루프 제어 — 모든 종목의 시간이 함께 흐른다

    func start() {
        guard loop == nil else { return }
        isRunning = true
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRunning else { return }
                for engine in self.enginesList { engine.step() }
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

    /// 계좌 부검 통과 후: 새 원장·새 시장들·새 기후로 새 시즌을 연다 (M4-3).
    func resetForNewSeason() {
        stop()
        let fresh = AccountLedger(cash: 10_000_000)
        // 새 시즌 = 새 기후 (store가 시즌 전환 후 새 시드를 발급·고정한다)
        let climate = MarketClimate(seed: store?.climateSeed() ?? .random(in: 0...UInt64.max))
        var engines: [String: MarketEngine] = [:]
        var seeds: [String: UInt64] = [:]
        for spec in SymbolCatalog.all {
            let seed = UInt64.random(in: 0...UInt64.max)
            seeds[spec.code] = seed
            let engine = MarketEngine(seed: seed, initialPrice: spec.initialPrice,
                                      config: spec.config, symbol: spec.code,
                                      ledger: fresh, climate: climate)
            engine.advance(ticks: spec.config.ticksPerCandle * warmupCandles)
            engines[spec.code] = engine
        }
        self.ledger = fresh
        self.engines = engines
        self.engineSeeds = seeds
        self.startPrices = engines.mapValues { $0.candles.last?.close ?? $0.lastPrice }
        self.limitTags = [:]
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

    // MARK: 주문 (활성 종목)

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

    /// "종목코드#주문ID" → 주문 시 고른 태그 (사후 체결 기록용)
    private var limitTags: [String: TradeReasonTag] = [:]
    /// 방금 체결된 대기 주문 알림 (UI 배너)
    private(set) var limitFillNotice: String?

    func placeLimitOrder(side: Side, price: Int, qty: Int, tag: TradeReasonTag)
    -> Result<MarketEngine.LimitOrderResult, OrderError> {
        do {
            let result = try engine.placeLimitOrder(side: side, price: price, qty: qty)
            if let resting = result.restingOrder {
                limitTags["\(activeSymbolCode)#\(resting.id)"] = tag
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
        limitTags["\(activeSymbolCode)#\(id)"] = nil
        persistSymbol(activeSymbolCode)
    }

    /// 전 종목의 대기 체결 이벤트를 기록·영속·알림으로 처리.
    func processUserFills() {
        for spec in SymbolCatalog.all {
            guard let engine = engines[spec.code] else { continue }
            let events = engine.drainUserFillEvents()
            guard !events.isEmpty else { continue }
            for event in events {
                let key = "\(spec.code)#\(event.orderId)"
                let fallback: TradeReasonTag = event.side == .buy ? .gutBuy : .gutSell
                let tag = limitTags[key] ?? fallback
                let fill = FillResult(side: event.side, requestedQty: event.qty,
                                      fills: [Fill(price: event.price, qty: event.qty)],
                                      displayedPrice: event.price)
                store?.record(fill: fill, tag: tag, symbol: spec.name,
                              avgCostBeforeOrder: event.avgCostBefore,
                              atTick: engine.tick,
                              atCandleIndex: engine.candles.count,
                              wasLimit: true)
                if !engine.openOrders.contains(where: { $0.id == event.orderId }) {
                    limitTags[key] = nil
                }
                limitFillNotice = "\(spec.name) 지정가 체결 · \(event.side == .buy ? "매수" : "매도") \(event.qty)주 @ \(event.price.formatted())원"
            }
            persistSymbol(spec.code)
        }
        if limitFillNotice != nil {
            Task {
                try? await Task.sleep(for: .seconds(4))
                limitFillNotice = nil
            }
        }
    }

    /// 다음 캔들로 스킵 — 모든 종목의 시간이 함께 간다.
    func skipToNextCandle() {
        for engine in enginesList { engine.advanceToNextCandle() }
        processUserFills()
    }
}
