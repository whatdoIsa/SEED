import SwiftUI
import JurinKit

/// 가치투자 미션 (레슨 7) — PER만 보고 고르기 → 왜 싼지 드러남.
/// 예측(어느 게 싼가) → 선택 → 3개월 뒤 결과(저PER의 함정 vs 정상 PER의 안정).
struct ValueTrapMissionView: View {
    let onSuccess: () -> Void

    private enum Phase: Equatable { case pick, result }

    /// 가상의 세 회사 — 이름은 이 미션에서만 쓴다.
    private struct Candidate: Identifiable {
        let name: String
        let tag: String
        let price: Int
        let per: Double
        let pbr: Double
        /// 3개월 뒤 가격 (이유가 결과로 드러난다)
        let futurePrice: Int
        let reveal: String
        var id: String { name }
    }

    private let candidates: [Candidate] = [
        Candidate(name: "가온중공업", tag: "저PER",
                  price: 42_000, per: 3.2, pbr: 0.4, futurePrice: 33_000,
                  reveal: "주력 사업 수주가 끊겨 이익이 급감할 예정이었어요. 시장은 이미 알고 가격을 낮춰둔 거예요 — 이게 가치 함정이에요."),
        Candidate(name: "가온식품", tag: "보통 PER",
                  price: 68_000, per: 11.5, pbr: 1.2, futurePrice: 71_000,
                  reveal: "특별할 것 없는 꾸준한 회사예요. PER이 평범한 데는 평범한 이유가 있었죠 — 그래서 크게 오르지도, 무너지지도 않았어요."),
        Candidate(name: "가온바이오", tag: "고PER",
                  price: 95_000, per: 68.0, pbr: 7.0, futurePrice: 88_000,
                  reveal: "신약 기대로 비싸게 거래됐지만, 기대가 조금 식으며 내렸어요. 높은 PER은 '기대를 산다'는 뜻이라 기대가 흔들리면 약해요.")
    ]

    @State private var phase: Phase = .pick
    @State private var picked: Int?

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .pick: pickStage
            case .result: resultStage
            }
        }
    }

    // MARK: 1. 고르기

    private var pickStage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("셋 중 가장 '싼' 회사는?")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
                .padding(.top, 22)
            Text("가격이 아니라 이익 대비(PER)로 저울질해보세요.")
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.textSecondary)
                .padding(.top, 6)

            VStack(spacing: 10) {
                ForEach(Array(candidates.enumerated()), id: \.offset) { index, c in
                    Button {
                        picked = index
                        phase = .result
                    } label: {
                        candidateCard(c)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 18)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func candidateCard(_ c: Candidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(c.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text(c.tag)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SeedTheme.violetDeep)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(SeedTheme.violetTint, in: Capsule())
                Spacer()
                Text("\(c.price.formatted())원")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
            }
            HStack(spacing: 16) {
                metricPair("PER", "\(c.per.formatted(.number.precision(.fractionLength(1))))배")
                metricPair("PBR", "\(c.pbr.formatted(.number.precision(.fractionLength(1))))배")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SeedTheme.band, lineWidth: 1))
    }

    private func metricPair(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 12)).foregroundStyle(SeedTheme.textSecondary)
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(SeedTheme.textPrimary)
        }
    }

    // MARK: 2. 결과 (3개월 뒤)

    private var resultStage: some View {
        let pickedIndex = picked ?? 0
        let pickedC = candidates[pickedIndex]
        let pickedReturn = Double(pickedC.futurePrice - pickedC.price) / Double(pickedC.price) * 100
        // 가장 낮은 PER을 골랐는가 = 순진하게 '싸다'만 본 선택
        let lowestPerIndex = candidates.enumerated().min { $0.element.per < $1.element.per }?.offset ?? 0
        let choseTheTrap = pickedIndex == lowestPerIndex

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("3개월 뒤…")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                    .padding(.top, 16)

                VStack(spacing: 8) {
                    ForEach(Array(candidates.enumerated()), id: \.offset) { index, c in
                        resultRow(c, isPicked: index == pickedIndex)
                    }
                }

                coachCard(pickedC: pickedC, pickedReturn: pickedReturn, choseTheTrap: choseTheTrap)

                Text("교육용 · 실제 종목·수익 보장 아님")
                    .font(.system(size: 10))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    .frame(maxWidth: .infinity)

                Button(action: onSuccess) {
                    Text("다음")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }

    private func resultRow(_ c: Candidate, isPicked: Bool) -> some View {
        let change = Double(c.futurePrice - c.price) / Double(c.price) * 100
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(c.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                if isPicked {
                    Text("내 선택")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SeedTheme.violetDeep)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(SeedTheme.violetTint, in: Capsule())
                }
                Spacer()
                Text("\(c.price.formatted()) → \(c.futurePrice.formatted())")
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                Text("\(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(0))))%")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SeedTheme.pnl(change))
                    .frame(width: 48, alignment: .trailing)
            }
            Text(c.reveal)
                .font(.system(size: 12))
                .foregroundStyle(SeedTheme.textSecondary)
                .lineSpacing(3)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .stroke(isPicked ? SeedTheme.violet.opacity(0.6) : .clear, lineWidth: 1.5))
    }

    private func coachCard(pickedC: Candidate, pickedReturn: Double, choseTheTrap: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "message.circle.fill").font(.system(size: 12))
                Text("코치").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(SeedTheme.violetOnDark)
            Text(choseTheTrap
                 ? "PER이 가장 낮은 걸 골랐네요 — 가장 싸 보였으니까요. 그런데 싼 데는 이유가 있었어요. PER은 출발점이지 정답이 아니에요."
                 : "숫자만 보고 가장 싼 걸 덥석 잡지 않았네요. PER이 낮다고 무조건 좋은 게 아니라는 걸 이미 아는 거예요.")
                .font(.system(size: 14))
                .foregroundStyle(SeedTheme.inkText)
                .lineSpacing(5)
            Text("가치투자는 '싼 걸 사는 것'이 아니라 '가격보다 가치가 큰 걸 사는 것'이에요. 숫자 뒤의 '왜'를 묻는 게 시작이에요.")
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.inkText.opacity(0.85))
                .lineSpacing(5)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeedTheme.ink, in: RoundedRectangle(cornerRadius: 16))
    }
}
