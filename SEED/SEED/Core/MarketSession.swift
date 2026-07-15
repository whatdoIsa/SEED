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
    /// 합성 ETF 펀드 (트랙 2) — 종목 엔진들 위의 바스켓 상품. 같은 원장을 공유한다.
    private(set) var etfFunds: [String: ETFFund] = [:]

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
        self.ledger = AccountLedger(cash: 10_000_000)
        self.store = store
        bootstrap()
    }

    /// 저장소에서 시장·계좌를 (재)구성한다. 원장 복원 순서:
    /// 시즌 베이스라인 → (장기 시즌이면 스냅샷 폴백 = 타임라인 리셋) → 현재 타임라인 리플레이.
    private func bootstrap() {
        let ledger = AccountLedger(cash: 10_000_000)
        // 타임라인 리셋 이전의 매매는 베이스라인에 반영돼 있다 — 원장을 여기서 시작한다.
        if let baseline = store?.ledgerBaseline() {
            ledger.restore(cash: baseline.cash,
                           realizedPnL: baseline.realizedPnL,
                           feesPaid: baseline.feesPaid,
                           holdings: baseline.holdingTuples)
        }
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

        // 합성 ETF — 구성 좌수가 스펙 초기가 기준 상수라 시즌·세션 무관하게 결정론적
        var funds: [String: ETFFund] = [:]
        for spec in ETFCatalog.all {
            funds[spec.code] = spec.makeFund(ledger: ledger)
        }

        // 장기 시즌 가드: 리플레이 총량이 크면(수 초 이상 걸릴 규모)
        // 차트 연속성을 포기하고 계좌만 복원한다 — 시작 지연·런치 워치독 방지.
        let totalReplaySteps = restoredTargets.values.reduce(0, +)
        let replayBudgetSteps = 300_000 // 릴리즈 기준 ~1.5초
        if totalReplaySteps > replayBudgetSteps {
            // 시드 지문이 맞는 스냅샷만 신뢰한다 — 임포트 전 부트스트랩 세션이 남긴
            // 초기 계좌 스냅샷을 복원본 위에 씌우는 사고 방지.
            if let snapshot = LedgerSnapshot.load(seasonNumber: store?.currentSeason.number ?? 1),
               snapshot.matches(seeds: seeds) {
                ledger.restore(cash: snapshot.cash,
                               realizedPnL: snapshot.realizedPnL,
                               feesPaid: snapshot.feesPaid,
                               holdings: snapshot.holdingTuples)
                // 베이스라인으로 못박아 두면 다음 부팅은 (스냅샷 없이도) 여기서 이어간다
                store?.beginNewTimeline(baseline: snapshot)
            } else {
                // 스냅샷이 없거나(새 기기 iCloud 복원 — 스냅샷은 기기 로컬 UserDefaults) 지문 불일치:
                // 기록된 체결가로 원장만 재구성한다. 여기서 풀 리플레이를 강행하면
                // 메인 스레드가 수십 초 블록되어 런치 워치독(0x8badf00d)에 죽는다.
                for log in store?.replayableLogs() ?? [] {
                    let price = Int(log.avgFillPrice.rounded())
                    if let etfCode = ETFCatalog.code(forName: log.symbol) {
                        funds[etfCode]?.restoreFill(side: log.side, price: price, qty: log.qty)
                    } else if let code = SymbolCatalog.code(forName: log.symbol) {
                        engines[code]?.restoreFill(side: log.side, price: price, qty: log.qty)
                    }
                }
                let rebuilt = LedgerSnapshot(
                    seasonNumber: store?.currentSeason.number ?? 1,
                    cash: ledger.cash,
                    realizedPnL: ledger.realizedPnL,
                    feesPaid: ledger.feesPaid,
                    holdings: ledger.holdings.mapValues {
                        LedgerSnapshot.HoldingSnap(qty: $0.qty, avgCost: $0.avgCost)
                    },
                    seedsHash: nil)
                store?.beginNewTimeline(baseline: rebuilt)
            }
            // 공통: 타임라인 리셋 — 새 시장(워밍업)으로 교체
            for spec in SymbolCatalog.all where restoredTargets[spec.code] != nil {
                let seed = UInt64.random(in: 0...UInt64.max)
                seeds[spec.code] = seed
                let engine = MarketEngine(
                    seed: seed, initialPrice: spec.initialPrice,
                    config: spec.config, symbol: spec.code, ledger: ledger, climate: climate)
                engine.advance(ticks: spec.config.ticksPerCandle * warmupCandles)
                engines[spec.code] = engine
                store?.replaceSymbolState(code: spec.code, seed: seed, tick: engine.tick)
            }
            restoredTargets.removeAll()
        }

        // 전 종목 주문을 틱 순으로 리플레이 — 현금 흐름의 시간 순서를 보존한다
        let replayedTimeline = !restoredTargets.isEmpty
        if !restoredTargets.isEmpty {
            for log in store?.replayableLogs() ?? [] {
                // ETF 체결은 기록된 NAV 그대로 원장에만 반영 (호가창 없음)
                if let etfCode = ETFCatalog.code(forName: log.symbol) {
                    funds[etfCode]?.restoreFill(side: log.side,
                                                price: Int(log.avgFillPrice.rounded()),
                                                qty: log.qty)
                    continue
                }
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
        self.etfFunds = funds
        self.startPrices = engines.mapValues { $0.candles.last?.close ?? $0.lastPrice }

        // 미체결 지정가 복원 — 같은 시드·틱으로 되살린 같은 시장에 재접수한다.
        // (스냅샷 폴백 = 다른 시장이므로 재접수하지 않는다 — 기존 전제 유지)
        if replayedTimeline {
            restoreOpenOrders()
        }

        for code in freshCodes {
            persistSymbol(code)
        }
    }

    /// 재시작 전에 걸려 있던 지정가를 다시 접수한다. 큐 순번은 근사(맨 뒤 합류)이고,
    /// 리플레이 근사 오차로 시장이 지정가를 지나쳐 있으면 즉시 체결 — 정상 흐름으로 기록한다.
    private func restoreOpenOrders() {
        for spec in SymbolCatalog.all {
            guard let data = store?.openOrdersData(code: spec.code),
                  let saved = try? JSONDecoder().decode([PersistedOrder].self, from: data),
                  let engine = engines[spec.code] else { continue }
            for order in saved {
                guard let side = Side(rawValue: order.sideRaw) else { continue }
                let tag = TradeReasonTag(rawValue: order.tagRaw)
                    ?? (side == .buy ? .gutBuy : .gutSell)
                let avgBefore = ledger.avgCost(of: spec.code)
                guard let result = try? engine.placeLimitOrder(
                    side: side, price: order.price, qty: order.qty) else { continue }
                if let resting = result.restingOrder {
                    limitTags["\(spec.code)#\(resting.id)"] = tag
                }
                if let fill = result.immediateFill {
                    store?.record(fill: fill, tag: tag, symbol: spec.name,
                                  avgCostBeforeOrder: avgBefore,
                                  atTick: engine.tick,
                                  atCandleIndex: engine.candles.count,
                                  wasLimit: true)
                }
            }
        }
    }

    /// iCloud 임포트가 세션 생성 뒤에 도착했을 때: 저장소의 시장 상태가 지금 세션과
    /// 다르면(= 복원본이 합류했으면) 세션을 다시 구성한다. 이게 없으면 매매 기록은
    /// 보이는데 현금은 초기값 그대로인 화면이 된다.
    func adoptRemoteStateIfNeeded() {
        guard store != nil else { return }
        let mismatch = SymbolCatalog.all.contains { spec in
            guard let state = store?.symbolState(code: spec.code) else { return false }
            return state.seed != engineSeeds[spec.code]
        }
        guard mismatch else { return }
        let wasRunning = isRunning
        stop()
        limitTags = [:]
        bootstrap()
        if wasRunning { start() }
    }

    // MARK: 등락·자산

    var startPrice: Int { startPrices[activeSymbolCode] ?? engine.lastPrice }
    /// 등락 기준 — 전일 종가(기준가). 차트 선 색·현재가 배지와 같은 기준이라
    /// 화면 전체가 한 목소리를 낸다 (실제 증권앱과 동일).
    /// 크립토(거래일 없음)는 기준가가 갱신되지 않으므로 세션 시작가 기준을 유지한다.
    private var changeBasis: Int {
        engine.config.candlesPerDay > 0 ? engine.referencePrice : startPrice
    }
    var change: Int { engine.lastPrice - changeBasis }
    var changePercent: Double {
        guard changeBasis > 0 else { return 0 }
        return Double(change) / Double(changeBasis) * 100
    }

    var currentPrices: [String: Int] {
        var prices = engines.mapValues(\.lastPrice)
        let members = prices
        for (code, fund) in etfFunds {
            prices[code] = fund.nav(prices: members, daysElapsed: etfDaysElapsed)
        }
        return prices
    }

    /// 전 종목 통합 평가액 — 진짜 내 자산.
    var totalEquity: Int {
        ledger.totalEquity(prices: currentPrices)
    }

    // MARK: ETF (트랙 2) — NAV 호가·매매

    /// 보수 차감의 기준 경과 거래일 — 기준 종목(대형주) 엔진의 거래일에서 파생.
    var etfDaysElapsed: Int {
        max((engines[SymbolCatalog.all[0].code]?.tradingDay ?? 1) - 1, 0)
    }

    func etfNAV(_ code: String) -> Int {
        guard let fund = etfFunds[code] else { return 0 }
        return fund.nav(prices: engines.mapValues(\.lastPrice), daysElapsed: etfDaysElapsed)
    }

    /// 등락 기준 — 구성 종목의 기준가(전일 종가)로 계산한 NAV. 화면 전체가 같은 기준.
    func etfReferenceNAV(_ code: String) -> Int {
        guard let fund = etfFunds[code] else { return 0 }
        return fund.nav(prices: engines.mapValues(\.referencePrice), daysElapsed: etfDaysElapsed)
    }

    func etfChangePercent(_ code: String) -> Double {
        let basis = etfReferenceNAV(code)
        guard basis > 0 else { return 0 }
        return Double(etfNAV(code) - basis) / Double(basis) * 100
    }

    /// NAV 히스토리 — 구성 종목 분봉 종가에서 재구성 (라인차트 원료).
    func etfNAVSeries(_ code: String, maxPoints: Int = 120) -> [Int] {
        guard let fund = etfFunds[code],
              let firstMember = fund.components.first?.symbol,
              let referenceEngine = engines[firstMember] else { return [] }
        let counts = fund.components.compactMap { engines[$0.symbol]?.candles.count }
        guard let count = counts.min(), count > 0 else { return [] }
        let candlesPerDay = max(referenceEngine.config.candlesPerDay, 1)
        let start = max(count - maxPoints, 0)
        return (start..<count).map { index in
            var prices: [String: Int] = [:]
            for component in fund.components {
                if let candles = engines[component.symbol]?.candles, index < candles.count {
                    prices[component.symbol] = candles[index].close
                }
            }
            return fund.nav(prices: prices, daysElapsed: index / candlesPerDay)
        }
    }

    func buyETF(code: String, qty: Int, tag: TradeReasonTag) -> Result<FillResult, OrderError> {
        guard let fund = etfFunds[code] else { return .failure(.noLiquidity) }
        let avgBefore = ledger.avgCost(of: code)
        do {
            let fill = try fund.buy(qty: qty, prices: engines.mapValues(\.lastPrice),
                                    daysElapsed: etfDaysElapsed)
            recordETF(fill: fill, fund: fund, tag: tag, avgCostBefore: avgBefore)
            return .success(fill)
        } catch let error as OrderError {
            return .failure(error)
        } catch {
            return .failure(.noLiquidity)
        }
    }

    func sellETF(code: String, qty: Int, tag: TradeReasonTag) -> Result<FillResult, OrderError> {
        guard let fund = etfFunds[code] else { return .failure(.noLiquidity) }
        let avgBefore = ledger.avgCost(of: code)
        do {
            let fill = try fund.sell(qty: qty, prices: engines.mapValues(\.lastPrice),
                                     daysElapsed: etfDaysElapsed)
            recordETF(fill: fill, fund: fund, tag: tag, avgCostBefore: avgBefore)
            return .success(fill)
        } catch let error as OrderError {
            return .failure(error)
        } catch {
            return .failure(.noLiquidity)
        }
    }

    private func recordETF(fill: FillResult, fund: ETFFund,
                           tag: TradeReasonTag, avgCostBefore: Double) {
        let referenceEngine = engines[SymbolCatalog.all[0].code]
        store?.record(fill: fill, tag: tag, symbol: fund.name,
                      avgCostBeforeOrder: avgCostBefore,
                      atTick: referenceEngine?.tick,
                      atCandleIndex: referenceEngine?.candles.count,
                      wasLimit: false)
        persistState()
    }

    // MARK: 연속성

    /// 미체결 지정가의 영속 형태 (SymbolState.openOrdersData)
    struct PersistedOrder: Codable {
        let sideRaw: String
        let price: Int
        let qty: Int
        let tagRaw: String
    }

    private func persistSymbol(_ code: String) {
        guard let engine = engines[code], let seed = engineSeeds[code] else { return }
        store?.persistSymbolState(code: code, seed: seed, tick: engine.tick,
                                  openOrders: encodedOpenOrders(code: code, engine: engine))
    }

    private func encodedOpenOrders(code: String, engine: MarketEngine) -> Data? {
        guard !engine.openOrders.isEmpty else { return nil }
        let orders = engine.openOrders.map { order in
            PersistedOrder(
                sideRaw: order.side.rawValue,
                price: order.price,
                qty: order.remainingQty,
                tagRaw: (limitTags["\(code)#\(order.id)"]
                         ?? (order.side == .buy ? .gutBuy : .gutSell)).rawValue)
        }
        return try? JSONEncoder().encode(orders)
    }

    func persistState() {
        for code in engines.keys { persistSymbol(code) }
        LedgerSnapshot.save(from: ledger, seasonNumber: store?.currentSeason.number ?? 1,
                            seeds: engineSeeds)
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
        var funds: [String: ETFFund] = [:]
        for spec in ETFCatalog.all {
            funds[spec.code] = spec.makeFund(ledger: fresh)
        }
        self.etfFunds = funds
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
    /// 배너 소멸 세대 — 연속 체결 시 앞선 타이머가 새 배너를 조기에 지우는 것 방지
    private var limitFillNoticeGeneration = 0

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
        // 취소 직전에 정산된 체결이 있을 수 있다 — 태그가 살아 있는 동안 먼저 기록
        processUserFills()
        limitTags["\(activeSymbolCode)#\(id)"] = nil
        persistSymbol(activeSymbolCode)
    }

    /// 전 종목의 대기 체결 이벤트를 기록·영속·알림으로 처리.
    func processUserFills() {
        var hadFills = false
        for spec in SymbolCatalog.all {
            guard let engine = engines[spec.code] else { continue }
            let events = engine.drainUserFillEvents()
            guard !events.isEmpty else { continue }
            hadFills = true
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
        // 지정가 체결도 스냅샷을 갱신 — 백그라운드 전환 없이 죽으면(크래시·잿섬)
        // 장기 시즌의 스냅샷 폴백 계좌가 체결 이전으로 되돌아가는 구멍 방지.
        if hadFills {
            LedgerSnapshot.save(from: ledger, seasonNumber: store?.currentSeason.number ?? 1,
                                seeds: engineSeeds)
        }
        if limitFillNotice != nil {
            limitFillNoticeGeneration += 1
            let generation = limitFillNoticeGeneration
            Task {
                try? await Task.sleep(for: .seconds(4))
                guard generation == limitFillNoticeGeneration else { return }
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

// MARK: - 원장 스냅샷 (장기 시즌 리플레이 가드의 폴백)

struct LedgerSnapshot: Codable {
    struct HoldingSnap: Codable {
        let qty: Int
        let avgCost: Double
    }
    let seasonNumber: Int
    let cash: Int
    let realizedPnL: Double
    let feesPaid: Int
    let holdings: [String: HoldingSnap]
    /// 저장 당시 엔진 시드들의 XOR 지문 — 다른 시장의 스냅샷(임포트 전 부트스트랩
    /// 세션이 남긴 초기 계좌)을 복원본에 씌우는 것을 막는다. nil = 구버전 저장분(수용).
    var seedsHash: UInt64?

    var holdingTuples: [String: (qty: Int, avgCost: Double)] {
        holdings.mapValues { ($0.qty, $0.avgCost) }
    }

    func matches(seeds: [String: UInt64]) -> Bool {
        guard let seedsHash else { return true }
        return seedsHash == Self.hash(of: seeds)
    }

    static func hash(of seeds: [String: UInt64]) -> UInt64 {
        seeds.values.reduce(0, ^)
    }

    private static let key = "seed.ledgerSnapshot"

    static func save(from ledger: AccountLedger, seasonNumber: Int, seeds: [String: UInt64]) {
        let snap = LedgerSnapshot(
            seasonNumber: seasonNumber,
            cash: ledger.cash,
            realizedPnL: ledger.realizedPnL,
            feesPaid: ledger.feesPaid,
            holdings: ledger.holdings.mapValues { HoldingSnap(qty: $0.qty, avgCost: $0.avgCost) },
            seedsHash: hash(of: seeds)
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load(seasonNumber: Int) -> LedgerSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snap = try? JSONDecoder().decode(LedgerSnapshot.self, from: data),
              snap.seasonNumber == seasonNumber else { return nil }
        return snap
    }
}
