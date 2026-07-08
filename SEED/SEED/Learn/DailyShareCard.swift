import SwiftUI

/// 오늘의 장 공유 카드 — 무가입 로컬 앱의 유일한 성장 고리.
/// 이미지로 렌더되므로 다크/라이트와 무관한 고정 브랜드 색을 쓴다.
struct DailyShareCard: View {
    let patternName: String
    let lessonLine: String
    let pnl: Int
    let streak: Int
    let date: Date

    private let cardWidth: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 워드마크 + 날짜
            HStack {
                Text("SEED")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x8B74FF))
                    .kerning(1.5)
                Spacer()
                Text(date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "ko_KR"))))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Text("오늘의 장")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 26)
            Text(patternName)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 3)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(pnl >= 0 ? "+" : "")\(pnl.formatted())원")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(pnl >= 0 ? Color(hex: 0xFF8A93) : Color(hex: 0x8FBAFF))
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
                .padding(.top, 14)

            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
                .padding(.top, 22)

            Text("주린이를 위한 모의투자 학습 · 가상 시장 · 교육용")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 12)
        }
        .padding(26)
        .frame(width: cardWidth, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0x17141F), Color(hex: 0x241E38)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    /// 3배율 이미지로 렌더 — ShareLink에 그대로 물린다.
    @MainActor
    static func render(patternName: String, lessonLine: String,
                       pnl: Int, streak: Int, date: Date = .now) -> Image? {
        let renderer = ImageRenderer(content: DailyShareCard(
            patternName: patternName, lessonLine: lessonLine,
            pnl: pnl, streak: streak, date: date))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}
