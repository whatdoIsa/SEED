import Foundation

/// 외부 링크 모음 — 법적 고지·지원 채널 (arcseed.kr 게시 확인 완료, 2026.7).
enum SeedLinks {
    /// 개인정보처리방침 — App Store Connect 앱 정보에도 같은 URL 입력
    static let privacyPolicy = URL(string: "https://www.arcseed.kr/ko/privacy")!
    /// 이용약관 (EULA) — 구독 페이월 필수 링크
    static let terms = URL(string: "https://www.arcseed.kr/ko/terms")!
    /// 앱 소개 페이지 — App Store 지원 URL용
    static let homepage = URL(string: "https://www.arcseed.kr/seed")!
    /// 문의 이메일 — 홈페이지 방침 문서에 명시된 주소와 일치
    static let supportEmail = "contact@arcseed.kr"

    static var supportMailURL: URL? {
        URL(string: "mailto:\(supportEmail)?subject=SEED%20문의")
    }
}
