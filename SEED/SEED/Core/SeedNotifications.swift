import Foundation
import UserNotifications

/// 로컬 알림 3종 — 아침 루틴 · 저녁 리마인더 · 주간 복기. 서버 없이 로컬만 쓴다.
///
/// 설계 원칙: 하루 최대 2발(아침·저녁), 저녁은 오늘의 장을 마치면 그날 것이 사라진다.
/// 전부 기본 켬이고 설정에서 종류별로 끌 수 있다.
///
/// 주의: 알림 센터는 XPC 기반이다. 콜백 클로저 대신 async API만 쓰고,
/// 앱이 서스펜드되는 순간(.background 전환)에는 절대 호출하지 않는다 —
/// XPC 응답과 프로세스 정지가 경합하면 dispatch 내부에서 크래시가 난다.
@MainActor
enum SeedNotifications {
    private static let weeklyId = "seed.weeklyReview"
    private static let morningId = "seed.morningRoutine"
    private static let eveningPrefix = "seed.eveningReminder."
    /// 저녁 리마인더는 반복 트리거 대신 7일치 개별 예약 —
    /// "오늘의 장을 마친 날"만 콕 집어 취소할 수 있어야 하기 때문.
    private static let eveningWindowDays = 7

    // MARK: 종류별 토글 (기본 전부 켬 — 설정 화면에서 제어)

    enum Kind: String, CaseIterable {
        case morning = "seed.notif.morning"
        case evening = "seed.notif.evening"
        case weekly = "seed.notif.weekly"
    }

    static func isEnabled(_ kind: Kind) -> Bool {
        UserDefaults.standard.object(forKey: kind.rawValue) as? Bool ?? true
    }

    static func setEnabled(_ kind: Kind, _ on: Bool,
                           weeklyTradeCount: Int, dailyDoneToday: Bool) {
        UserDefaults.standard.set(on, forKey: kind.rawValue)
        rescheduleIfAuthorized(weeklyTradeCount: weeklyTradeCount,
                               dailyDoneToday: dailyDoneToday)
    }

    // MARK: 진입점

    /// 첫 매매 직후 호출 — 의미 있는 순간에만 권한을 묻는다.
    static func requestThenScheduleAll(weeklyTradeCount: Int, dailyDoneToday: Bool) {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(
                options: [.alert, .sound, .badge])) ?? false
            guard granted else { return }
            await scheduleAll(weeklyTradeCount: weeklyTradeCount,
                              dailyDoneToday: dailyDoneToday)
        }
    }

    /// 앱 활성화·설정 변경 시 호출 — 이미 허용된 경우에만 갱신.
    static func rescheduleIfAuthorized(weeklyTradeCount: Int, dailyDoneToday: Bool) {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            await scheduleAll(weeklyTradeCount: weeklyTradeCount,
                              dailyDoneToday: dailyDoneToday)
        }
    }

    /// 오늘의 장 완료 순간 호출 — 오늘 저녁 리마인더만 걷어낸다.
    static func cancelTodayEveningReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [eveningId(for: .now)])
    }

    // MARK: 스케줄링

    private static func scheduleAll(weeklyTradeCount: Int, dailyDoneToday: Bool) async {
        await scheduleMorning()
        await scheduleEvening(dailyDoneToday: dailyDoneToday)
        await scheduleWeekly(weeklyTradeCount: weeklyTradeCount)
    }

    /// 아침 08:00 반복 — 복습과 오늘의 장을 한 발에 묶는다 (하루 첫 접속 유도).
    private static func scheduleMorning() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [morningId])
        guard isEnabled(.morning) else { return }

        let content = UNMutableNotificationContent()
        content.title = "아침 루틴이 준비됐어요"
        content.body = "복습 1문제, 그리고 오늘의 장 한 판 — 3분이면 충분해요."
        content.sound = .default

        var date = DateComponents()
        date.hour = 8
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        try? await center.add(
            UNNotificationRequest(identifier: morningId, content: content, trigger: trigger))
    }

    /// 저녁 20:00 — 앞으로 7일치 개별 예약. 오늘 이미 완료면 오늘 것은 건너뛴다.
    private static func scheduleEvening(dailyDoneToday: Bool) async {
        let center = UNUserNotificationCenter.current()
        // 기존 저녁 예약 전부 제거 후 다시 깐다 (창을 굴리는 가장 단순한 방법)
        let pending = await center.pendingNotificationRequests()
        let eveningIds = pending.map(\.identifier).filter { $0.hasPrefix(eveningPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: eveningIds)
        guard isEnabled(.evening) else { return }

        let calendar = Calendar.current
        for offset in 0..<eveningWindowDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: .now) else { continue }
            if offset == 0 && dailyDoneToday { continue }

            var date = calendar.dateComponents([.year, .month, .day], from: day)
            date.hour = 20
            // 이미 20시가 지난 날은 예약해도 울리지 않으므로 건너뛴다
            if let fireDate = calendar.date(from: date), fireDate <= .now { continue }

            let content = UNMutableNotificationContent()
            content.title = "오늘의 장이 아직 열려 있어요"
            content.body = "하루 한 판이 스트릭을 지켜요 — 3분이면 돼요."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
            try? await center.add(UNNotificationRequest(
                identifier: eveningId(for: day), content: content, trigger: trigger))
        }
    }

    private static func scheduleWeekly(weeklyTradeCount: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyId])
        guard isEnabled(.weekly) else { return }

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
        try? await center.add(
            UNNotificationRequest(identifier: weeklyId, content: content, trigger: trigger))
    }

    private static func eveningId(for day: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return eveningPrefix + String(format: "%04d%02d%02d",
                                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
