import SwiftUI

/// 全局配色：米色 + 纸张。想调整颜色只改这里。
enum Theme {
    #if os(iOS)
    /// 纸张底色（浅色模式米白；深色模式是暖褐色的“夜间纸”）
    static let paper = dynamic(light: 0xFAF7F1, dark: 0x1D1A16)
    /// 纸张边缘稍深的晕染
    static let paperShade = dynamic(light: 0xF1ECE3, dark: 0x13110E)
    /// 正文墨色
    static let ink = dynamic(light: 0x3A3027, dark: 0xEDE3D3)
    static let inkSecondary = dynamic(light: 0x857563, dark: 0xA99B88)
    /// 强调色：在纸上用于文字和图标（柔和的灰米色）
    static let accent = dynamic(light: 0xB9AC9A, dark: 0xE6DED2)
    /// 米色填充：按钮、高亮
    static let beige = dynamic(light: 0xF5F0E7, dark: 0xD9CFBF)
    /// 米色按钮上的文字
    static let onBeige = Color(hex: 0x2E261D)
    /// 可点的文字/图标（系统按钮、弹窗按钮、选中的标签）：比 accent 深一些，保证看得清
    static let tint = dynamic(light: 0x8A7A66, dark: 0xE6DED2)
    /// 纸上的主按钮/选中项：比 beige 稍深，和纸张背景拉开一点
    static let beigeButton = dynamic(light: 0xE3D7C4, dark: 0xBFB19B)
    /// 玻璃的轻微染色，让玻璃在纸上更通透
    static let glassTint = dynamic(light: 0xFFFBF2, dark: 0x3A3127, lightAlpha: 0.35, darkAlpha: 0.25)
    static let gold = dynamic(light: 0xC2AB84, dark: 0xE8D8B6)
    /// 训练热力图：没练 + 4 档强度（浅米 → 深棕）
    static let heat: [Color] = [
        dynamic(light: 0x3A3027, dark: 0xEDE3D3, lightAlpha: 0.07, darkAlpha: 0.08),
        dynamic(light: 0xE6DAC6, dark: 0x4A3F33),
        dynamic(light: 0xCDB794, dark: 0x6E5D48),
        dynamic(light: 0xA88B63, dark: 0x9A8366),
        dynamic(light: 0x7A5F3E, dark: 0xCDB794),
    ]
    static let warmup = dynamic(light: 0xC0682E, dark: 0xE89A5C)

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
    #else
    /// 手表是黑底，用更亮一点的米色
    static let accent = Color(hex: 0xF7F3EC)
    static let beige = Color(hex: 0xF4EFE6)
    static let onBeige = Color(hex: 0x2E261D)
    static let gold = Color(hex: 0xEADCBD)
    static let warmup = Color(hex: 0xE89A5C)
    #endif
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

#if os(iOS)
extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
#endif
