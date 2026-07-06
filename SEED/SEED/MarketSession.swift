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

    let engine: MarketEngine
    var speed: Speed = .x1
    private(set) var isRunning = false
    /// 세션 시작 기준가 — 등락 표시의 기준.
    let startPrice: Int

    private var loop: Task<Void, Never>?
    /// 1x에서 1틱 ≈ 1초. 배속은 간격을 줄인다.
    private let baseTickInterval: Duration = .seconds(1)

    init(seed: UInt64 = .random(in: 0...UInt64.max)) {
        let engine = MarketEngine(seed: seed)
        // 첫 화면이 비어 보이지 않게 과거 캔들을 미리 만들어 둔다.
        engine.advance(ticks: engine.config.ticksPerCandle * 30)
        self.engine = engine
        self.startPrice = engine.candles.last?.close ?? engine.lastPrice
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
}
