import WidgetKit
import SwiftUI

/// 오늘의 장 스트릭 위젯 — 리텐션 루프를 홈 화면으로.
/// 앱이 App Group에 써둔 값을 읽기만 한다 (streak · lastDoneStamp · week).
/// 탭하면 seed://daily 딥링크로 오늘의 장에 바로 진입.

struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let doneToday: Bool
    let week: [Bool]
}

struct StreakProvider: TimelineProvider {
    private let suite = "group.kr.arcseed.SEED"

    private func dayStamp(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 2_026) * 10_000 + (parts.month ?? 1) * 100 + (parts.day ?? 1)
    }

    private func currentEntry(at date: Date) -> StreakEntry {
        // 완료 날짜 도장 원본에서 렌더 시점 날짜로 전부 재계산 — 앱이 마지막으로
        // 열린 날 기준의 낡은 스트릭·주간 점이 남지 않는다 (앱의 DailyMarket과 동일 규칙).
        let defaults = UserDefaults(suiteName: suite)
        let stamps = Set((defaults?.array(forKey: "seed.widget.doneStamps") as? [Int]) ?? [])
        let calendar = Calendar.current
        let doneToday = stamps.contains(dayStamp(date))

        // 스트릭: 오늘 미완료면 어제부터 센다 (자정에 끊기지 않는다)
        var cursor = date
        if !doneToday {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var streak = 0
        while stamps.contains(dayStamp(cursor)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        let week = (0..<7).reversed().map { offset -> Bool in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { return false }
            return stamps.contains(dayStamp(day))
        }
        return StreakEntry(date: date, streak: streak, doneToday: doneToday, week: week)
    }

    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: .now, streak: 3, doneToday: false,
                    week: [true, true, false, true, true, true, false])
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let now = Date.now
        // 자정 직후 엔트리를 하나 더 — 날짜가 바뀌면 '오늘 완료'가 저절로 풀린다
        let midnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now)
        let timeline = Timeline(
            entries: [currentEntry(at: now), currentEntry(at: midnight.addingTimeInterval(60))],
            policy: .after(midnight.addingTimeInterval(120))
        )
        completion(timeline)
    }
}

struct DailyStreakWidgetView: View {
    var entry: StreakEntry
    @Environment(\.widgetFamily) private var family

    private let violet = Color(red: 0x6B / 255, green: 0x4E / 255, blue: 0xFF / 255)

    var body: some View {
        content
            .containerBackground(for: .widget) { Color(.systemBackground) }
            .widgetURL(URL(string: "seed://daily"))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium: medium
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    // MARK: 잠금화면

    /// 원형: 완료 체크 또는 연속 일수 — 한 글자 정보
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.doneToday {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
            } else if entry.streak >= 2 {
                VStack(spacing: 0) {
                    Text("🔥").font(.system(size: 14))
                    Text("\(entry.streak)일")
                        .font(.system(size: 11, weight: .bold))
                }
            } else {
                Image(systemName: "sunrise.fill")
                    .font(.system(size: 18))
            }
        }
    }

    /// 직사각형: 상태 + 스트릭 한 줄
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: entry.doneToday ? "checkmark.circle.fill" : "sunrise.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("오늘의 장")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(entry.doneToday ? "오늘 완료" : "오늘 판이 열렸어요")
                .font(.system(size: 11))
            if entry.streak >= 2 {
                Text("🔥 \(entry.streak)일 연속")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: entry.doneToday ? "checkmark.circle.fill" : "sunrise.fill")
                .font(.system(size: 22))
                .foregroundStyle(entry.doneToday ? .green : violet)
            Spacer(minLength: 0)
            Text("오늘의 장")
                .font(.system(size: 14, weight: .semibold))
            Text(entry.doneToday ? "오늘 완료!" : "오늘 판이 열렸어요")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if entry.streak >= 2 {
                Text("🔥 \(entry.streak)일 연속")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(violet)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: entry.doneToday ? "checkmark.circle.fill" : "sunrise.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(entry.doneToday ? .green : violet)
                Text("오늘의 장")
                    .font(.system(size: 15, weight: .semibold))
                Text(entry.doneToday ? "오늘 완료 · 내일 또 열려요" : "오늘은 어떤 장일까요?")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                if entry.streak >= 2 {
                    Text("🔥 \(entry.streak)일 연속")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(violet)
                }
                HStack(spacing: 4) {
                    ForEach(Array(entry.week.enumerated()), id: \.offset) { _, done in
                        Circle()
                            .fill(done ? violet : Color(.systemGray4))
                            .frame(width: 7, height: 7)
                    }
                }
                Text("최근 7일")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DailyStreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "seed.dailyStreak", provider: StreakProvider()) { entry in
            DailyStreakWidgetView(entry: entry)
        }
        .configurationDisplayName("오늘의 장")
        .description("연속 기록과 오늘의 장 완료 여부를 보여줘요.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular])
    }
}
