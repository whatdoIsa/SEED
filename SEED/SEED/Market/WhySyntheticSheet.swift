import SwiftUI

/// 첫 매매 직후 1회: "왜 실제 종목이 없나요?" — 가상 시장의 이유를 설득하는 카드.
/// 경쟁 앱은 전부 실시세인데 SEED만 합성 시장 — 이 차이가 약점으로 읽히기 전에,
/// 궁금증이 실제로 생기는 순간(첫 체결 직후)에 먼저 답한다.
struct WhySyntheticSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(SeedTheme.band).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            Text("왜 실제 종목이 없나요?")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
                .padding(.top, 18)
            Text("첫 매매를 하셨으니, 이 시장의 정체를 말씀드릴게요.")
                .font(.system(size: 14))
                .foregroundStyle(SeedTheme.textSecondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 12) {
                ruleRow(icon: "gearshape.2.fill", title: "여긴 설계된 시장이에요",
                        detail: "종목·가격·뉴스 전부 학습용으로 만들어진 가상 데이터예요. 실존 기업과 무관해요.")
                ruleRow(icon: "dice.fill", title: "실제 시세엔 함정이 있어요",
                        detail: "실시세 모의투자는 우연히 번 수익을 실력으로 착각하게 해요. 상승장에 시작하면 누구나 천재가 되죠.")
                ruleRow(icon: "arrow.triangle.2.circlepath", title: "여기선 천 번 망해도 돼요",
                        detail: "폭락·급등·지루한 횡보를 의도적으로 반복해서 겪어요. 오늘의 장에선 매일 다른 패턴이 나와요.")
            }
            .padding(.top, 16)

            HStack(spacing: 8) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(SeedTheme.violet)
                Text("SEED는 체육관이에요. 습관은 여기서 만들고, 시합(실전)은 준비된 뒤에 나가세요.")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .lineSpacing(4)
            }
            .padding(13)
            .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 16)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("좋아요, 마음껏 망해볼게요")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 14))
            }
            Text("교육용 모의투자 · 실제 투자 권유가 아닙니다")
                .font(.system(size: 10))
                .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 20)
        .presentationBackground(SeedTheme.background)
    }

    private func ruleRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(SeedTheme.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .lineSpacing(3)
            }
        }
    }
}
