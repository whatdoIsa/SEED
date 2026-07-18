import SwiftUI
import StoreKit

/// 트랙 단품 페이월 — 트랙 2(ETF·분산투자)부터 쓰는 정직한 구매 시트.
/// 원칙: 강매 없음, 단품과 Pro의 차이 명확, 무료로 남는 것 명시.
struct TrackPaywallSheet: View {
    let purchases: PurchaseStore
    var trackTitle = "트랙 2 — ETF·분산투자"
    var trackSubtitle = "레슨 8편 + ETF 시장 (한빛300 지수·균형 자산배분)"
    /// 어디서 열렸는지 — 전환율을 소스별로 나눠 보기 위한 계측 키
    var source = "unknown"
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(trackTitle)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(SeedTheme.textPrimary)
                        Text(trackSubtitle)
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

                // 트랙에 담긴 것
                VStack(alignment: .leading, spacing: 6) {
                    benefitRow("ETF가 뭔지부터 리밸런싱까지 — 레슨 8편")
                    benefitRow("합성 ETF 2종으로 직접 운용 연습")
                    benefitRow("운용보수가 계좌를 갉아먹는 걸 눈으로 확인")
                    benefitRow("적립식 vs 몰빵, 숫자로 비교")
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 13))

                // 단품 (영구 소장)
                VStack(alignment: .leading, spacing: 8) {
                    Text("이 트랙만")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SeedTheme.textSecondary)
                    trackBuyRow
                }

                // Pro (구독)
                VStack(alignment: .leading, spacing: 8) {
                    Text("SEED Pro — 전 트랙 + AI까지")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SeedTheme.textSecondary)
                    VStack(alignment: .leading, spacing: 6) {
                        benefitRow("지금·앞으로의 모든 트랙 포함")
                        benefitRow(AICoach.isAvailable
                            ? "AI 코치 코멘트 (복기·부검·해설)"
                            : "AI 코치 코멘트 — 이 기기는 미지원 (iPhone 15 Pro 이상)")
                        benefitRow("튜터 매달 40문 자동 충전")
                        benefitRow("시즌 아카이브 — 전 시즌 성장 그래프")
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
                    Task {
                        await purchases.restore()
                        if purchases.ownsETFTrack { dismiss() }
                    }
                } label: {
                    Text("구매 복원")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }

                Text("단품은 한 번 사면 영구 소장이에요 (AI 기능 미포함). 트랙 1(12편)·시장·오늘의 장·아레나는 계속 무료입니다.")
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
        .onAppear { Analytics.log(.paywallShown, ["sheet": "track", "source": source]) }
        .task { if purchases.products.isEmpty { await purchases.loadProducts() } }
    }

    private var trackBuyRow: some View {
        let product = purchases.product(PurchaseStore.trackETFID)
        return Button {
            guard let product else { return }
            Task {
                isPurchasing = true
                await purchases.purchase(product)
                isPurchasing = false
                if purchases.ownsETFTrack { dismiss() }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("트랙 2 영구 소장")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    Text("일회성 · 기한 없음 · AI 미포함")
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
                if purchases.ownsETFTrack { dismiss() }
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
