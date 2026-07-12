import SwiftUI

/// 페이월 하단 법적 링크 — 자동갱신 구독 심사 필수 요소 (가이드라인 3.1.2).
struct LegalLinkFooter: View {
    var body: some View {
        HStack(spacing: 10) {
            Link("이용약관", destination: SeedLinks.terms)
            Text("·")
            Link("개인정보처리방침", destination: SeedLinks.privacyPolicy)
        }
        .font(.system(size: 11))
        .foregroundStyle(SeedTheme.textSecondary.opacity(0.8))
        .frame(maxWidth: .infinity)
    }
}
