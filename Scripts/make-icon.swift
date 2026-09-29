// make-icon.swift —— 用 CoreGraphics 绘制 AppIcon 的 iconset，供 iconutil 合成 .icns。
//
// 为什么不用 SF Symbols：SF Symbols 的许可不允许用作 App Icon（architecture.md R12）。
// 为什么不用渐变：design.md P0-2 禁止紫→粉渐变，这里一律用纯色填充。
//
// 用法：
//   swiftc -O -sdk <SDK> -target <target> Scripts/make-icon.swift -o .build/make-icon
//   .build/make-icon .build/AppIcon.iconset     # 产出 10 个尺寸的 png
//   iconutil -c icns .build/AppIcon.iconset -o AppIcon.icns
//
// 图形语义：圆角方块底 + 向下的箭头 + 底部托盘（进度条），对应"下载到磁盘"。

import Foundation
import CoreGraphics
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("用法: make-icon <输出 iconset 目录>\n".data(using: .utf8)!)
    exit(64)
}

let outputDir = arguments[1]

// iconset 要求的标准尺寸：points 与对应的 2x 像素
let sizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

func roundedRectPath(in rect: CGRect, radius: CGFloat) -> CGMutablePath {
    let path = CGMutablePath()
    let r = min(radius, rect.width / 2, rect.height / 2)
    let top = rect.maxY
    let bottom = rect.minY
    let left = rect.minX
    let right = rect.maxX

    path.move(to: CGPoint(x: left + r, y: top))
    path.addLine(to: CGPoint(x: right - r, y: top))
    path.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right, y: top - r), radius: r)
    path.addLine(to: CGPoint(x: right, y: bottom + r))
    path.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right - r, y: bottom), radius: r)
    path.addLine(to: CGPoint(x: left + r, y: bottom))
    path.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left, y: bottom + r), radius: r)
    path.addLine(to: CGPoint(x: left, y: top - r))
    path.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left + r, y: top), radius: r)
    path.closeSubpath()
    return path
}

func drawIcon(pixels: Int) -> CGImage? {
    let size = CGFloat(pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // 翻转为左上原点，便于按 UI 习惯写坐标
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    let unit = size / 100.0          // 以 100 为设计单位
    func u(_ v: CGFloat) -> CGFloat { v * unit }

    // 1) 圆角底：系统蓝（纯色，非渐变）
    let inset = u(4)
    let bounds = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    ctx.setFillColor(CGColor(red: 0.11, green: 0.45, blue: 0.92, alpha: 1.0))
    ctx.addPath(roundedRectPath(in: bounds, radius: u(22)))
    ctx.fillPath()

    // 2) 白色向下箭头：竖杆 + 三角箭头
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
    let stemWidth = u(11)
    let stemTop = u(26)
    let stemBottom = u(58)
    let stemRect = CGRect(x: (size - stemWidth) / 2, y: stemTop, width: stemWidth, height: stemBottom - stemTop)
    ctx.addPath(roundedRectPath(in: stemRect, radius: stemWidth / 2))
    ctx.fillPath()

    let arrowApexY = u(70)
    let arrowHalf = u(19)
    let arrowBaseY = u(55)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: size / 2 - arrowHalf, y: arrowBaseY))
    ctx.addLine(to: CGPoint(x: size / 2 + arrowHalf, y: arrowBaseY))
    ctx.addLine(to: CGPoint(x: size / 2, y: arrowApexY))
    ctx.closePath()
    ctx.fillPath()

    // 3) 底部托盘（进度条）：底槽 + 已完成段
    let trayHeight = u(9)
    let trayY = u(78)
    let trayRect = CGRect(x: u(24), y: trayY, width: u(52), height: trayHeight)
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.35))
    ctx.addPath(roundedRectPath(in: trayRect, radius: trayHeight / 2))
    ctx.fillPath()

    let doneRect = CGRect(x: u(24), y: trayY, width: u(32), height: trayHeight)
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
    ctx.addPath(roundedRectPath(in: doneRect, radius: trayHeight / 2))
    ctx.fillPath()

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

let iconsetURL = URL(fileURLWithPath: outputDir, isDirectory: true)
try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

var written = 0
for entry in sizes {
    let pixels = entry.points * entry.scale
    guard let image = drawIcon(pixels: pixels) else {
        FileHandle.standardError.write("绘制失败：\(pixels)px\n".data(using: .utf8)!)
        exit(1)
    }
    let name = entry.scale == 1
        ? "icon_\(entry.points)x\(entry.points).png"
        : "icon_\(entry.points)x\(entry.points)@2x.png"
    if writePNG(image, to: iconsetURL.appendingPathComponent(name)) {
        written += 1
    }
}

if written < sizes.count {
    FileHandle.standardError.write("仅写出 \(written)/\(sizes.count) 个图标\n".data(using: .utf8)!)
    exit(1)
}
print("iconset 已生成：\(outputDir)（\(written) 个 png）")
