import SwiftUI

/// 공유 카드 공통 골격 — 세 카드(오늘의 장·시즌·수료)가 같은 헤더·배경·푸터 문법을 쓴다.
/// 이미지로 렌더되므로 다크/라이트와 무관한 고정 브랜드 색.
struct ShareCardFrame<Content: View>: View {
    let date: Date
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0x8B74FF))
                Text("SEED")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(.white)
                    .kerning(1.5)
                Spacer()
                Text(date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "ko_KR"))))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }

            content

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
        .frame(width: 340, alignment: .leading)
        .background(ShareCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

/// 공유 카드 배경 — 딥 바이올렛 그라데이션 + 우상단 글로우 + 우하단 잎 워터마크.
struct ShareCardBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x141020), Color(hex: 0x2A2145)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: 0x8B74FF).opacity(0.28), .clear],
                           center: .init(x: 0.95, y: 0.02),
                           startRadius: 8, endRadius: 240)
            Image(systemName: "leaf.fill")
                .font(.system(size: 170, weight: .bold))
                .foregroundStyle(Color(hex: 0x8B74FF).opacity(0.08))
                .rotationEffect(.degrees(-16))
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .bottomTrailing)
                .offset(x: 42, y: 48)
        }
    }
}

/// 스파크라인 — 실데이터 전용 (오늘의 장 종가 경로). 장식용 가짜 곡선은 §11 위반.
struct ShareSparkline: View {
    let values: [Double]
    let lineColor: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1,
                  let low = values.min(), let high = values.max(), high > low else { return }
            let range = high - low
            func point(_ index: Int) -> CGPoint {
                CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                        y: size.height * (1 - CGFloat((values[index] - low) / range)))
            }
            var line = Path()
            line.move(to: point(0))
            for index in 1..<values.count { line.addLine(to: point(index)) }

            // 라인 아래를 은은하게 채워 '흐름'이 배경처럼 깔리게
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(
                Gradient(colors: [lineColor.opacity(0.22), lineColor.opacity(0.0)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

            context.stroke(line, with: .color(lineColor),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            // 끝점 도트 — '지금 여기'
            let last = point(values.count - 1)
            context.fill(Path(ellipseIn: CGRect(x: last.x - 3.5, y: last.y - 3.5,
                                                width: 7, height: 7)),
                         with: .color(lineColor))
        }
    }
}
