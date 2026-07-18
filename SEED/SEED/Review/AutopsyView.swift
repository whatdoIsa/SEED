import SwiftUI
import JurinKit

/// 계좌 부검 (M4-3, 부록 A-5) — 리셋 버튼 앞의 강제 복기 게이트.
/// 손실을 정직하게 마주하되, 이월되는 것은 돈이 아니라 규칙이다.
struct AutopsyView: View {
    let store: SeedStore
    @Bindable var session: MarketSession
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRule: String?
    /// 진입 시점 총자산 스냅샷 — session.totalEquity를 body에서 직접 읽으면 아래 세션이 계속 돌아
    /// 매 틱 body가 재평가되고, AI 지문이 틱마다 바뀌어 온디바이스 생성이 무한 재시작된다 (시뮬 미재현).
    @State private var equitySnapshot: Int?

    static let rulePresets = [
        "한 종목에 30% 이상 넣지 않기",
        "급등을 봐도 첫 눌림까지 기다리기",
        "사기 전에 이유를 딱 하나 정하기"
    ]

    var body: some View {
        let equity = equitySnapshot ?? session.totalEquity
        let startCash = store.currentSeason.startCash
        let returnPct = Double(equity - startCash) / Double(startCash) * 100

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                inkHeader
                accountSummary(equity: equity, returnPct: returnPct)

                // AI 부검: 시즌당 1회 (시즌 키 캐시)
                AICoachCard(
                    cacheKey: "autopsy.\(store.currentSeason.number)",
                    fingerprint: "\(equity)",
                    prompt: autopsyPrompt(equity: equity, returnPct: returnPct),
                    maxTokens: 300
                )
                .padding(.horizontal, 20)
                habitSection
                if equity <= startCash / 2 {
                    halfLossMath(equity: equity, startCash: startCash)
                }
                carrySection
                carryOverSection
                confirmButton(equity: equity)
                Text("교육용 복기 · 투자 권유 아님")
                    .font(.system(size: 10))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .background(SeedTheme.background)
        .scrollClipDisabled() // 잉크 헤더가 상태바 뒤까지 그려지도록 (위 -160pt 배경 확장과 한 쌍)
        .onAppear {
            if equitySnapshot == nil { equitySnapshot = session.totalEquity }
        }
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
        // 잉크 배경을 위로 늘려 상태바 뒤까지 — 위에 뜨는 검은 띠 제거
        .background(SeedTheme.ink.padding(.top, -160))
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

    private func autopsyPrompt(equity: Int, returnPct: Double) -> String {
        let stats = store.tagStats()
        var lines = ["시즌이 끝났어. 이 시즌의 계좌 부검을 두세 문장으로 해줘. 데이터:"]
        lines.append("- 시즌 \(store.currentSeason.number): 수익률 \(returnPct >= 0 ? "+" : "")\(returnPct.formatted(.number.precision(.fractionLength(1))))%, 매매 \(store.tradeCount())건")
        for stat in stats.prefix(4) {
            let avg = stat.avgRealizedReturnPct.map { "\($0 >= 0 ? "+" : "")\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "미확정"
            lines.append("- '\(stat.tag.label)': \(stat.count)건, 평균 \(avg)")
        }
        lines.append("이 시즌의 결정적 습관 하나를 짚고, 다음 시즌으로 가져갈 규칙 하나를 제안해줘.")
        return lines.joined(separator: "\n")
    }

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
            if let stats = store.holdingStats() {
                habitRow("평균 보유 시간",
                         TradePairing.holdText(ticks: stats.avgHoldTicks),
                         warning: stats.avgHoldTicks <= 60)
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

    // MARK: 가져가는 것 — 리셋은 상실이 아니라 졸업이다

    private var carryOverSection: some View {
        let lessonCount = store.completedLessonIds.filter { !$0.hasPrefix("daily.") }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 11))
                Text("시즌 \(store.currentSeason.number + 1)로 가져가는 것")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(SeedTheme.violetDeep)
            .padding(.bottom, 9)

            carryRow("열어둔 도구 전부 (Lv\(min(store.progress.unlockLevel, UnlockLevel.max)))")
            carryRow("완료한 레슨 \(lessonCount)개와 배운 \(store.currentSeason.number)시즌의 경험")
            if let rule = selectedRule {
                carryRow("이번 시즌 규칙: “\(rule)”")
            }
            carryRow("이번 시즌 매매 기록 (성장 그래프에 보관)")

            Divider().padding(.vertical, 10)

            Text("사라지는 것은 가상 계좌 잔고뿐 — 새 1,000만원으로 다시 시작해요. 잃은 건 연습이었고, 남은 건 실력입니다.")
                .font(.system(size: 12))
                .foregroundStyle(SeedTheme.textSecondary)
                .lineSpacing(4)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func carryRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SeedTheme.violet)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.textPrimary)
        }
        .padding(.vertical, 3)
    }

    // MARK: 확인 — 여기까지 스크롤해야 리셋된다

    private func confirmButton(equity: Int) -> some View {
        let startCash = store.currentSeason.startCash
        let returnPct = startCash > 0
            ? Double(equity - startCash) / Double(startCash) * 100 : 0
        return VStack(spacing: 8) {
            // 시즌 결과 공유 — 규칙을 고른 상태 그대로 카드에 실린다
            if let card = SeasonShareCard.render(
                seasonNumber: store.currentSeason.number,
                returnPct: returnPct,
                tradeCount: store.tradeCount(),
                carriedRule: selectedRule
            ) {
                ShareLink(item: card,
                          preview: SharePreview("시즌 \(store.currentSeason.number) 마감", image: card)) {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                        Text("시즌 결과 공유하기")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(SeedTheme.violetDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(SeedTheme.violet.opacity(0.5), lineWidth: 1.2))
                }
            }
            Button {
                _ = store.startNextSeason(endEquity: equity, carriedRule: selectedRule)
                session.resetForNewSeason()
                ReviewPrompt.askIfEligible(.seasonEnd)
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
