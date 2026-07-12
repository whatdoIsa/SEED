import Foundation

/// 외부 링크 모음 — 법적 고지·지원 채널.
/// ⚠️ 아래 URL·이메일은 플레이스홀더: 회사 홈페이지에 문서 게시 후 실제 주소로 교체할 것.
///   문서에 들어가야 할 내용 요약은 claudedocs/legal-docs-요약.md 참고.
enum SeedLinks {
    /// 개인정보처리방침 — App Store 메타데이터에도 같은 URL 입력
    static let privacyPolicy = URL(string: "https://arcseed.kr/seed/privacy")!
    /// 이용약관 (EULA) — 구독 페이월 필수 링크
    static let terms = URL(string: "https://arcseed.kr/seed/terms")!
    /// 문의 이메일 — App Store 지원 URL의 대안 채널
    static let supportEmail = "seed@arcseed.kr"

    static var supportMailURL: URL? {
        URL(string: "mailto:\(supportEmail)?subject=SEED%20문의")
    }
}
