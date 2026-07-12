import SwiftUI

/// 본문 강조 파서 — **…** 마커만 해석한다.
/// CommonMark(AttributedString(markdown:))는 닫는 ** 가 문장부호 뒤·글자 앞에 오는
/// 한국어 문장(`**파랑(음봉)**이에요`, `**'한 주'**일`)을 강조로 인정하지 않아
/// 마커가 화면에 그대로 노출된다. 우리 콘텐츠의 마크다운은 볼드뿐이므로
/// 홀짝 분할이 가장 정확하고 예측 가능하다.
enum SeedMarkdown {
    static func bold(_ text: String, size: CGFloat,
                     boldColor: Color? = nil) -> AttributedString {
        let parts = text.components(separatedBy: "**")
        // 마커가 없거나 짝이 안 맞으면 원문 그대로 (강조를 잘못 먹이지 않는다)
        guard parts.count > 1, parts.count % 2 == 1 else { return AttributedString(text) }
        var result = AttributedString()
        for (index, part) in parts.enumerated() {
            var piece = AttributedString(part)
            if index % 2 == 1 {
                piece.font = .system(size: size, weight: .semibold)
                if let boldColor {
                    piece.foregroundColor = boldColor
                }
            }
            result += piece
        }
        return result
    }
}
