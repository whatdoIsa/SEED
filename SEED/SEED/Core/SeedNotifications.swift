import Foundation
import UserNotifications

/// 주간 복기 푸시 (B, §6.2) — 리텐션 루프의 마지막 조각.
/// 일요일 저녁, 한 주의 매매가 정리됐음을 알린다. 서버 없이 로컬 알림만 쓴다.
@MainActor
enum SeedNotifications {
    private static let weeklyId = "seed.weeklyReview"

    /// 첫 매매 직후 호출 — 의미 있는 순간에만 권한을 묻는다.
    static func requestThenScheduleWeekly(weeklyTradeCount: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                scheduleWeekly(weeklyTradeCount: weeklyTradeCount)
            }
        }
    }

    /// 백그라운드 진입마다 호출 — 이미 허용된 경우에만 최신 숫자로 갱신.
    static func rescheduleIfAuthorized(weeklyTradeCount: Int) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            Task { @MainActor in
                scheduleWeekly(weeklyTradeCount: weeklyTradeCount)
            }
        }
    }

    private static func scheduleWeekly(weeklyTradeCount: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyId])

        let content = UNMutableNotificationContent()
        content.title = "주간 복기가 준비됐어요"
        content.body = weeklyTradeCount > 0
            ? "이번 주 매매 \(weeklyTradeCount)건 — 내 패턴을 확인해보세요."
            : "이번 주 시장을 돌아보고, 다음 주의 한 가지를 정해보세요."
        content.sound = .default

        // 일요일 19시 반복
        var date = DateComponents()
        date.weekday = 1
        date.hour = 19
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)

        center.add(UNNotificationRequest(identifier: weeklyId, content: content, trigger: trigger))
    }
}
