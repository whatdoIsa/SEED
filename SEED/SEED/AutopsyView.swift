import SwiftUI
import JurinKit

/// 계좌 부검 (M4-3, 부록 A-5) — 리셋 버튼 앞의 강제 복기 게이트.
/// 손실을 정직하게 마주하되, 이월되는 것은 돈이 아니라 규칙이다.
struct AutopsyView: View {
    let store: SeedStore
    @Bindable var session: MarketSession
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRule: String?

    private static let rulePresets = [
        "한 종목에 30% 이상 넣지 않기",
        "급등을 봐도 첫 눌림까지 기다리기",
        "사기 전에 이유를 딱 하나 정하기"
    ]

    var body: some View {
        let equity = session.engine.portfolio.equity(at: session.engine.lastPrice)
        let startCash = store.currentSeason.startCash
        let returnPct = Double(equity - startCash) / Double(startCash) * 100

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                inkHeader
                accountSummary(equity: equity, returnPct: returnPct)
                habitSection
                if equity <= startCash / 2 {
                    halfLossMath(equity: equity, startCash: startCash)
                }
                carrySection
                confirmButton(equity: equity)
                Text("교육용 복기 · 투자 권유 아님")
                    .font(.system(size: 10))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .background(SeedTheme.background)
    }

    // MARK: 헤더 — 사망 원인

    private var inkHeader: some View {
        let lifespanDays = max(Calendar.current.dateComponents(
            [.day], from: store.currentSeason.startedAt, to: .now).day ?? 0, 0)

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 11))
                    Text("시즌 \(store.currentSeason.number) · 계좌 부검서")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(SeedTheme.violetOnDark)
                Spacer()
                Text("수명 \(lifespanDays)일")
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.inkText.opacity(0.6))
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SeedTheme.inkText.opacity(0.7))
                }
            }
            Text("사망 원인")
                .font(.system(size: 12))
                .foregroundStyle(SeedTheme.violetOnDark)
                .padding(.top, 18)
            Text(causeOfDeath)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(SeedTheme.inkText)
                .lineSpacing(4)
                .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeedTheme.ink)
    }

    private var causeOfDeath: String {
        if let maxWeight = store.maxBuyWeightPct(), maxWeight >= 50 {
            return "자산의 \(Int(maxWeight))%를\n한 번에 넣었어요"
        }
        if let worst = store.tagStats()
            .filter({ ($0.avgRealizedReturnPct ?? 0) < 0 })
            .min(by: { ($0.avgRealizedReturnPct ?? 0) < ($1.avgRealizedReturnPct ?? 0) }) {
            return "'\(worst.tag.label)' 매매를\n반복했어요"
        }
        return "특별한 사인 없음 —\n새로 시작하고 싶었을 뿐"
    }

    // MARK: 계좌 요약

    private func accountSummary(equity: Int, returnPct: Double) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(store.currentSeason.startCash.formatted())원으로 시작 →")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)
                Spacer()
                Text("\(equity.formatted())원")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SeedTheme.pnl(Double(equity - store.currentSeason.startCash)))
            }
            HStack {
                Spacer()
                Text("\(returnPct >= 0 ? "+" : "")\(returnPct.formatted(.number.precision(.fractionLength(1))))%")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SeedTheme.pnl(returnPct))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    // MARK: 치명적 습관

    private var habitSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("이번 시즌의 습관")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
            habitRow("총 매매", "\(store.tradeCount())건")
            if let maxWeight = store.maxBuyWeightPct() {
                habitRow("최대 단일 매수 비중", "\(Int(maxWeight))%",
                         warning: maxWeight >= 50)
            }
            if let worst = store.tagStats()
                .filter({ $0.lossCount > 0 })
                .max(by: { $0.lossCount < $1.lossCount }) {
                habitRow("가장 많이 손실 난 이유",
                         "\(worst.tag.label) · \(worst.lossCount)건",
                         warning: true)
            }
            if let slippage = store.avgBuySlippage(), slippage >= 1 {
                habitRow("평균 슬리피지", "+\(Int(slippage))원")
            }
        }
        .padding(16)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func habitRow(_ label: String, _ value: String, warning: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(SeedTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(warning ? SeedTheme.down : SeedTheme.textPrimary)
        }
    }

    // MARK: 반토막의 수학 (-50% 도달 시)

    private func halfLossMath(equity: Int, startCash: Int) -> some View {
        let lossPct = Double(startCash - equity) / Double(startCash) * 100
        let neededPct = (Double(startCash) / Double(max(equity, 1)) - 1) * 100
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "function").font(.system(size: 12))
                Text("반토막의 수학 · 새 레슨")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(SeedTheme.violetOnDark)
            Text("-\(Int(lossPct))%에서 원금까지 돌아오려면 +\(Int(neededPct))%가 필요해요. 잃기는 반, 되찾기는 두 배 — 그래서 크게 잃지 않는 게 먼저예요.")
                .font(.system(size: 14))
                .foregroundStyle(SeedTheme.inkText)
                .lineSpacing(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(SeedTheme.ink, in: RoundedRectangle(cornerRadius: 15))
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: 이월 규칙 — 돈이 아니라 이것을 가져간다

    private var carrySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("시즌 \(store.currentSeason.number + 1)로 가져갈 규칙")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SeedTheme.violetDeep)
            Text("돈이 아니라 이것 하나를 가져갑니다.")
                .font(.system(size: 12))
                .foregroundStyle(SeedTheme.textSecondary)
            ForEach(Self.rulePresets, id: \.self) { rule in
                Button {
                    selectedRule = selectedRule == rule ? nil : rule
                } label: {
                    HStack {
                        Image(systemName: selectedRule == rule ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(selectedRule == rule ? SeedTheme.violet : SeedTheme.textSecondary.opacity(0.4))
                        Text(rule)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SeedTheme.textPrimary)
                        Spacer()
                    }
                    .padding(13)
                    .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(selectedRule == rule ? SeedTheme.violet : SeedTheme.band, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    // MARK: 확인 — 여기까지 스크롤해야 리셋된다

    private func confirmButton(equity: Int) -> some View {
        VStack(spacing: 8) {
            Button {
                _ = store.startNextSeason(endEquity: equity, carriedRule: selectedRule)
                session.resetForNewSeason()
                store.persistPortfolio(session.engine.portfolio)
                dismiss()
            } label: {
                Text("부검 확인 · 시즌 \(store.currentSeason.number + 1) 시작하기")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(SeedTheme.ink, in: RoundedRectangle(cornerRadius: 14))
            }
            Text("시즌 \(store.currentSeason.number) 기록은 성장 그래프에 남습니다")
                .font(.system(size: 12))
                .foregroundStyle(SeedTheme.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}
