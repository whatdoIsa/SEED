import SwiftUI

/// 앱 최상위 — 탭 구조. 배우기·복기 탭은 해당 마일스톤에서 추가된다.
struct RootView: View {
    @Bindable var session: MarketSession
    let store: SeedStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab = 0
    @State private var purchases = PurchaseStore()
    /// 콜드 런치 이음새 — 시스템 런치 화면(로고)과 똑같은 뷰를 첫 프레임에 겹쳐
    /// '로고 → 툭 시장'의 단절 대신 짧은 페이드로 이어준다.
    @State private var showsSplash = true

    var body: some View {
        Group {
            if store.progress.onboardingDone {
                mainTabs
            } else {
                OnboardingView(store: store)
                    .onAppear { Analytics.log(.onboardingStart) }
            }
        }
        .overlay {
            if showsSplash {
                LaunchSplashView {
                    withAnimation(.easeOut(duration: 0.35)) { showsSplash = false }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            Analytics.log(.sessionStart)
            Analytics.logDayOpenIfNeeded()
        }
        .task {
            // 첫 실행(재설치) 직후: CloudKit 임포트가 수 초 뒤 도착하므로 몇 차례 재확인
            for delay in [8, 20, 45] {
                try? await Task.sleep(for: .seconds(delay))
                store.refreshAfterRemoteImport()
                // 복원된 시장 상태가 합류했으면 세션(원장·엔진)을 다시 구성 —
                // 없으면 매매 기록만 보이고 현금은 초기값으로 남는다
                session.adoptRemoteStateIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // 백그라운드 저장 + 복귀 시 경과분 따라잡기 (§9.2 catch-up)
            session.handleScenePhase(active: phase == .active)
            // 알림 갱신은 활성화 시에만 — 서스펜드 순간의 XPC 호출은 크래시를 부른다
            if phase == .active {
                // iCloud 복원분(늦게 도착)을 화면에 합류시키고 중복 레코드를 정리
                store.refreshAfterRemoteImport()
                session.adoptRemoteStateIfNeeded()
                SeedNotifications.rescheduleIfAuthorized(
                    weeklyTradeCount: store.weeklyTradeCount(),
                    dailyDoneToday: store.isLessonDone(DailyMarket.id()))
            }
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            TradingView(session: session, store: store)
                .tabItem { Label("시장", systemImage: "chart.bar.fill") }
                .tag(0)
            LessonListView(store: store)
                .tabItem { Label("배우기", systemImage: "book.fill") }
                .tag(1)
            ReviewReportView(store: store, session: session)
                .tabItem { Label("복기", systemImage: "text.magnifyingglass") }
                .tag(2)
            PortfolioView(session: session, store: store)
                .tabItem { Label("내 주식", systemImage: "briefcase.fill") }
                .tag(3)
        }
        .tint(SeedTheme.textPrimary)
        .environment(purchases)
        .onOpenURL { url in
            // 위젯 딥링크: seed://daily → 배우기 탭 + 오늘의 장
            guard url.scheme == "seed", url.host() == "daily" else { return }
            selectedTab = 1
            // 콜드 런치에서는 배우기 탭 콘텐츠가 아직 생성 전이라 동기 post가 유실된다 —
            // pending 플래그를 함께 남겨 탭의 onAppear가 소비하게 한다 (웜 상태는 post가 즉시 처리)
            DeepLinkRelay.pendingDailyMarket = true
            NotificationCenter.default.post(name: .seedOpenDailyMarket, object: nil)
        }
    }
}

/// 콜드 런치 브랜드 모션 — 시스템 런치 화면(정중앙 아이콘)과 첫 프레임이 동일해
/// 이음새 없이 시작한 뒤: 글로우 블룸 → 아이콘 팝 → 워드마크 → 페이드.
/// §11: 장식용 가짜 차트 곡선은 쓰지 않는다 (ShareCardKit과 같은 원칙).
private struct LaunchSplashView: View {
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glows = false
    @State private var iconScale: CGFloat = 1
    @State private var showsWordmark = false

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            // 씨앗이 틔는 순간의 빛 — 브랜드 바이올렛 블룸
            Circle()
                .fill(SeedTheme.violet.opacity(0.20))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .scaleEffect(glows ? 1.15 : 0.35)
                .opacity(glows ? 1 : 0)
            Image("LaunchIcon")
                .scaleEffect(iconScale)
            VStack(spacing: 7) {
                Text("SEED")
                    .font(.system(size: 25, weight: .heavy))
                    .kerning(5)
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("주식 습관 트레이닝")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            .offset(y: showsWordmark ? 100 : 110)
            .opacity(showsWordmark ? 1 : 0)
        }
        .task {
            if reduceMotion {
                // 모션 최소화 — 정적 로고+워드마크를 잠깐 보여주고 페이드만
                showsWordmark = true
                try? await Task.sleep(for: .milliseconds(700))
                onDone()
                return
            }
            withAnimation(.easeOut(duration: 0.55)) { glows = true }
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.easeOut(duration: 0.18)) { iconScale = 1.07 }
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { iconScale = 1 }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.4)) { showsWordmark = true }
            try? await Task.sleep(for: .milliseconds(750))
            onDone()
        }
    }
}

/// 콜드 런치 딥링크 릴레이 — 알림 구독 전에 도착한 딥링크의 유실 대비
@MainActor
enum DeepLinkRelay {
    static var pendingDailyMarket = false

    static func consumePendingDailyMarket() -> Bool {
        defer { pendingDailyMarket = false }
        return pendingDailyMarket
    }
}

extension Notification.Name {
    /// 위젯 딥링크가 오늘의 장을 열라고 알릴 때
    static let seedOpenDailyMarket = Notification.Name("seed.openDailyMarket")
}
