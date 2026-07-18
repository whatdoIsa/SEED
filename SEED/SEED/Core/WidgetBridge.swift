import Foundation
import WidgetKit

/// 위젯에 완료 기록을 넘기는 다리.
/// 위젯은 SwiftData를 열지 않는다 — 앱이 App Group에 써두면 읽기만 한다.
/// 계산된 스트릭이 아니라 **완료 날짜 도장 원본**을 넘긴다: 위젯이 렌더 시점 날짜로
/// 스트릭·주간을 재계산하므로, 앱을 며칠 안 열어도 낡은 "🔥 N일 연속"이 남지 않는다.
enum WidgetBridge {
    private static let suite = "group.kr.arcseed.SEED"

    @MainActor
    static func sync(completed: Set<String>) {
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        let stamps = completed.compactMap { id -> Int? in
            guard id.hasPrefix("daily.") else { return nil }
            return Int(id.dropFirst("daily.".count))
        }.sorted().suffix(90)
        defaults.set(Array(stamps), forKey: "seed.widget.doneStamps")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
