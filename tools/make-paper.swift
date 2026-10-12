// 生成“揉皱后摊平”的米色纸张背景（浅色 + 深色两张 JPEG）。
// 用法：swiftc -O tools/make-paper.swift -o /tmp/make-paper && /tmp/make-paper iOS/Assets.xcassets/Paper.imageset
//
// 原理：把屏幕分成网格，每格随机放几条短折痕（两端渐隐、有凸有凹，只在折痕两侧一小段有坡度），
// 轻微扭曲、模糊后按左上方光照算出明暗——像纸被轻轻揉过又抚平，褶皱均匀分布。
import AppKit
import UniformTypeIdentifiers

let width = 1320, height = 2868   // 覆盖最大的 iPhone 屏幕（3x）
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

struct RNG {
    var state: UInt64
    mutating func next() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(state >> 40) / Float(1 << 24)
    }
}

/// 一条折痕：沿直线的 V 形（或倒 V 形）凹凸，离开折痕 reach 像素后变平，两端渐隐
struct Fold {
    var cx, cy, dx, dy, halfLength, reach, amp: Float

    init(cx: Float, cy: Float, rng: inout RNG) {
        self.cx = cx
        self.cy = cy
        let angle = rng.next() * .pi
        dx = cos(angle)
        dy = sin(angle)
        halfLength = 50 + rng.next() * 130
        reach = 10 + rng.next() * 24
        amp = (0.35 + rng.next() * 0.65) * (rng.next() < 0.5 ? -1 : 1)
    }

    /// 影响范围（用于只在折痕附近计算，加快速度）
    var bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        let r = halfLength + reach
        return (max(0, Int(cx - r)), min(width - 1, Int(cx + r)), max(0, Int(cy - r)), min(height - 1, Int(cy + r)))
    }

    /// 折痕处最低（或最高），离开 reach 后回到 0；沿折痕方向两端平滑地衰减到 0
    func elevation(_ x: Float, _ y: Float) -> Float {
        let rx = x - cx, ry = y - cy
        let t = (rx * dx + ry * dy) / halfLength
        guard abs(t) < 1 else { return 0 }
        let across = abs(-rx * dy + ry * dx)
        guard across < reach else { return 0 }
        let fade = (1 - t * t) * (1 - t * t)
        return amp * (across - reach) * fade
    }
}

/// 平滑的扭曲场，让折痕不是直线
struct Warp {
    var waves: [(fx: Float, fy: Float, phase: Float, amp: Float)] = []
    init(rng: inout RNG) {
        for i in 0..<6 {
            let scale = Float(1 << i)
            waves.append((fx: (rng.next() * 2 - 1) * 0.004 * scale, fy: (rng.next() * 2 - 1) * 0.004 * scale,
                          phase: rng.next() * 6.283, amp: 28 / scale))
        }
    }
    func offset(_ x: Float, _ y: Float) -> (Float, Float) {
        var ox: Float = 0, oy: Float = 0
        for (i, w) in waves.enumerated() {
            let v = sin(w.fx * x + w.fy * y + w.phase) * w.amp
            if i % 2 == 0 { ox += v } else { oy += v }
        }
        return (ox, oy)
    }
}

var rng = RNG(state: 20261012)
// 网格均匀分布：每格放 3 条短折痕，位置在格内随机，避免挤在一起
let gridCols = 9, gridRows = 19
var folds: [Fold] = []
for r in 0..<gridRows {
    for c in 0..<gridCols {
        for _ in 0..<3 {
            let x = (Float(c) + rng.next()) * Float(width) / Float(gridCols)
            let y = (Float(r) + rng.next()) * Float(height) / Float(gridRows)
            folds.append(Fold(cx: x, cy: y, rng: &rng))
        }
    }
}
let warp = Warp(rng: &rng)

