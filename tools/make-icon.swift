// 生成 1024×1024 的 app 图标：swift tools/make-icon.swift <输出.png>
import AppKit
import UniformTypeIdentifiers

let size = 1024.0
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
// 不带透明通道（App Store 要求图标不透明）
guard let cg = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)

// 背景：驼色到浅米色的渐变
let gradient = NSGradient(colors: [NSColor(red: 0.90, green: 0.86, blue: 0.80, alpha: 1),
                                   NSColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)])!
gradient.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: 60)

// 哑铃
let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .bold)
if let symbol = NSImage(systemSymbolName: "dumbbell.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor(red: 0.23, green: 0.19, blue: 0.15, alpha: 1).set()
        rect.fill(using: .sourceAtop)
        return true
    }
    let s = tinted.size
    tinted.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2 - 60, width: s.width, height: s.height))
}

// “+1”
let text = NSAttributedString(string: "+1", attributes: [
    .font: NSFont.systemFont(ofSize: 250, weight: .heavy),
    .foregroundColor: NSColor(red: 0.68, green: 0.62, blue: 0.55, alpha: 1),
])
let ts = text.size()
text.draw(at: NSPoint(x: (size - ts.width) / 2, y: size - ts.height - 90))

NSGraphicsContext.restoreGraphicsState()
guard let image = cg.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("已生成 \(output)")
