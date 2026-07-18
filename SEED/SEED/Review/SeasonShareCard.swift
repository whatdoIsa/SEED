import SwiftUI

/// 시즌 부검 공유 카드 — 시즌 마감은 가장 공유하고 싶은 순간.
/// 수익률이 아니라 '가져가는 규칙'이 주인공이다 (§8.3 — 이월되는 것은 돈이 아니라 교훈).
struct SeasonShareCard: View {
    let seasonNumber: Int
    let returnPct: Double
    let tradeCount: Int
    let carriedRule: String?
    let date: Date

    var body: some View {
        ShareCardFrame(date: date) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                Text("시즌 \(seasonNumber) 마감")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Color(hex: 0xC9BBFF))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(hex: 0x8B74FF).opacity(0.18), in: Capsule())
            .padding(.top, 24)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(returnPct >= 0 ? "+" : "")\(returnPct.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(returnPct >= 0 ? Color(hex: 0xFF8A93) : Color(hex: 0x8FBAFF))
                Text("매매 \(tradeCount)건")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.top, 12)

            if let rule = carriedRule, !rule.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("다음 시즌으로 가져가는 규칙")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: 0xC9BBFF))
                    Text("\u{201C}\(rule)\u{201D}")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineSpacing(4)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0x8B74FF).opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(hex: 0x8B74FF).opacity(0.35), lineWidth: 1))
                .padding(.top, 18)
            } else {
                Text("잃어도 남는 게 있으면 시즌은 성공이에요.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 18)
            }
        }
    }

    @MainActor
    static func render(seasonNumber: Int, returnPct: Double, tradeCount: Int,
                       carriedRule: String?, date: Date = .now) -> Image? {
        let renderer = ImageRenderer(content: SeasonShareCard(
            seasonNumber: seasonNumber, returnPct: returnPct,
            tradeCount: tradeCount, carriedRule: carriedRule, date: date))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}
