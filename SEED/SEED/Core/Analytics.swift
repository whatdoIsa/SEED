import Foundation

/// KPI 계측 파사드 (M5-2, §13) — 로컬 우선·익명.
/// 이벤트는 Application Support/analytics.jsonl에 줄 단위 JSON으로 쌓인다.
/// 서버 전송은 없다 — 금융 앱 신뢰 원칙. 원격 집계 도입 시에도 이 파사드만 바꾼다.
enum SeedEvent: String {
    case onboardingStart = "onboarding_start"
    case onboardingLevelChoice = "onboarding_level_choice"
    case firstTradeFilled = "first_trade_filled"
    case tradePlaced = "trade_placed"
    case tagSelected = "tag_selected"
    case lessonStart = "lesson_start"
    case lessonComplete = "lesson_complete"
    case toolUnlocked = "tool_unlocked"
    case slippageTutorialCompleted = "slippage_tutorial_completed"
    case reviewReportOpened = "review_report_opened"
    case accountReset = "account_reset"
    case sessionStart = "session_start"
    case dayOpen = "day_open"
    // 수익화 퍼널: 노출 → (졸업 CTA) → 결제. 전환율 = purchase / paywall_shown.
    case paywallShown = "paywall_shown"
    case purchaseCompleted = "purchase_completed"
    case trackPromoTapped = "track_promo_tapped"
    case reviewPrompted = "review_prompted"
}

@MainActor
enum Analytics {

    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("analytics.jsonl")
    }

    /// 로그 파일 상한 — 넘으면 오래된 앞쪽 절반을 버린다 (무한 성장 방지)
    private static let maxLogBytes = 1_000_000

    private static func rotateIfNeeded() {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.size] as? Int,
              size > maxLogBytes,
              let data = try? Data(contentsOf: fileURL) else { return }
        let keep = data.suffix(maxLogBytes / 2)
        // 줄 경계 정렬: 첫 개행 다음부터
        if let newline = keep.firstIndex(of: UInt8(ascii: "\n")) {
            try? keep[keep.index(after: newline)...].write(to: fileURL)
        }
    }

    static func log(_ event: SeedEvent, _ props: [String: String] = [:]) {
        rotateIfNeeded()
        var payload: [String: String] = props
        payload["event"] = event.rawValue
        payload["ts"] = ISO8601DateFormatter().string(from: .now)
        guard let data = try? JSONEncoder().encode(payload),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: fileURL)
        }
    }

    /// 하루 1회 day_open 기록 — D1/D7 리텐션의 원료.
    static func logDayOpenIfNeeded() {
        let defaults = UserDefaults.standard
        let installKey = "seed.installDate"
        let lastOpenKey = "seed.lastDayOpen"

        let install: Date
        if let saved = defaults.object(forKey: installKey) as? Date {
            install = saved
        } else {
            install = .now
            defaults.set(install, forKey: installKey)
        }

        let today = Calendar.current.startOfDay(for: .now)
        if let lastOpen = defaults.object(forKey: lastOpenKey) as? Date,
           Calendar.current.isDate(lastOpen, inSameDayAs: today) {
            return
        }
        defaults.set(today, forKey: lastOpenKey)
        let dayIndex = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: install), to: today).day ?? 0
        log(.dayOpen, ["dayIndex": "\(dayIndex)"])
    }

    /// 디버그용 이벤트 카운트 — KPI 6종이 계산 가능한지 확인하는 창.
    static func eventCounts() -> [(event: String, count: Int)] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        var counts: [String: Int] = [:]
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let payload = try? JSONDecoder().decode([String: String].self, from: data),
                  let event = payload["event"] else { continue }
            counts[event, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}
