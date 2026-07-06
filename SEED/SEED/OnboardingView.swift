import SwiftUI

/// 온보딩 (M5-1, 부록 A-2) — 무가입, 안심 메시지, 경험 분기 1문항.
/// 목표: 설치 후 60초 안에 첫 매수 체결 (§7.1).
struct OnboardingView: View {
    let store: SeedStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(SeedTheme.violet).frame(width: 42, height: 42)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(.white)
            }
            .padding(.top, 60)

            Text("1,000만원이\n준비됐어요.")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(SeedTheme.textPrimary)
                .lineSpacing(4)
                .padding(.top, 26)

            Text("진짜 돈은 **1원도** 들지 않아요.\n마음껏 사고, 팔고, 물려보세요.")
                .font(.system(size: 16))
                .foregroundStyle(SeedTheme.textPrimary.opacity(0.75))
                .lineSpacing(5)
                .padding(.top, 12)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 12))
                Text("회원가입 없이 시작 · 모의투자")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(SeedTheme.violetDeep)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(SeedTheme.violetTint, in: Capsule())
            .padding(.top, 18)

            Spacer()

            Text("주식, 얼마나 해보셨어요?")
                .font(.system(size: 14))
                .foregroundStyle(SeedTheme.textSecondary)
                .padding(.bottom, 10)

            choiceButton(
                title: "완전 처음이에요",
                subtitle: "차트부터 하나씩, 도구를 열어가며 배워요",
                primary: true
            ) {
                store.completeOnboarding(startLevel: UnlockLevel.lineOnly)
            }
            choiceButton(
                title: "해본 적 있어요",
                subtitle: "모든 도구를 열고 시작해요",
                primary: false
            ) {
                store.completeOnboarding(startLevel: UnlockLevel.all)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 30)
        .background(Color.white)
    }

    private func choiceButton(title: String, subtitle: String, primary: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(primary ? .white : SeedTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(primary ? .white.opacity(0.75) : SeedTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(primary ? .white.opacity(0.8) : SeedTheme.textSecondary)
            }
            .padding(16)
            .background(
                primary ? SeedTheme.violet : SeedTheme.card,
                in: RoundedRectangle(cornerRadius: 15)
            )
        }
        .buttonStyle(.plain)
    }
}
