import SwiftUI
import JurinKit

/// 라이브 시장 화면들의 공용 부품 — 아레나·리매치·인내 미션이 같은 뼈대를 공유한다.
/// (중복 제거: 루프 관리 · 배속 컨트롤 · 매매 버튼)

// MARK: - 시장 루프 (워밍업 + 일시정지 + 배속 + 종료 콜백)

@MainActor
@Observable
final class LiveLoop {
    var isPaused = false
    var speed = 1

    private var task: Task<Void, Never>?
    private let delays = [1: 40, 2: 22, 4: 11]

    /// 자유 매매용 루프: 결정 지점은 조용히 통과, 시나리오 끝나면 onFinish.
    func start(engine: MarketEngine,
               prerollTicks: Int = 160,
               onFinish: @escaping () -> Void) {
        guard task == nil else { return }
        // 워밍업: 빈 차트에 거대 막대가 쌓이는 혼란 방지
        if engine.tick == 0 { engine.advance(ticks: prerollTicks) }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.isPaused {
                    engine.step()
                    if engine.pendingDecision != nil { engine.resolveDecision() }
                    if engine.isScenarioFinished {
                        // task를 비워야 이후 start()가 무시되지 않는다 (자연 종료 경로)
                        self.task = nil
                        onFinish()
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(self.delays[self.speed] ?? 40))
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

// MARK: - 배속 컨트롤 (일시정지 + 1/2/4x)

struct SpeedControls: View {
    @Bindable var loop: LiveLoop
    var pausedHint: String?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                loop.isPaused.toggle()
            } label: {
                Image(systemName: loop.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SeedTheme.inverse)
                    .frame(width: 38, height: 30)
                    .background(SeedTheme.textPrimary, in: Capsule())
            }
            ForEach([1, 2, 4], id: \.self) { value in
                Button {
                    loop.speed = value
                    loop.isPaused = false
                } label: {
                    Text("\(value)x")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(loop.speed == value && !loop.isPaused
                                         ? SeedTheme.inverse : SeedTheme.textSecondary)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(loop.speed == value && !loop.isPaused
                                    ? SeedTheme.textPrimary : SeedTheme.card,
                                    in: Capsule())
                }
            }
            Spacer()
            if loop.isPaused, let pausedHint {
                Text(pausedHint)
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
        }
    }
}

// MARK: - 매매 버튼 (사기 / 보유 시 전량 팔기)

struct LiveTradeButtons: View {
    let engine: MarketEngine
    let onTraded: (Side, FillResult) -> Void

    @State private var tradeCount = 0

    var body: some View {
        HStack(spacing: 8) {
            Button {
                trade(side: .buy)
            } label: {
                Text("100주 사기")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(SeedTheme.up, in: RoundedRectangle(cornerRadius: 12))
            }
            if engine.portfolio.qty > 0 {
                Button {
                    trade(side: .sell)
                } label: {
                    Text("전량 팔기")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(SeedTheme.down, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: engine.portfolio.qty > 0)
        .sensoryFeedback(.success, trigger: tradeCount)
    }

    private func trade(side: Side) {
        let qty = side == .buy ? 100 : engine.portfolio.qty
        guard qty > 0, let fill = try? engine.placeMarketOrder(side: side, qty: qty) else { return }
        tradeCount += 1
        onTraded(side, fill)
    }
}
