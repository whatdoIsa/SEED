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
            _store = State(initialValue: SeedStore(context: container.mainContext))
            _session = State(initialValue: MarketSession())
        } catch {
            fatalError("SwiftData 컨테이너 생성 실패: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            TradingView(session: session, store: store)
        }
        .modelContainer(container)
    }
}
