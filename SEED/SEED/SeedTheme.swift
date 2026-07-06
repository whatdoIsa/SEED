import SwiftUI
import UIKit

/// 기획서 v0.3 §10.0 색 시스템 — 라이트/다크 적응형.
/// 규칙: 빨/파는 손익 전용, 바이올렛은 브랜드(학습·코치·해금·모의 배지) 전용 — 역할 혼용 금지.
/// 기능색(빨/파)과 브랜드 바이올렛은 두 모드에서 동일한 값을 쓴다 — 손익·브랜드의 일관성.
enum SeedTheme {

    // MARK: 기능색 (손익 전용 — 한국식: 상승 빨강 / 하락 파랑, 모드 불변)
    static let up = Color(hex: 0xF04452)
    static let down = Color(hex: 0x3182F6)
    static let upTint = adaptive(light: 0xFEE8EA, dark: 0x3B2126)
    static let downTint = adaptive(light: 0xEAF2FE, dark: 0x1B2A40)

    // MARK: 브랜드 — 아크 바이올렛
    static let violet = Color(hex: 0x6B4EFF)
    static let violetDeep = adaptive(light: 0x4A32D9, dark: 0xC3B7FF)
    static let violetOnDark = Color(hex: 0x9D8CFF)
    static let violetTint = adaptive(light: 0xEFEBFF, dark: 0x2B2447)

    // MARK: 중립 (적응형)
    static let background = adaptive(light: 0xFFFFFF, dark: 0x111116)
    static let card = adaptive(light: 0xF9FAFB, dark: 0x1D1D24)
    static let band = adaptive(light: 0xF2F4F6, dark: 0x26262E)
    static let textPrimary = adaptive(light: 0x191F28, dark: 0xF0F1F4)
    static let textSecondary = Color(hex: 0x8B95A1)
    /// textPrimary를 배경으로 쓰는 컨트롤 위의 글자색 (칩·버튼)
    static let inverse = adaptive(light: 0xFFFFFF, dark: 0x15151A)

    // MARK: 잉크 (코치 카드 — 다크에서는 배경보다 살짝 밝게 떠 보이게)
    static let ink = adaptive(light: 0x17171C, dark: 0x24242D)
    static let inkText = Color(hex: 0xF2F3F5)

    /// 손익 부호에 따른 기능색.
    static func pnl(_ value: Double) -> Color {
        if value > 0 { return up }
        if value < 0 { return down }
        return textSecondary
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
