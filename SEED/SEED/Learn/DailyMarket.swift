import Foundation
import JurinKit

/// 오늘의 장 (⑦, §6.2) — 날짜가 시드가 되는 일일 시나리오.
/// 같은 날이면 모두에게 같은 장이 열리고, 내일은 다른 장이 열린다.
/// 무료 일일 콘텐츠이자, 이후 수익화의 "일일 제한" 경계가 되는 지점(§12.1).
enum DailyMarket {

    enum Pattern: Int, CaseIterable {
        case rallyAndFade = 0
        case crashAndRecover = 1
        case sideways = 2
        case steadyTrend = 3
        case deadCat = 4

        /// 이름은 장이 끝난 뒤에만 공개한다 — 미리 알면 연습이 아니다.
        var revealName: String {
            switch self {
            case .rallyAndFade: return "급등 후 되돌림"
            case .crashAndRecover: return "급락 후 회복 시도"
            case .sideways: return "지루한 횡보"
            case .steadyTrend: return "꾸준한 추세"
            case .deadCat: return "데드캣 바운스"
            }
        }

        var lessonLine: String {
            switch self {
            case .rallyAndFade: return "고점 추격은 오늘도 아팠을 거예요. 되돌림은 급등의 그림자예요."
            case .crashAndRecover: return "급락에서 판 사람과 주운 사람의 하루가 갈렸어요."
            case .sideways: return "아무 일도 없는 날, 지루함에 매매하지 않았나요?"
            case .steadyTrend: return "추세를 타면 조용히 벌어요. 자주 내리면 수수료와 실수만 늘어요."
            case .deadCat: return "떨어진 게 반등한다고 바닥은 아니에요. 반짝 반등에 속지 않았나요?"
            }
        }
    }

