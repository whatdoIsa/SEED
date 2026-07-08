import Foundation
import WidgetKit

/// 위젯에 스트릭 스냅샷을 넘기는 다리.
/// 위젯은 SwiftData를 열지 않는다 — 앱이 계산해서 App Group에 써두면 읽기만 한다.
enum WidgetBridge {
    private static let suite = "group.kr.arcseed.SEED"

    @MainActor
    static func sync(completed: Set<String>) {
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        defaults.set(DailyMarket.streak(completed: completed), forKey: "seed.widget.streak")
        defaults.set(DailyMarket.lastSevenDays(completed: completed).map { $0 ? 1 : 0 },
                     forKey: "seed.widget.week")
        // '오늘 했는가'는 위젯이 렌더 시점에 판정하도록 날짜 도장만 준다
        let doneToday = completed.contains(DailyMarket.id())
        defaults.set(doneToday ? DailyMarket.dayStamp() : 0, forKey: "seed.widget.lastDoneStamp")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
