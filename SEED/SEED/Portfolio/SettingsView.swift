import SwiftUI
import UserNotifications

/// 설정·정보 — 알림 상태, 데이터 초기화, 교육 고지 전문, 버전.
struct SettingsView: View {
    @Bindable var session: MarketSession
    let store: SeedStore
    @Environment(\.dismiss) private var dismiss

    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var confirmsErase = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    aiSection
                    notificationSection
                    dataSection
                    disclosureSection
                    aboutSection
                }
                .padding(16)
            }
            .background(SeedTheme.background)
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(SeedTheme.violet)
                }
            }
        }
        .task {
            notificationStatus = await UNUserNotificationCenter.current()
                .notificationSettings().authorizationStatus
        }
    }

    // MARK: AI 코치

    private var aiSection: some View {
        section("AI 코치") {
            VStack(alignment: .leading, spacing: 8) {
                infoRow("처리 방식", AICoach.isAvailable ? "이 기기 안에서 생성" : "이 기기에선 미지원")
                infoRow("이번 달 생성", "\(AIUsageMeter.thisMonth)회")
                Text(AICoach.isAvailable
                     ? "복기·해설 코멘트는 Apple Intelligence로 기기 안에서 만들어져요. 데이터가 기기를 떠나지 않아요."
                     : "AI 코치는 Apple Intelligence 지원 기기(iPhone 15 Pro 이상)에서 동작해요. 이 기기에선 기본 코멘트가 제공돼요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .lineSpacing(4)
            }
        }
    }

    // MARK: 알림

    private var notificationSection: some View {
        section("알림") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("주간 복기 알림")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SeedTheme.textPrimary)
                    Text(notificationText)
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
                Spacer()
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("설정 앱")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SeedTheme.violet)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(SeedTheme.violetTint, in: Capsule())
                }
            }
        }
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized: return "켜짐 · 매주 일요일 저녁 7시"
        case .denied: return "꺼짐 · 설정 앱에서 켤 수 있어요"
        case .notDetermined: return "첫 매매를 하면 물어볼게요"
        default: return "확인 중…"
        }
    }

    // MARK: 데이터

    private var dataSection: some View {
        section("데이터") {
            VStack(alignment: .leading, spacing: 10) {
                Text("매매 기록·시즌·레슨 진행은 이 기기와 내 iCloud(개인 저장소)에만 저장돼요. 개발자 서버로는 아무것도 보내지 않아요.")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .lineSpacing(4)
                Button(role: .destructive) {
                    confirmsErase = true
                } label: {
                    Text("모든 데이터 초기화")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(SeedTheme.down.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 11))
                }
                .confirmationDialog(
                    "정말 모두 지울까요?",
                    isPresented: $confirmsErase,
                    titleVisibility: .visible
                ) {
                    Button("모든 기록 삭제 (되돌릴 수 없음)", role: .destructive) {
                        store.eraseAll()
                        session.resetForNewSeason()
                        dismiss()
                    }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text("매매 기록, 시즌, 레슨 진행이 모두 사라지고 처음부터 다시 시작해요.")
                }
            }
        }
    }

    // MARK: 고지 전문

    private var disclosureSection: some View {
        section("꼭 알아두세요") {
            Text("""
            SEED의 시장은 실제 시장 데이터가 아니라 앱 안에서 만들어진 가상 시장이에요. 종목·가격·뉴스·재무 지표는 모두 학습을 위해 합성된 것으로, 실존 기업과 무관해요.

            이 앱은 투자 습관과 시장 언어를 연습하는 교육 도구예요. 특정 종목 추천이나 수익 보장을 하지 않으며, 여기서의 성적이 실제 투자 수익을 의미하지 않아요.

            실제 투자의 판단과 책임은 언제나 본인에게 있어요.
            """)
            .font(.system(size: 13))
            .foregroundStyle(SeedTheme.textSecondary)
            .lineSpacing(5)
        }
    }

    // MARK: 정보

    private var aboutSection: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return section("정보") {
            VStack(spacing: 8) {
                infoRow("버전", "\(version) (\(build))")
                infoRow("데이터 보관", "이 기기 + 내 iCloud")
                infoRow("광고", "없음")
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(SeedTheme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(SeedTheme.textPrimary)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SeedTheme.textSecondary)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
