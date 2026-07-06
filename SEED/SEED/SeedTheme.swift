import SwiftUI

/// 기획서 v0.3 §10.0 색 시스템.
/// 규칙: 빨/파는 손익 전용, 바이올렛은 브랜드(학습·코치·해금·모의 배지) 전용 — 역할 혼용 금지.
enum SeedTheme {

    // MARK: 기능색 (손익 전용 — 한국식: 상승 빨강 / 하락 파랑)
    static let up = Color(hex: 0xF04452)
    static let down = Color(hex: 0x3182F6)
    static let upTint = Color(hex: 0xFEE8EA)
    static let downTint = Color(hex: 0xEAF2FE)

    // MARK: 브랜드 — 아크 바이올렛
    static let violet = Color(hex: 0x6B4EFF)
    static let violetDeep = Color(hex: 0x4A32D9)
    static let violetOnDark = Color(hex: 0x9D8CFF)
    static let violetTint = Color(hex: 0xEFEBFF)

    // MARK: 중립
    static let textPrimary = Color(hex: 0x191F28)
    static let textSecondary = Color(hex: 0x8B95A1)
    static let band = Color(hex: 0xF2F4F6)
    static let card = Color(hex: 0xF9FAFB)
    static let ink = Color(hex: 0x17171C)
    /// 잉크(다크 카드) 위 본문 텍스트
    static let inkText = Color(hex: 0xF2F3F5)

    /// 손익 부호에 따른 기능색.
    static func pnl(_ value: Double) -> Color {
        if value > 0 { return up }
        if value < 0 { return down }
        return textSecondary
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
