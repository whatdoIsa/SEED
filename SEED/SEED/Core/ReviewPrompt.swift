import StoreKit
import UIKit

/// 앱 평가 요청 — 만족의 정점에서만, 조심스럽게 한 번.
/// Apple이 연 3회로 제한하므로: 모멘트당 평생 1회 + 요청 간 최소 14일 간격.
/// 시뮬레이터에선 항상 뜨지만 실기기에선 시스템 재량으로 생략될 수 있다.
@MainActor
enum ReviewPrompt {

    enum Moment: String {
        /// 오늘의 장 3일 연속 — 출시 초기 가장 빨리 도달하는 만족 순간
        case streak3 = "streak3"
        /// 첫 수익 실현 매도
        case firstProfit = "first_profit"
        /// 트랙 1 졸업
        case graduation = "graduation"
        /// 시즌 완주 (부검 후 새 시즌 시작)
        case seasonEnd = "season_end"
    }

    private static let lastAskKey = "seed.review.lastAskAt"
    private static let minimumInterval: TimeInterval = 14 * 86_400

    static func askIfEligible(_ moment: Moment) {
        let defaults = UserDefaults.standard
        let momentKey = "seed.review.done.\(moment.rawValue)"
        guard !defaults.bool(forKey: momentKey) else { return }

        let lastAsk = defaults.double(forKey: lastAskKey)
        if lastAsk > 0, Date.now.timeIntervalSince1970 - lastAsk < minimumInterval { return }

        defaults.set(true, forKey: momentKey)
        defaults.set(Date.now.timeIntervalSince1970, forKey: lastAskKey)
        Analytics.log(.reviewPrompted, ["moment": moment.rawValue])

        // 화면 전환(시트·커버 닫힘)이 정리된 뒤 요청 — 전환 중엔 시스템이 무시한다
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            else { return }
            AppStore.requestReview(in: scene)
        }
    }
}
