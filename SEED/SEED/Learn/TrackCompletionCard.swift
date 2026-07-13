import SwiftUI

/// 트랙 수료 공유 카드 — 무료 유저도 돌릴 수 있는 공유 루프.
/// §11 가드레일: 수익률 자랑이 아니라 '완주'를 자랑한다.
/// 이미지로 렌더되므로 다크/라이트와 무관한 고정 브랜드 색을 쓴다 (DailyShareCard와 동일 문법).
struct TrackCompletionCard: View {
    let trackNumber: Int
    let trackTitle: String
    let lessonCount: Int
    let subtitle: String
    let date: Date

    private let cardWidth: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

            Text("수료")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: 0xC9BBFF))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color(hex: 0x8B74FF).opacity(0.18), in: Capsule())
                .padding(.top, 24)

            Text("트랙 \(trackNumber) · \(trackTitle)")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 10)

            Text("\(lessonCount)편 완주")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: 0x8B74FF))
                .padding(.top, 6)

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.8))
                .lineSpacing(5)
                .padding(.top, 12)

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

    @MainActor
    static func render(track: TrackDef, date: Date = .now) -> Image? {
        let subtitle = track.kind == .main
            ? "캔들 읽기부터 손절선, 자금 관리까지 — 도구 전부 해금"
            : "지수·운용보수·적립식·리밸런싱 — 예측 없이 굴리는 구조 완성"
        let renderer = ImageRenderer(content: TrackCompletionCard(
            trackNumber: track.number, trackTitle: track.title,
            lessonCount: track.lessons.count, subtitle: subtitle, date: date))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}

/// 트랙 목차의 완주 상태에서 노출되는 공유 버튼.
struct TrackCompletionShareButton: View {
    let track: TrackDef
    /// ImageRenderer는 싸지 않다 — 뷰 갱신마다가 아니라 등장 시 1회만 렌더해 보관
    @State private var card: Image?

    var body: some View {
        Group {
            if let card {
                shareLink(card)
            }
        }
        .task { if card == nil { card = TrackCompletionCard.render(track: track) } }
    }

    private func shareLink(_ card: Image) -> some View {
        ShareLink(item: card,
                      preview: SharePreview("\(track.title) 수료 카드", image: card)) {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                    Text("수료 카드 공유하기")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(SeedTheme.violetDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(SeedTheme.violetTint, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
