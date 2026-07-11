import Foundation

/// AI 튜터 — 3겹 구조.
/// ① 규칙 필터: 추천·예측 질문은 모델에 가기 전에 거절 (가드레일의 뼈대는 코드)
/// ② 용어사전 직답: 정확 일치는 0토큰
/// ③ 클라우드(Haiku): 일반 금융 지식 — 프록시 경유 (키는 서버에만)
enum TutorService {

    /// 프록시 주소 — Cloudflare Worker 배포 후 교체 (server/tutor-worker.js 참고).
    /// 비어 있으면 튜터가 '준비 중' 상태로 표시된다.
    static let endpoint = "https://seed-tutor.throbbing-sun-9e1e.workers.dev/"

    static var isConfigured: Bool { !endpoint.isEmpty }

    // MARK: ① 규칙 필터 — 추천·예측 의도

    private static let bannedPatterns = [
        "사야", "살까", "팔까", "팔아야", "추천", "종목 알려", "뭐 사", "뭘 사",
        "오를까", "내릴까", "떨어질까", "얼마까지", "목표가", "가즈아", "몰빵해도"
    ]

    /// 모델 호출 전 거절 판정 (0토큰)
    static func refusal(for question: String) -> String? {
        let compact = question.replacingOccurrences(of: " ", with: "")
        guard bannedPatterns.contains(where: { compact.contains($0.replacingOccurrences(of: " ", with: "")) })
        else { return nil }
        return "저는 지식을 설명하는 튜터라, 무엇을 사고팔지·오를지 내릴지는 답하지 않아요. 대신 그 판단에 필요한 개념이 궁금하면 물어보세요 — 예를 들어 \u{201C}PER이 뭐야?\u{201D} 같은 것들요."
    }

    // MARK: ② 용어사전 직답 (0토큰)

    static func glossaryAnswer(for question: String) -> String? {
        let compact = question.replacingOccurrences(of: " ", with: "").lowercased()
        for section in Glossary.sections {
            for term in section.terms {
                let key = term.term.replacingOccurrences(of: " ", with: "").lowercased()
                // "RSI가 뭐야", "rsi란?" 류의 짧은 정의 질문만 직답
                if compact.contains(key) && compact.count <= key.count + 8 {
                    return term.definition
                }
            }
        }
        return nil
    }

    // MARK: ③ 클라우드 호출

    struct Message: Codable {
        let role: String   // "user" | "assistant"
        let content: String
    }

    private struct RequestBody: Codable {
        let deviceId: String
        let messages: [Message]
    }

    private struct ResponseBody: Codable {
        let text: String?
        let error: String?
    }

    enum TutorError: Error {
        case notConfigured
        case network
        case serverLimit
    }

    /// 최근 3턴만 유지해 토큰을 아낀다.
    static func ask(history: [Message]) async throws -> String {
        guard isConfigured, let url = URL(string: endpoint) else { throw TutorError.notConfigured }
        let trimmed = Array(history.suffix(7)) // user/assistant 3턴 + 새 질문

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(deviceId: deviceIdentifier, messages: trimmed))
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            throw TutorError.serverLimit
        }
        guard let body = try? JSONDecoder().decode(ResponseBody.self, from: data),
              let text = body.text, !text.isEmpty else {
            throw TutorError.network
        }
        return text
    }

    /// 익명 기기 식별자 (서버측 상한용 — 개인정보 아님)
    private static var deviceIdentifier: String {
        let key = "seed.tutor.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }
}

// MARK: - 쿼터 (무료 총 5문 — 리필·Pro는 수익화 단계에서 크레딧 추가)

enum TutorQuota {
    private static let usedKey = "seed.tutor.used"
    private static let creditsKey = "seed.tutor.credits" // 리필·Pro가 충전 (Phase 2)

    static let freeTotal = 5

    static var remaining: Int {
        let defaults = UserDefaults.standard
        return max(0, freeTotal + defaults.integer(forKey: creditsKey)
                   - defaults.integer(forKey: usedKey))
    }

    static func consume() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: usedKey) + 1, forKey: usedKey)
    }

    static func addCredits(_ amount: Int) {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: creditsKey) + amount, forKey: creditsKey)
    }
}
