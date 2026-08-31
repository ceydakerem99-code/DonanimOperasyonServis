import Foundation

/// Lightweight configurable item for admin-managed work types and pause reasons.
struct CustomConfigItem: Identifiable, Codable, Hashable {
    let id: String
    var name: String

    init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

/// UserDefaults-backed store for custom admin configuration items.
/// Built-in enum cases are always present; this store holds additional
/// entries the admin creates.
enum CustomConfigStore {
    private static let workTypesKey = "admin.custom.workTypes"
    private static let pauseReasonsKey = "admin.custom.pauseReasons"

    static func loadWorkTypes() -> [CustomConfigItem] {
        load(key: workTypesKey)
    }

    static func saveWorkTypes(_ items: [CustomConfigItem]) {
        save(items, key: workTypesKey)
    }

    static func loadPauseReasons() -> [CustomConfigItem] {
        load(key: pauseReasonsKey)
    }

    static func savePauseReasons(_ items: [CustomConfigItem]) {
        save(items, key: pauseReasonsKey)
    }

    private static func load(key: String) -> [CustomConfigItem] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CustomConfigItem].self, from: data)) ?? []
    }

    private static func save(_ items: [CustomConfigItem], key: String) {
        let data = try? JSONEncoder().encode(items)
        UserDefaults.standard.set(data, forKey: key)
    }
}
