import SwiftUI

/// 单行日志：等宽 + 按级别着色（design.md §8.2 深色模式补偿：等宽字保持 regular 字重与 2pt 行距）。
struct LogRowView: View {

    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: SFSpace.s1) {
            HStack(alignment: .firstTextBaseline, spacing: SFSpace.s2) {
                if let timestamp = entry.timestamp {
                    Text(timestamp)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(SFColor.labelTertiary)
                        .accessibilityHidden(true)
                }
                Text(entry.level.displayName)
                    .font(.caption)
                    .foregroundStyle(levelColor)
                Text(entry.message)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.regular)
                    .foregroundStyle(levelColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let hint = entry.hint {
                HStack(spacing: SFSpace.s1) {
                    Image(systemName: SFSymbol.help).imageScale(.small)
                    Text(hint).font(.caption)
                }
                .foregroundStyle(SFColor.info)
            }
        }
        .lineSpacing(2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: return SFColor.labelSecondary
        case .info: return SFColor.label
        case .warn: return SFColor.warning
        case .error: return SFColor.danger
        }
    }
}
