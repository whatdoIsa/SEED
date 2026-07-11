import SwiftUI

/// 앱 최상위 — 탭 구조. 배우기·복기 탭은 해당 마일스톤에서 추가된다.
struct RootView: View {
    @Bindable var session: MarketSession
    let store: SeedStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab = 0
    @State private var purchases = PurchaseStore()

    var body: some View {
        Group {
            if store.progress.onboardingDone {
                mainTabs
            } else {
                OnboardingView(store: store)
                    .onAppear { Analytics.log(.onboardingStart) }
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
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // 백그라운드 저장 + 복귀 시 경과분 따라잡기 (§9.2 catch-up)
            session.handleScenePhase(active: phase == .active)
            // 알림 갱신은 활성화 시에만 — 서스펜드 순간의 XPC 호출은 크래시를 부른다
            if phase == .active {
                // iCloud 복원분(늦게 도착)을 화면에 합류시키고 중복 레코드를 정리
                store.refreshAfterRemoteImport()
                SeedNotifications.rescheduleIfAuthorized(
                    weeklyTradeCount: store.weeklyTradeCount())
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
            NotificationCenter.default.post(name: .seedOpenDailyMarket, object: nil)
        }
    }
}

extension Notification.Name {
    /// 위젯 딥링크가 오늘의 장을 열라고 알릴 때
    static let seedOpenDailyMarket = Notification.Name("seed.openDailyMarket")
}
