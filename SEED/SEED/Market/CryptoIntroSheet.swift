import SwiftUI

/// 크립토 첫 진입 교육 카드 (§16.4·§16.5) — 제도 차이와 색 규칙을 한 번에.
/// 온체인 지표(MVRV 등)는 실데이터가 필요해 합성 모드에는 없다 — 여기선 개념·리스크가 먼저다.
struct CryptoIntroSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(SeedTheme.band).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            Text("여긴 다른 세계예요")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
                .padding(.top, 18)
            Text("같은 차트, 같은 호가창 — 하지만 규칙이 다릅니다.")
                .font(.system(size: 14))
                .foregroundStyle(SeedTheme.textSecondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 12) {
                ruleRow(icon: "clock.fill", title: "장이 닫히지 않아요",
                        detail: "24시간 내내 돕니다. 자는 동안에도 가격이 움직여요.")
                ruleRow(icon: "arrow.up.and.down", title: "상·하한가가 없어요",
                        detail: "하루 ±30% 안전벨트가 없습니다. 얼마든지 더 갈 수 있어요.")
                ruleRow(icon: "waveform.path.ecg", title: "변동성이 훨씬 커요",
                        detail: "주식의 조정이 여기선 평범한 하루일 수 있어요.")
            }
            .padding(.top, 16)

            HStack(spacing: 8) {
                Image(systemName: "paintpalette.fill")
                    .foregroundStyle(SeedTheme.violet)
                Text("SEED는 여기서도 **상승 = 빨강**이에요. 다만 글로벌 거래소는 반대(상승 = 초록)인 곳이 많으니, 실제 거래소에선 색부터 확인하세요.")
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
                Text("알겠어요")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 14))
            }
            Text("모의·교육용 합성 시장 · 투자 신호가 아닙니다")
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
