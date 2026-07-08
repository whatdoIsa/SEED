import SwiftUI

/// 앱 최상위 — 탭 구조. 배우기·복기 탭은 해당 마일스톤에서 추가된다.
struct RootView: View {
    @Bindable var session: MarketSession
    let store: SeedStore
    @Environment(\.scenePhase) private var scenePhase

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
        TabView {
            TradingView(session: session, store: store)
                .tabItem { Label("시장", systemImage: "chart.bar.fill") }
            LessonListView(store: store)
                .tabItem { Label("배우기", systemImage: "book.fill") }
            ReviewReportView(store: store, session: session)
                .tabItem { Label("복기", systemImage: "text.magnifyingglass") }
            PortfolioView(session: session, store: store)
                .tabItem { Label("내 주식", systemImage: "briefcase.fill") }
        }
        .tint(SeedTheme.textPrimary)
    }
}
