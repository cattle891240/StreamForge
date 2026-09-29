// SDK 编译探针 —— 用于 Scripts/find-sdk.sh 的兼容性判定。
//
// 这个文件不是产品代码，只是一个"最小但真实"的 SwiftUI 可编译集。
// 之所以必须真实使用 SwiftUI，是因为 SDK 26.2 与 Swift 6.1.2 的不兼容
// 只在 SwiftUI 泛型展开时才暴露（报错 cannot suppress '~Copyable' on generic parameter）。
// 若探针退化成 print("hi")，26.2 会误判为可用，构建会在真正编译时才炸。
//
// 覆盖项（缺一项都可能漏掉兼容性问题）：
//   - @main + App 协议
//   - WindowGroup / Settings 两个 Scene
//   - Image(systemName:)（SF Symbols 绑定）
//   - ObservableObject + @Published + @ObservedObject / @StateObject
//   - Form + Toggle + Button + 字符串插值 Text

import SwiftUI

final class ProbeModel: ObservableObject {
    @Published var count: Int = 0
}

struct ProbeRowView: View {
    @ObservedObject var model: ProbeModel

    var body: some View {
        HStack {
            Image(systemName: "arrow.down.circle")
            Text("probe \(model.count)")
        }
    }
}

struct ProbeSettingsView: View {
    @State private var enabled: Bool = false

    var body: some View {
        Form {
            Toggle("probe toggle", isOn: $enabled)
        }
        .formStyle(.grouped)
        .padding()
    }
}

@main
struct SDKProbeApp: App {
    @StateObject private var model = ProbeModel()

    var body: some Scene {
        WindowGroup {
            VStack {
                ProbeRowView(model: model)
                Button("increment") { model.count += 1 }
            }
            .frame(width: 240, height: 160)
        }
        Settings {
            ProbeSettingsView()
        }
    }
}
