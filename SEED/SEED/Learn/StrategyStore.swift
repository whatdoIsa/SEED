import Foundation
import JurinKit

/// 아레나 출전 전략 슬롯 — 퀀트 빌더에서 만든 전략 하나를 저장해
/// 아레나의 7번째 선수로 내보낸다. 기기 저장(UserDefaults JSON).
enum StrategyStore {
    private static let key = "seed.arena.myStrategy"

    static func save(_ strategy: QuantStrategy) {
        guard let data = try? JSONEncoder().encode(strategy) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> QuantStrategy? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(QuantStrategy.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
