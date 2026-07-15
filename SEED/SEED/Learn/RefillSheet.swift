import SwiftUI
import StoreKit

/// 튜터 리필·Pro 안내 시트 — 체험 소진 시 열리는 정직한 페이월.
/// 원칙: 강매 없음, 가격·내용 명확, 무료로 남는 것도 명시.
struct RefillSheet: View {
    let purchases: PurchaseStore
    var title = "튜터와 계속 대화하기"
    var subtitle = "용어 정의와 추천 질문 거절은 언제나 무료예요."
    /// 어디서 열렸는지 — 전환율을 소스별로 나눠 보기 위한 계측 키
    var source = "tutor_quota"
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(SeedTheme.textPrimary)
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(SeedTheme.textSecondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SeedTheme.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(SeedTheme.card, in: Circle())
                    }
                }

                // 리필 (소모성 — 영구 크레딧)
                VStack(alignment: .leading, spacing: 8) {
                    Text("질문 리필")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SeedTheme.textSecondary)
                    refillRow(id: PurchaseStore.refill10ID,
                              title: "10문 리필", subtitle: "기한 없이 사용")
                    refillRow(id: PurchaseStore.refill30ID,
                              title: "30문 리필", subtitle: "기한 없이 사용 · 문당 더 저렴")
                }

                // Pro (구독)
                VStack(alignment: .leading, spacing: 8) {
                    Text("SEED Pro — 매달 40문 + 앞으로의 전부")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SeedTheme.textSecondary)
                    VStack(alignment: .leading, spacing: 6) {
                        benefitRow("튜터 매달 40문 자동 충전")
                        benefitRow(AICoach.isAvailable
                            ? "AI 코치 코멘트 (복기·부검·해설)"
                            : "AI 코치 코멘트 — 이 기기는 미지원 (iPhone 15 Pro 이상)")
                        benefitRow("시즌 아카이브 — 전 시즌 성장 그래프")
                        benefitRow("모든 학습 트랙 포함 (트랙 2 ETF·분산투자, 크립토 예정)")
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SeedTheme.violetTint.opacity(0.6),
                                in: RoundedRectangle(cornerRadius: 13))

                    HStack(spacing: 8) {
                        proButton(id: PurchaseStore.proMonthlyID, label: "월간")
                        proButton(id: PurchaseStore.proYearlyID,
                                  label: "연간" + (purchases.yearlyDiscountPct.map { " · \($0)% 할인" } ?? ""))
                    }
                }

                Button {
                    Task { await purchases.restore() }
                } label: {
                    Text("구매 복원")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }

                Text("구독은 언제든 App Store 설정에서 해지할 수 있어요. 트랙 1(12편)·시장·오늘의 장·아레나는 계속 무료입니다.")
                    .font(.system(size: 10))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.7))
                    .lineSpacing(4)

                LegalLinkFooter()

                #if DEBUG
                if let loadError = purchases.lastLoadError {
                    Text("DEBUG · \(loadError)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SeedTheme.down)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SeedTheme.downTint, in: RoundedRectangle(cornerRadius: 10))
                }
                #endif
            }
            .padding(20)
        }
        .background(SeedTheme.background)
        .presentationDetents([.large])
        .onAppear { Analytics.log(.paywallShown, ["sheet": "refill", "source": source]) }
        .task { if purchases.products.isEmpty { await purchases.loadProducts() } }
    }

    private func refillRow(id: String, title: String, subtitle: String) -> some View {
        let product = purchases.product(id)
        return Button {
            guard let product else { return }
            Task {
                isPurchasing = true
                await purchases.purchase(product)
                isPurchasing = false
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
                Spacer()
                Text(product?.displayPrice ?? "—")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SeedTheme.violetDeep)
            }
            .padding(14)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .disabled(product == nil || isPurchasing)
    }

    private func proButton(id: String, label: String) -> some View {
        let product = purchases.product(id)
        return Button {
            guard let product else { return }
            Task {
                isPurchasing = true
                await purchases.purchase(product)
                isPurchasing = false
            }
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                Text(product?.displayPrice ?? "—")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 13))
        }
        .disabled(product == nil || isPurchasing)
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(SeedTheme.violet)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.textPrimary)
        }
    }
}
