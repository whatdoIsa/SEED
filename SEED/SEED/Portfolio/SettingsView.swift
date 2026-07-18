import SwiftUI
import StoreKit
import UserNotifications

/// 설정·정보 — 알림 상태, 구독·지원, 데이터 초기화, 교육 고지 전문, 버전.
struct SettingsView: View {
    @Bindable var session: MarketSession
    let store: SeedStore
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var morningOn = SeedNotifications.isEnabled(.morning)
    @State private var eveningOn = SeedNotifications.isEnabled(.evening)
    @State private var weeklyOn = SeedNotifications.isEnabled(.weekly)
    @State private var confirmsErase = false
    @State private var showsManageSubscriptions = false
    @State private var isRestoring = false
    @State private var restoreDone = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    aiSection
                    notificationSection
                    supportSection
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
                    SheetCloseButton { dismiss() }
                        .foregroundStyle(SeedTheme.violet)
                }
            }
        }
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
        .task {
            notificationStatus = await UNUserNotificationCenter.current()
                .notificationSettings().authorizationStatus
        }
    }

    // MARK: 구독·지원 — 구독 앱의 기본 3종 + 법적 고지

    private var supportSection: some View {
        section("구독·지원") {
            VStack(spacing: 0) {
                supportRow("구독 관리", icon: "creditcard") {
                    showsManageSubscriptions = true
                }
                Divider().padding(.vertical, 9)
                supportRow(restoreDone ? "구매 복원 완료" : "구매 복원",
                           icon: restoreDone ? "checkmark.circle.fill" : "arrow.clockwise") {
                    guard !isRestoring else { return }
                    Task {
                        isRestoring = true
                        await purchases.restore()
                        isRestoring = false
                        restoreDone = true
                    }
                }
                Divider().padding(.vertical, 9)
                supportRow("문의하기", icon: "envelope") {
                    if let url = SeedLinks.supportMailURL {
                        UIApplication.shared.open(url)
                    }
                }
                Divider().padding(.vertical, 9)
                supportRow("이용약관", icon: "doc.text") {
                    UIApplication.shared.open(SeedLinks.terms)
                }
                Divider().padding(.vertical, 9)
                supportRow("개인정보처리방침", icon: "hand.raised") {
                    UIApplication.shared.open(SeedLinks.privacyPolicy)
                }
            }
        }
    }

    private func supportRow(_ title: String, icon: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SeedTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: AI 코치

    private var aiSection: some View {
        section("AI 코치") {
            VStack(alignment: .leading, spacing: 8) {
                infoRow("SEED Pro", purchases.isPro ? "구독 중" : "미구독")
                infoRow("튜터 남은 질문", "\(TutorQuota.remaining)문")
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
            VStack(spacing: 0) {
                if notificationStatus == .denied {
                    HStack {
                        Text("알림이 꺼져 있어요 — 설정 앱에서 켤 수 있어요")
                            .font(.system(size: 13))
                            .foregroundStyle(SeedTheme.textSecondary)
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
                } else {
                    notifToggle("아침 루틴", "매일 08:00 · 복습 1문제 + 오늘의 장",
                                kind: .morning, isOn: $morningOn)
                    Divider().padding(.vertical, 9)
                    notifToggle("저녁 리마인더", "매일 20:00 · 오늘의 장을 안 했을 때만",
                                kind: .evening, isOn: $eveningOn)
                    Divider().padding(.vertical, 9)
                    notifToggle("주간 복기", "일요일 19:00 · 한 주 매매 정리",
                                kind: .weekly, isOn: $weeklyOn)
                    if notificationStatus == .notDetermined {
                        Divider().padding(.vertical, 9)
                        Text("첫 매매를 하면 알림 허용 여부를 물어볼게요.")
                            .font(.system(size: 11))
                            .foregroundStyle(SeedTheme.textSecondary.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func notifToggle(_ title: String, _ subtitle: String,
                             kind: SeedNotifications.Kind,
                             isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
        }
        .tint(SeedTheme.violet)
        .onChange(of: isOn.wrappedValue) { _, on in
            SeedNotifications.setEnabled(kind, on,
                weeklyTradeCount: store.weeklyTradeCount(),
                dailyDoneToday: store.isLessonDone(DailyMarket.id()))
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
