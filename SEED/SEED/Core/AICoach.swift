import Foundation
import FoundationModels

/// 온디바이스 AI 코치 — 복기·해설 코멘트를 기기 안에서 생성한다.
/// 서버 없음, 비용 없음, 데이터가 기기를 떠나지 않는다.
///
/// 정책 (§AI 호출 기준):
/// - 같은 데이터에 두 번 묻지 않는다 — 키+데이터 해시 캐시
/// - 출력 토큰 상한 강제
/// - 미지원 기기·생성 실패 시 nil → 화면은 룰 기반 카피로 폴백
enum AICoach {

    /// 코치 공통 인격 — §11 준수가 인격에 박혀 있다.
    private static let instructions = """
    당신은 주식 초보를 위한 모의투자 학습 앱 'SEED'의 코치입니다.

    말투: 따뜻하지만 정직한 한국어 존댓말. 두세 문장, 짧고 구체적으로.
    반드시 지킬 것:
    - 실제 종목 추천, 가격 예측, 수익 보장 발언 금지
    - 사용자의 데이터에 있는 사실만 말하고, 없는 것을 지어내지 않기
    - 잘한 것은 인정하되 과장하지 않고, 나쁜 습관은 데이터를 근거로 짚기
    - 이 시장은 학습용 가상 시장임을 전제로 말하기
    """

    /// 온디바이스 모델 사용 가능 여부 (Apple Intelligence 기기 + 활성화)
    static var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        return false
    }

    /// 코멘트 생성 — 캐시 우선, 실패 시 nil (호출부는 룰 기반 폴백 유지).
    /// - Parameters:
    ///   - cacheKey: 정책 키 (예: "daily.20260711", "weekly.2026-28", "autopsy.3")
    ///   - dataFingerprint: 입력 데이터 해시 — 같으면 재생성하지 않는다
    ///   - prompt: 앱이 미리 계산한 요약 (원시 데이터 금지 — 토큰 다이어트)
    static func comment(cacheKey: String,
                        dataFingerprint: String,
                        prompt: String,
                        maxTokens: Int = 250) async -> String? {
        // 1. 캐시 — 같은 데이터에 두 번 묻지 않는다
        if let cached = AICommentCache.load(key: cacheKey, fingerprint: dataFingerprint) {
            return cached
        }
        // 2. 생성
        guard isAvailable else { return nil }
        guard #available(iOS 26.0, *) else { return nil }
        do {
            let session = LanguageModelSession(instructions: instructions)
            var options = GenerationOptions()
            options.maximumResponseTokens = maxTokens
            let response = try await session.respond(to: prompt, options: options)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            AICommentCache.save(key: cacheKey, fingerprint: dataFingerprint, text: text)
            AIUsageMeter.increment()
            return text
        } catch {
            return nil
        }
    }
}

// MARK: - 코멘트 캐시 (키 + 데이터 지문)

enum AICommentCache {
    private static let keyPrefix = "seed.ai.cache."
    private static func defaultsKey(_ key: String) -> String { keyPrefix + key }
    /// 날짜 키(daily.*)가 무한히 쌓이지 않도록 오래된 항목은 버린다
    private static let retention: TimeInterval = 45 * 86_400

    struct Entry: Codable {
        let fingerprint: String
        let text: String
        var savedAt: Date? = nil
    }

    static func load(key: String, fingerprint: String) -> String? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey(key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.fingerprint == fingerprint else { return nil }
        return entry.text
    }

    static func save(key: String, fingerprint: String, text: String) {
        let entry = Entry(fingerprint: fingerprint, text: text, savedAt: .now)
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: defaultsKey(key))
        }
        pruneStale()
    }

    /// 보존 기간이 지난(또는 저장 시각이 없는 구버전) 캐시 제거
    private static func pruneStale() {
        let defaults = UserDefaults.standard
        let cutoff = Date.now.addingTimeInterval(-retention)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            guard let data = defaults.data(forKey: key),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data),
                  let savedAt = entry.savedAt, savedAt > cutoff else {
                defaults.removeObject(forKey: key)
                continue
            }
        }
    }
}

// MARK: - 사용량 계측 (투명성 — 설정 화면 노출용)

enum AIUsageMeter {
    private static let countKey = "seed.ai.usage.count"
    private static let monthKey = "seed.ai.usage.month"

    private static var currentMonth: Int {
        let parts = Calendar.current.dateComponents([.year, .month], from: .now)
        return (parts.year ?? 0) * 100 + (parts.month ?? 0)
    }

    static func increment() {
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: monthKey) != currentMonth {
            defaults.set(currentMonth, forKey: monthKey)
            defaults.set(0, forKey: countKey)
        }
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
    }

    static var thisMonth: Int {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: monthKey) == currentMonth else { return 0 }
        return defaults.integer(forKey: countKey)
    }
}
