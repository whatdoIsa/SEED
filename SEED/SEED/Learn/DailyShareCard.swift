import SwiftUI

/// 오늘의 장 공유 카드 — 무가입 로컬 앱의 유일한 성장 고리.
/// 오늘 장의 실제 가격 경로(스파크라인)가 카드의 얼굴이 된다.
struct DailyShareCard: View {
    let patternName: String
    let lessonLine: String
    let pnl: Int
    let streak: Int
    let closes: [Double]
    let date: Date

    private var pnlColor: Color { pnl >= 0 ? Color(hex: 0xFF8A93) : Color(hex: 0x8FBAFF) }

    var body: some View {
        ShareCardFrame(date: date) {
            Text("오늘의 장")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 26)
            Text(patternName)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 3)

            // 오늘 판의 실제 가격 경로 — 이 장을 겪었다는 증거이자 카드의 그림
            if closes.count > 1 {
                ShareSparkline(values: closes, lineColor: pnlColor)
                    .frame(height: 64)
                    .padding(.top, 16)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(pnl >= 0 ? "+" : "")\(pnl.formatted())원")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(pnlColor)
                if streak >= 2 {
                    Text("🔥 \(streak)일 연속")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC9BBFF))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color(hex: 0x8B74FF).opacity(0.18), in: Capsule())
                }
            }
            .padding(.top, 14)

            Text(lessonLine)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.8))
                .lineSpacing(5)
                .padding(.top, 12)
        }
    }

    /// 3배율 이미지로 렌더 — ShareLink에 그대로 물린다.
    @MainActor
    static func render(patternName: String, lessonLine: String,
                       pnl: Int, streak: Int, closes: [Double] = [],
                       date: Date = .now) -> Image? {
        let renderer = ImageRenderer(content: DailyShareCard(
            patternName: patternName, lessonLine: lessonLine,
            pnl: pnl, streak: streak, closes: closes, date: date))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}
