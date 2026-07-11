import SwiftUI

/// AI 코치 코멘트 카드 — 온디바이스 생성 결과를 보여준다.
/// 생성 실패·미지원 기기면 아무것도 그리지 않는다 (룰 기반 카피가 폴백).
struct AICoachCard: View {
    let cacheKey: String
    let fingerprint: String
    let prompt: String
    var maxTokens: Int = 250

    @State private var text: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let text {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                        Text("AI 코치")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("기기에서 생성됨")
                            .font(.system(size: 9))
                            .opacity(0.6)
                    }
                    .foregroundStyle(SeedTheme.violetDeep)
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textPrimary)
                        .lineSpacing(5)
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SeedTheme.violetTint.opacity(0.7),
                            in: RoundedRectangle(cornerRadius: 13))
                .transition(.opacity)
            } else if isLoading && AICoach.isAvailable {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("AI 코치가 읽는 중…")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
                .padding(.vertical, 6)
            }
        }
        .animation(.easeOut(duration: 0.3), value: text)
        .task(id: cacheKey + fingerprint) {
            isLoading = true
            text = await AICoach.comment(cacheKey: cacheKey,
                                         dataFingerprint: fingerprint,
                                         prompt: prompt,
                                         maxTokens: maxTokens)
            isLoading = false
        }
    }
}