// 1. 高度图（逐条折痕累加，只算它附近的像素）
var warpX = [Float](repeating: 0, count: width * height)
var warpY = [Float](repeating: 0, count: width * height)
for y in 0..<height {
    for x in 0..<width {
        let (ox, oy) = warp.offset(Float(x), Float(y))
        warpX[y * width + x] = Float(x) + ox * 0.4
        warpY[y * width + x] = Float(y) + oy * 0.4
    }
}
var heights = [Float](repeating: 0, count: width * height)
for f in folds {
    let b = f.bounds
    for y in b.minY...b.maxY {
        for x in b.minX...b.maxX {
            let i = y * width + x
            heights[i] += f.elevation(warpX[i], warpY[i])
        }
    }
}

// 1.5 模糊高度图：让折痕变成柔和的起伏，而不是一道道“裂缝”
func boxBlur(_ src: inout [Float], radius r: Int) {
    var tmp = src
    for y in 0..<height {               // 横向
        var sum: Float = 0
        let row = y * width
        for x in -r...r { sum += src[row + min(max(x, 0), width - 1)] }
        for x in 0..<width {
            tmp[row + x] = sum / Float(2 * r + 1)
            sum += src[row + min(x + r + 1, width - 1)] - src[row + max(x - r, 0)]
        }
    }
    for x in 0..<width {                // 纵向
        var sum: Float = 0
        for y in -r...r { sum += tmp[min(max(y, 0), height - 1) * width + x] }
        for y in 0..<height {
            src[y * width + x] = sum / Float(2 * r + 1)
            sum += tmp[min(y + r + 1, height - 1) * width + x] - tmp[max(y - r, 0) * width + x]
        }
    }
}
for _ in 0..<3 { boxBlur(&heights, radius: 2) }   // 三次盒式模糊 ≈ 高斯模糊

// 2. 光照：法线 · 左上方光线
let lightRaw: (Float, Float, Float) = (-0.55, -0.65, 0.52)
let ln = (lightRaw.0 * lightRaw.0 + lightRaw.1 * lightRaw.1 + lightRaw.2 * lightRaw.2).squareRoot()
let light = (lightRaw.0 / ln, lightRaw.1 / ln, lightRaw.2 / ln)
let bump: Float = 0.30
var values = [Float](repeating: 0, count: width * height)
for y in 1..<(height - 1) {
    for x in 1..<(width - 1) {
        let i = y * width + x
        let hx = (heights[i + 1] - heights[i - 1]) * 0.5 * bump
        let hy = (heights[i + width] - heights[i - width]) * 0.5 * bump
        let inv = 1 / (hx * hx + hy * hy + 1).squareRoot()
        values[i] = (-hx * light.0 - hy * light.1 + light.2) * inv - light.2
    }
}

func render(base: (Float, Float, Float), amplitude: Float, vignette: Float, name: String) throws {
    var noise = RNG(state: 7)
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = y * width + x
            let dx = Float(x) / Float(width) - 0.5, dy = Float(y) / Float(height) - 0.5
            let edge = 1 - vignette * (dx * dx + dy * dy) * 2.2
            let grain = (noise.next() - 0.5) * 0.012
            let k = values[i] * amplitude + grain
            func channel(_ c: Float) -> UInt8 { UInt8(max(0, min(255, (c * edge + k) * 255))) }
            pixels[i * 4] = channel(base.0)
            pixels[i * 4 + 1] = channel(base.1)
            pixels[i * 4 + 2] = channel(base.2)
        }
    }
    let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    print("已生成 \(url.path)")
}

// 浅色：米白纸（#FAF7F1）；深色：暖褐色夜间纸（#1D1A16）
try render(base: (0xFA / 255.0, 0xF7 / 255.0, 0xF1 / 255.0), amplitude: 0.075, vignette: 0, name: "paper-light.jpg")
try render(base: (0x1D / 255.0, 0x1A / 255.0, 0x16 / 255.0), amplitude: 0.04, vignette: 0, name: "paper-dark.jpg")
