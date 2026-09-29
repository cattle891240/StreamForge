import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 拖入内容的识别：文件按扩展名白名单，文本按行抽取 http 链接或已存在的本地路径
/// （architecture.md §8.4）。识别不了就返回空，由调用方给出诚实提示。
enum DropReceiver {

    private static let allowedExtensions: Set<String> = ["m3u8", "mpd", "ism", "ismv", "txt", "json"]

    static func sources(fromFileURLs urls: [URL]) -> [InputSource] {
        urls.compactMap { url in
            allowedExtensions.contains(url.pathExtension.lowercased())
                ? InputSource.localFile(url)
                : nil
        }
    }

    static func firstSource(in text: String) -> InputSource? { allSources(in: text).first }

    static func allSources(in text: String) -> [InputSource] {
        var result: [InputSource] = []
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("http://") || line.hasPrefix("https://") {
                result.append(.url(line))
                continue
            }
            let path: String?
            if line.hasPrefix("file://") {
                path = String(line.dropFirst(7))
            } else if line.hasPrefix("/") {
                path = line
            } else {
                path = nil
            }
            if let path, FileManager.default.fileExists(atPath: path) {
                result.append(.localFile(URL(fileURLWithPath: path)))
            }
        }
        return result
    }

    /// `NSItemProvider` → 输入源。异步加载，主线程回调。
    static func load(_ providers: [NSItemProvider], completion: @escaping ([InputSource]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var collected: [InputSource] = []

        func append(_ sources: [InputSource]) {
            lock.lock()
            collected.append(contentsOf: sources)
            lock.unlock()
        }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let url = item as? URL { append(Self.sources(fromFileURLs: [url])) }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                    if let text = item as? String { append(Self.allSources(in: text)) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { completion(collected) }
    }
}

/// 拖拽悬停层：虚线框 + 底色，仅在 `isTargeted` 为真时出现（design.md §4.3）。
struct DropZoneOverlay<Content: View>: View {

    @Binding var isTargeted: Bool
    var onReceive: ([InputSource]) -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .onDrop(of: [.fileURL, .text], isTargeted: $isTargeted) { providers in
                DropReceiver.load(providers) { sources in
                    guard !sources.isEmpty else { return }
                    onReceive(sources)
                }
                return true
            }
            .overlay {
                if isTargeted {
                    ZStack {
                        RoundedRectangle(cornerRadius: SFRadius.lg)
                            .fill(SFColor.fillQuaternary.opacity(0.4))
                        RoundedRectangle(cornerRadius: SFRadius.lg)
                            .strokeBorder(SFColor.border, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        VStack(spacing: SFSpace.s2) {
                            Image(systemName: SFSymbol.emptyTray)
                                .font(.largeTitle)
                                .foregroundStyle(SFColor.labelSecondary)
                            Text("松手即新建下载任务")
                                .font(.headline)
                            Text("支持 .m3u8 / .mpd 文件或 http 链接")
                                .font(.caption)
                                .foregroundStyle(SFColor.labelSecondary)
                        }
                    }
                    .padding(SFSpace.s3)
                    .allowsHitTesting(false)
                }
            }
    }
}
