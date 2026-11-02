import SwiftUI
import UIKit

/// 语义色板。所有颜色都随系统浅色 / 深色模式自动切换。
///
/// 只定义「用途」不定义「色值」，页面里一律引用这些名字，
/// 避免再出现散落的 `Color.white` / `Color(red:)` 导致深色模式下瞎掉。
extension Color {
    /// 页面底色。
    static let paper = dynamic(light: 0xFBFAF8, dark: 0x0D0D10)
    /// 卡片、浮层、列表行的底色。
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1B1B1F)
    /// 主文字。
    static let ink = dynamic(light: 0x141519, dark: 0xF1EFEA)
    /// 次要文字、说明文字。
    static let sub = dynamic(light: 0x6B6F76, dark: 0x9DA1A9)
    /// 正文段落（比 sub 重、比 ink 轻）。
    static let body = dynamic(light: 0x33363C, dark: 0xD7D5D0)
    /// 分组列表底色，比 paper 低一档，让卡片浮起来。
    static let grouped = dynamic(light: 0xF2F0EB, dark: 0x08080A)
    /// 输入框 / 搜索框这类浅填充。
    static let field = dynamic(light: 0xF7F7F9, dark: 0x26262B)
    /// 主按钮的底色与文字，成对使用，深色模式下反转。
    static let primaryFill = dynamic(light: 0x141519, dark: 0xEDEAE4)
    static let primaryLabel = dynamic(light: 0xFFFFFF, dark: 0x111114)
    /// 语义色。深色模式下统一提亮，保证在深底上仍有对比。
    static let danger = dynamic(light: 0xBF382B, dark: 0xFF6B5E)
    static let success = dynamic(light: 0x245A53, dark: 0x4FC3A8)
    static let caution = dynamic(light: 0xB37817, dark: 0xE0A93F)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark)
                : UIColor(rgb: light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum CoverPalette {
    private static let pairs: [(Color, Color)] = [
        (Color(red: 0.141, green: 0.353, blue: 0.325), Color(red: 0.051, green: 0.157, blue: 0.145)),
        (Color(red: 0.553, green: 0.357, blue: 0.235), Color(red: 0.290, green: 0.169, blue: 0.102)),
        (Color(red: 0.227, green: 0.290, blue: 0.420), Color(red: 0.106, green: 0.141, blue: 0.212)),
        (Color(red: 0.478, green: 0.239, blue: 0.278), Color(red: 0.227, green: 0.122, blue: 0.149)),
        (Color(red: 0.361, green: 0.353, blue: 0.267), Color(red: 0.173, green: 0.169, blue: 0.122))
    ]

    static func gradient(for key: String) -> LinearGradient {
        let seed = key.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let pair = pairs[seed % pairs.count]
        return LinearGradient(
            colors: [pair.0, pair.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
