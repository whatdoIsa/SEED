import SwiftUI

/// 상품 로드 실패 안내 — 무한 스피너 대신 상태를 말하고 재시도 버튼을 준다.
/// 로드 성공·진행 중에는 아무것도 그리지 않으므로 페이월 상단에 상시 배치해도 안전하다.
struct ProductLoadRetryCard: View {
    let purchases: PurchaseStore

    var body: some View {
        if purchases.products.isEmpty && !purchases.isLoading {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.textSecondary)
                    Text("가격을 불러오지 못했어요")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                }
                Text("네트워크 상태를 확인한 뒤 다시 시도해주세요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                Button {
                    Task { await purchases.loadProducts() }
                } label: {
                    Text("다시 시도")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 13))
        }
    }
}
