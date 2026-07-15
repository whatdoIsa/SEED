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
        // 워커와 공유하는 클라이언트 토큰 — 값은 gitignore된 TutorSecrets.swift에만 존재 (저장소가 public)
        request.setValue(TutorSecrets.clientToken, forHTTPHeaderField: "x-seed-client")
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

// MARK: - 크레딧 영속 저장소 (iCloud Key-Value Store)

/// 튜터 크레딧·지급 기록의 저장소 — iCloud KV.
/// 소모성 리필은 finish 후 StoreKit이 재전달하지 않아(구매 복원 불가) 이 잔액이 유일한 기록이다.
/// UserDefaults에만 두면 재설치·기기 이전 때 유료 크레딧이 증발한다 ("영구 크레딧" 카피 위반).
/// iCloud 미로그인 기기에서도 로컬 디스크에 저장돼 동작은 유지된다.
enum TutorCloudStore {
    private static let cloud = NSUbiquitousKeyValueStore.default
    private static let migratedFlag = "seed.tutor.cloudMigrated"
    static let grantedKey = "seed.iap.granted"

    /// 앱 시작 시 1회: 원격 값 당겨오기 + 구버전 UserDefaults 값 병합 (기기당 1회).
    static func bootstrap() {
        cloud.synchronize()
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedFlag) else { return }
        defaults.set(true, forKey: migratedFlag)
        // 로컬 레거시와 클라우드 중 큰 쪽을 남긴다 — 레거시 크레딧 구제 + 이중 반영 방지
        for key in ["seed.tutor.used", "seed.tutor.credits", "seed.pro.creditMonth"] {
            let local = defaults.integer(forKey: key)
            if local > int(forKey: key) { set(local, forKey: key) }
        }
        let localGranted = Set(defaults.stringArray(forKey: grantedKey) ?? [])
        if !localGranted.isEmpty {
            setGranted(granted().union(localGranted))
        }
    }

    static func int(forKey key: String) -> Int { Int(cloud.longLong(forKey: key)) }

    static func set(_ value: Int, forKey key: String) {
        cloud.set(Int64(value), forKey: key)
        cloud.synchronize()
    }

    /// 지급 완료된 소모성 트랜잭션 ID 집합 (중복 지급 방어)
    static func granted() -> Set<String> {
        Set(cloud.array(forKey: grantedKey) as? [String] ?? [])
    }

    static func setGranted(_ ids: Set<String>) {
        cloud.set(Array(ids), forKey: grantedKey)
        cloud.synchronize()
    }
}

// MARK: - 쿼터 (무료 총 5문 + 리필·Pro 크레딧)

enum TutorQuota {
    private static let usedKey = "seed.tutor.used"
    private static let creditsKey = "seed.tutor.credits" // 리필·Pro가 충전

    static let freeTotal = 5

    static var remaining: Int {
        max(0, freeTotal + TutorCloudStore.int(forKey: creditsKey)
            - TutorCloudStore.int(forKey: usedKey))
    }

    static func consume() {
        TutorCloudStore.set(TutorCloudStore.int(forKey: usedKey) + 1, forKey: usedKey)
    }

    static func addCredits(_ amount: Int) {
        TutorCloudStore.set(TutorCloudStore.int(forKey: creditsKey) + amount, forKey: creditsKey)
    }
}
