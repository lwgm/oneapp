import SwiftUI

extension Color {
    static let paper = Color(red: 0.984, green: 0.980, blue: 0.973)
    static let ink = Color(red: 0.078, green: 0.082, blue: 0.098)
    static let sub = Color(red: 0.420, green: 0.435, blue: 0.463)
    /// 设置页这类分组列表的底色，比 paper 略深一档，让白色卡片浮起来。
    static let grouped = Color(red: 0.949, green: 0.941, blue: 0.922)
    static let danger = Color(red: 0.75, green: 0.22, blue: 0.17)
    static let success = Color(red: 0.141, green: 0.353, blue: 0.325)
    static let caution = Color(red: 0.70, green: 0.47, blue: 0.09)
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
