import SwiftUI
import SwiftData
import UserNotifications

@main
struct SEEDApp: App {
    private let container: ModelContainer
    @State private var session: MarketSession
    @State private var store: SeedStore

    init() {
        // 포그라운드에서도 체결 배너가 보이게 — 델리게이트는 런치 직후 한 번만
        UNUserNotificationCenter.current().delegate = SeedNotificationDelegate.shared

        // 튜터 크레딧 저장소(iCloud KV) — 원격 값 당기기 + 구버전 UserDefaults 병합
        TutorCloudStore.bootstrap()

        // SwiftData의 기본 저장 위치(Application Support)가 첫 실행 시 존재하지 않아
        // 저장소 생성이 실패할 수 있다 — 미리 만들어 두면 실패 경로 자체가 사라진다.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        // iCloud 백업: 사용자의 프라이빗 CloudKit DB로 조용히 동기화 (무가입 유지).
        // iCloud 미로그인·컨테이너 문제 시 로컬 전용으로, 그마저 실패하면 인메모리로 폴백.
        func makeCloudContainer() -> ModelContainer? {
            try? ModelContainer(
                for: SeedStore.schema,
                configurations: [ModelConfiguration(
                    schema: SeedStore.schema,
                    cloudKitDatabase: .private("iCloud.kr.arcseed.SEED"))]
            )
        }
        func makeContainer(inMemory: Bool) -> ModelContainer? {
            try? ModelContainer(
                for: SeedStore.schema,
                configurations: [ModelConfiguration(schema: SeedStore.schema,
                                                    isStoredInMemoryOnly: inMemory)]
            )
        }

        // 디스크 저장소가 끝내 실패해도 앱을 죽이지 않는다 —
        // 인메모리로 내려앉아 이번 실행만 비영속으로 돈다 (fatalError 제거).
        if let cloud = makeCloudContainer() {
            self.container = cloud
        } else if let container = makeContainer(inMemory: false) {
            self.container = container
        } else if let fallback = makeContainer(inMemory: true) {
            self.container = fallback
        } else {
            // 스키마 자체가 깨진 개발 중 상황에서만 도달 가능
            fatalError("SwiftData 컨테이너 생성 실패 (디스크·인메모리 모두)")
        }
        let store = SeedStore(context: container.mainContext)
        _store = State(initialValue: store)
        _session = State(initialValue: MarketSession(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session, store: store)
        }
        .modelContainer(container)
    }
}
