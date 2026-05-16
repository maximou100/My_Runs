import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

enum Theme {
    static let accent = Color(hex: "7BFF00")
    static let bgPrimary = Color(hex: "0a0a0f")
    static let bgCard = Color(hex: "1a1a2e")
    static let bgCardHover = Color(hex: "1e1e38")
    static let border = Color(hex: "2a2a4a")
    static let textSecondary = Color(hex: "9999b3")
    static let textMuted = Color(hex: "666680")
    static let danger = Color(hex: "ff4d6a")
}

extension RunCategory {
    var color: Color {
        switch self {
        case .marathon: return Color(hex: "ffa500")
        case .halfMarathon: return Color(hex: "ffd700")
        case .fifteenK: return Color(hex: "7BFF00")
        case .tenK: return Color(hex: "4da6ff")
        case .fiveK: return Color(hex: "c084fc")
        case .short_: return Color(hex: "9999b3")
        }
    }
}
