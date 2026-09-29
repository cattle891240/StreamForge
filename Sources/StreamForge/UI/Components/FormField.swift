import SwiftUI
import AppKit

/// 表单行：标题 + 帮助气泡 + 右侧控件 + 字段级错误（错误说清「哪里错 + 怎么修」，design.md §4.2）。
struct FormField<Content: View>: View {
    let title: String
    var help: String? = nil
    var error: String? = nil
    @ViewBuilder var content: () -> Content

    init(_ title: String,
         help: String? = nil,
         error: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.help = help
        self.error = error
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SFSpace.s1) {
            HStack(alignment: .firstTextBaseline, spacing: SFSpace.s2) {
                HStack(spacing: SFSpace.s1) {
                    Text(title)
                    if let help { FieldHelpButton(text: help) }
                }
                .frame(minWidth: 148, alignment: .leading)
                content().frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error {
                HStack(spacing: SFSpace.s1) {
                    Image(systemName: SFSymbol.dependencyMissing).imageScale(.small)
                    Text(error).font(.footnote)
                }
                .foregroundStyle(SFColor.danger)
            }
        }
        .padding(.vertical, SFSpace.s1)
    }
}

struct FieldHelpButton: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: { Image(systemName: SFSymbol.help).imageScale(.small) }
            .buttonStyle(.borderless)
            .foregroundStyle(SFColor.info)
            .accessibilityLabel("说明：\(text)")
            .popover(isPresented: $shown) {
                Text(text).font(.footnote).frame(maxWidth: 280).padding(SFSpace.s3)
            }
    }
}

/// 目录 / 文件选择。design.md §4.2：选目录必须退回 `NSOpenPanel`，`.fileImporter` 不支持目录。
enum PanelPicker {
    static func chooseDirectory(current: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        if !current.isEmpty { panel.directoryURL = URL(fileURLWithPath: current) }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func chooseFile(current: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "选择"
        if !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (current as NSString).deletingLastPathComponent)
        }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
