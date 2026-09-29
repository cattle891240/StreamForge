import Foundation

/// 任务输入源。本地文件保留原始 URL，以便重试时复用完全相同的参数（ADR-003）。
enum InputSource: Codable, Equatable {
    case url(String)
    case localFile(URL)

    /// 交给内核 argv 的取值：URL 原样，本地文件用路径。
    var argumentValue: String {
        switch self {
        case .url(let value): return value
        case .localFile(let url): return url.path
        }
    }

    var isLocalFile: Bool {
        if case .localFile = self { return true }
        return false
    }

    /// 列表展示用的简要来源描述。
    var displayText: String {
        switch self {
        case .url(let value): return value
        case .localFile(let url): return url.lastPathComponent
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let value = try container.decode(String.self, forKey: .value)
        if kind == "url" {
            self = .url(value)
        } else {
            self = .localFile(URL(fileURLWithPath: value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .url(let value):
            try container.encode("url", forKey: .kind)
            try container.encode(value, forKey: .value)
        case .localFile(let url):
            try container.encode("file", forKey: .kind)
            try container.encode(url.path, forKey: .value)
        }
    }
}
