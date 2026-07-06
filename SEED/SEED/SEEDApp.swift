import SwiftUI
import SwiftData

@main
struct SEEDApp: App {
    private let container: ModelContainer
    @State private var session: MarketSession
    @State private var store: SeedStore

    init() {
        do {
            let container = try ModelContainer(
                for: SeedStore.schema,
                configurations: [ModelConfiguration(schema: SeedStore.schema)]
            )
            self.container = container
            let store = SeedStore(context: container.mainContext)
            _store = State(initialValue: store)
            _session = State(initialValue: MarketSession(portfolio: store.restorePortfolio()))
        } catch {
            fatalError("SwiftData 컨테이너 생성 실패: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session, store: store)
        }
        .modelContainer(container)
    }
}
