import Foundation

/// 历史记录 JSON 落盘。写入原子化：先写同目录 tmp 再 rename。
final class HistoryStore {
    private let fileURL: URL
    static let maximumRecords = 200

    init(path: String = Paths.historyFile()) {
        self.fileURL = URL(fileURLWithPath: path)
    }

    func load() -> [TaskHistoryRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([TaskHistoryRecord].self, from: data)
        else { return [] }
        return records
    }

    func save(_ records: [TaskHistoryRecord]) {
        let trimmed = Array(records.prefix(Self.maximumRecords))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        Paths.ensureExists(fileURL.deletingLastPathComponent().path)
        let temporary = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            _ = try? FileManager.default.removeItem(at: fileURL)
            try FileManager.default.moveItem(at: temporary, to: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
        }
    }

    func append(_ record: TaskHistoryRecord) {
        var records = load()
        records.removeAll { $0.input == record.input && $0.name == record.name }
        records.insert(record, at: 0)
        save(records)
    }

    func remove(id: UUID) {
        var records = load()
        records.removeAll { $0.id == id }
        save(records)
    }

    func clear() {
        save([])
    }
}
