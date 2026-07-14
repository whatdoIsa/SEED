import SwiftUI

/// AI 코치 코멘트 카드 — 온디바이스 생성 결과를 보여준다.
///
/// 게이트 정책:
/// - Pro: 모든 화면에서 생성 (기존 동작)
/// - 비Pro + offersTrial(주간 복기): 첫 1회 무료 체험 → 이후 잠금 티저 (지난 코멘트 인용)
/// - 비Pro + 그 외 화면: 아무것도 그리지 않음 (룰 기반 카피가 폴백)
/// - 캐시된 코멘트는 구독 여부와 무관하게 보여준다 — 체험한 그 주 내내 유지
/// - 미지원 기기: 항상 숨김
struct AICoachCard: View {
    let cacheKey: String
    let fingerprint: String
    let prompt: String
    var maxTokens: Int = 250
    /// 주간 복기에서만 true — 체험·티저 UI 제공
    var offersTrial = false

    @Environment(PurchaseStore.self) private var purchases
    @State private var text: String?
    @State private var isLoading = true
    @State private var isGeneratingTrial = false
    @State private var showsPaywall = false

    private static let trialUsedKey = "seed.ai.trial.used"
    private static let trialSnippetKey = "seed.ai.trial.snippet"

    var body: some View {
        Group {
            if let text {
                commentCard(text)
            } else if isLoading && purchases.isPro && AICoach.isAvailable {
                loadingRow
            } else if !isLoading, offersTrial, AICoach.isAvailable, !purchases.isPro {
                if UserDefaults.standard.bool(forKey: Self.trialUsedKey) {
                    lockedTeaserCard
                } else {
                    trialOfferCard
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: text)
        .sheet(isPresented: $showsPaywall) {
            RefillSheet(purchases: purchases,
                        title: "AI 코치와 매주 복기하기",
                        subtitle: "주간 복기·부검·오늘의 장 해설 — 전부 기기 안에서 생성돼요.",
                        source: "ai_teaser")
        }
        .task(id: cacheKey + fingerprint) {
            isLoading = true
            // 캐시는 구독 여부와 무관 — 체험으로 받은 그 주의 코멘트도 계속 보인다
            if let cached = AICommentCache.load(key: cacheKey, fingerprint: fingerprint) {
                text = cached
            } else if purchases.isPro {
                text = await AICoach.comment(cacheKey: cacheKey,
                                             dataFingerprint: fingerprint,
                                             prompt: prompt,
                                             maxTokens: maxTokens)
            }
            isLoading = false
        }
    }

    // MARK: 코멘트 (Pro·체험 공통)

    private func commentCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text("AI 코치")
                    .font(.system(size: 11, weight: .semibold))
                if !purchases.isPro {
                    Text("무료 체험")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(SeedTheme.violet.opacity(0.18), in: Capsule())
                }
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
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("AI 코치가 읽는 중…")
                .font(.system(size: 12))
                .foregroundStyle(SeedTheme.textSecondary)
        }
        .padding(.vertical, 6)
    }

    // MARK: 체험 제안 — 가치를 먼저 보여주고 판다

    private var trialOfferCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text("AI 코치")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill").font(.system(size: 8))
                    Text("Pro").font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(SeedTheme.textSecondary)
            }
            .foregroundStyle(SeedTheme.violetDeep)
            Text("이번 주 매매를 읽고, 다음 주에 고칠 습관 하나를 짚어드려요.")
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.textPrimary)
                .lineSpacing(4)
            Button {
                generateTrial()
            } label: {
                HStack(spacing: 6) {
                    if isGeneratingTrial {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Text(isGeneratingTrial ? "읽는 중…" : "첫 1회 무료로 받기")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isGeneratingTrial)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeedTheme.violetTint.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .stroke(SeedTheme.violet.opacity(0.4), lineWidth: 1))
    }

    private func generateTrial() {
        Task {
            isGeneratingTrial = true
            if let result = await AICoach.comment(cacheKey: cacheKey,
                                                  dataFingerprint: fingerprint,
                                                  prompt: prompt,
                                                  maxTokens: maxTokens) {
                text = result
                UserDefaults.standard.set(true, forKey: Self.trialUsedKey)
                UserDefaults.standard.set(String(result.prefix(36)), forKey: Self.trialSnippetKey)
                Analytics.log(.aiTrialUsed)
            }
            isGeneratingTrial = false
        }
    }

    // MARK: 잠금 티저 — 본인이 받았던 코멘트를 기억시킨다

    private var lockedTeaserCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SeedTheme.textSecondary)
                Text("AI 코치")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SeedTheme.textSecondary)
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill").font(.system(size: 8))
                    Text("Pro").font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(SeedTheme.textSecondary)
            }
            if let snippet = UserDefaults.standard.string(forKey: Self.trialSnippetKey) {
                Text("지난번 코멘트 — “\(snippet)…”")
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(SeedTheme.textSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Text("이번 주 매매도 읽어드릴게요")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textPrimary)
                Spacer()
                Button {
                    showsPaywall = true
                } label: {
                    Text("Pro 알아보기")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 13))
    }
}
