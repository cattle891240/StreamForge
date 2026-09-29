import Foundation

/// `UserDefaults` 读写与版本迁移。编解码失败一律回退默认值——
/// 设置读不出来不能让应用起不来。
final class SettingsStore {
    private let defaults: UserDefaults
    private let key: String
    /// 当前 schema 版本。迁移时递增并补一条迁移分支。
    static let schemaVersion = 1

    init(suiteName: String = Defaults.userDefaultsSuite, key: String = Defaults.settingsKey) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.key = key
    }

    func load() -> AppSettings.Snapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(AppSettings.Snapshot.self, from: data)
        else { return AppSettings.Snapshot() }
        return snapshot
    }

    func save(_ snapshot: AppSettings.Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