    static func dayStamp(_ date: Date = .now) -> Int {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 2_026) * 10_000 + (parts.month ?? 1) * 100 + (parts.day ?? 1)
    }

    static func id(for date: Date = .now) -> String { "daily.\(dayStamp(date))" }

    static func pattern(for date: Date = .now) -> Pattern {
        pattern(stamp: dayStamp(date))
    }

    static func pattern(stamp: Int) -> Pattern {
        var rng = SeededRNG(seed: UInt64(stamp))
        return Pattern(rawValue: rng.int(in: 0...Pattern.allCases.count - 1)) ?? .sideways
    }

    // MARK: 스트릭 (§6.2 리텐션 루프 — "매일 한 판"의 기록)

    /// 연속 완료 일수. 오늘 아직 안 했으면 어제까지의 연속을 센다 (스트릭은 자정에 끊기지 않는다).
    static func streak(completed: Set<String>, today: Date = .now) -> Int {
        let calendar = Calendar.current
        var cursor = today
        // 오늘 미완료면 어제부터 시작 — 아직 오늘 판이 남아있는 것뿐
        if !completed.contains(id(for: cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while completed.contains(id(for: cursor)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// 최근 7일 완료 여부 (과거 → 오늘 순).
    static func lastSevenDays(completed: Set<String>, today: Date = .now) -> [Bool] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return false }
            return completed.contains(id(for: day))
        }
    }

    /// 완료한 날들의 패턴별 횟수 — 날짜에서 결정론적으로 재계산 (저장 불필요).
    static func patternCounts(completed: Set<String>) -> [(pattern: Pattern, count: Int)] {
        var counts: [Pattern: Int] = [:]
        for lessonId in completed where lessonId.hasPrefix("daily.") {
            guard let stamp = Int(lessonId.dropFirst("daily.".count)) else { continue }
            var rng = SeededRNG(seed: UInt64(stamp))
            let pattern = Pattern(rawValue: rng.int(in: 0...Pattern.allCases.count - 1)) ?? .sideways
            counts[pattern, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    /// 날짜 시드로 프리셋 생성 — 패턴 골격은 같고 크기·타이밍은 매일 다르다.
    static func scenario(for date: Date = .now) -> ScenarioPreset {
        scenario(stamp: dayStamp(date), id: id(for: date))
    }

    /// 임의 스탬프로 생성 (아레나: 무작위 대결장). 같은 스탬프 = 같은 장.
    static func scenario(stamp: Int, id: String) -> ScenarioPreset {
        var rng = SeededRNG(seed: UInt64(stamp))
        let dailyPattern = Pattern(rawValue: rng.int(in: 0...Pattern.allCases.count - 1)) ?? .sideways
        let base = Double(rng.int(in: 24...96) * 1_000)
        let duration = 600

        func jitter(_ range: ClosedRange<Double>) -> Double { rng.double(in: range) }
        var keyframes: [ScenarioPreset.Keyframe] = [.init(tick: 0, value: base)]
        var overrides: [ScenarioPreset.AgentOverride] = []

        switch dailyPattern {
        case .rallyAndFade:
            keyframes += [
                .init(tick: 150, value: base * jitter(0.99...1.01)),
                .init(tick: 240, value: base * jitter(1.12...1.20)),
                .init(tick: 330, value: base * jitter(1.15...1.24)),
                .init(tick: 470, value: base * jitter(0.99...1.05)),
                .init(tick: duration, value: base * jitter(1.00...1.04))
            ]
            overrides = [
                .init(agentId: "TREND", startTick: 150, endTick: 340,
                      params: AgentParams(activity: 0.85, minQty: 50, maxQty: 200)),
                .init(agentId: "VALUE", startTick: 330, endTick: 500,
                      params: AgentParams(activity: 0.8, minQty: 70, maxQty: 240))
            ]
        case .crashAndRecover:
            keyframes += [
                .init(tick: 130, value: base * jitter(0.99...1.01)),
                .init(tick: 200, value: base * jitter(0.80...0.88)),
                .init(tick: 320, value: base * jitter(0.82...0.90)),
                .init(tick: 480, value: base * jitter(0.90...0.98)),
                .init(tick: duration, value: base * jitter(0.92...1.00))
            ]
            overrides = [
                .init(agentId: "NOISE", startTick: 130, endTick: 260,
                      params: AgentParams(activity: 0.95, minQty: 30, maxQty: 160)),
                .init(agentId: "TREND", startTick: 130, endTick: 300,
                      params: AgentParams(activity: 0.85, minQty: 50, maxQty: 200)),
                .init(agentId: "VALUE", startTick: 250, endTick: 520,
                      params: AgentParams(activity: 0.7, minQty: 60, maxQty: 220))
            ]
        case .sideways:
            keyframes += [
                .init(tick: 150, value: base * jitter(0.985...1.015)),
                .init(tick: 300, value: base * jitter(0.98...1.02)),
                .init(tick: 450, value: base * jitter(0.985...1.015)),
                .init(tick: duration, value: base * jitter(0.99...1.01))
            ]
        case .steadyTrend:
            let up = rng.chance(0.6)
            let end = up ? jitter(1.08...1.16) : jitter(0.86...0.93)
            keyframes += [
                .init(tick: 200, value: base * (1 + (end - 1) * 0.35)),
                .init(tick: 400, value: base * (1 + (end - 1) * 0.7)),
                .init(tick: duration, value: base * end)
            ]
            overrides = [
                .init(agentId: "TREND", startTick: 100, endTick: 550,
                      params: AgentParams(activity: 0.6, minQty: 40, maxQty: 150))
            ]
        case .deadCat:
            keyframes += [
                .init(tick: 130, value: base * jitter(0.99...1.01)),
                .init(tick: 190, value: base * jitter(0.84...0.90)),   // 1차 급락
                .init(tick: 260, value: base * jitter(0.92...0.97)),   // 반짝 반등
                .init(tick: 400, value: base * jitter(0.76...0.83)),   // 재하락 (진짜)
                .init(tick: duration, value: base * jitter(0.80...0.86))
            ]
            overrides = [
                .init(agentId: "TREND", startTick: 130, endTick: 460,
                      params: AgentParams(activity: 0.85, minQty: 50, maxQty: 200)),
                .init(agentId: "NOISE", startTick: 130, endTick: 460,
                      params: AgentParams(activity: 0.92, minQty: 25, maxQty: 150))
            ]
        }

        return ScenarioPreset(
            id: id,
            seed: UInt64(stamp) &* 0x9E37_79B9,
            initialPrice: Int(base),
            durationTicks: duration,
            anchorPull: 0.12,
            keyframes: keyframes,
            overrides: overrides,
            timeScaleLabel: "1캔들 = 1일"
        )
    }
}
