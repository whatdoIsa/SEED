import SwiftUI

/// 시즌 약속 설정 — 부검을 거치지 않은 시즌(주로 시즌 1)에서 약속을 정한다.
/// 부검의 이월 규칙과 같은 계보: 애착의 대상을 종목이 아니라 "나의 약속"으로.
struct SeasonPromiseSheet: View {
    let store: SeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    @State private var custom = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(SeedTheme.band).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            Text("시즌 \(store.currentSeason.number)의 약속")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
            Text("이번 시즌, 지킬 것 하나만 고르세요. 내 주식 탭에 시즌 내내 붙어 있어요.")
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.textSecondary)
                .lineSpacing(4)

            ForEach(AutopsyView.rulePresets, id: \.self) { rule in
                Button {
                    selected = selected == rule ? nil : rule
                    custom = ""
                } label: {
                    HStack {
                        Image(systemName: selected == rule ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(selected == rule
                                             ? SeedTheme.violet
                                             : SeedTheme.textSecondary.opacity(0.4))
                        Text(rule)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SeedTheme.textPrimary)
                        Spacer()
                    }
                    .padding(13)
                    .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(selected == rule ? SeedTheme.violet : SeedTheme.band, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            TextField("직접 쓰기 — 예: 물타기 금지", text: $custom)
                .font(.system(size: 14))
                .padding(13)
                .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(custom.isEmpty ? SeedTheme.band : SeedTheme.violet, lineWidth: 1))
                .onChange(of: custom) { _, value in
                    if !value.isEmpty { selected = nil }
                }

            Spacer(minLength: 0)

            Button {
                let promise = custom.isEmpty ? selected : custom
                store.setSeasonRule(promise)
                dismiss()
            } label: {
                Text("이 약속으로 시작하기")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(promiseReady ? SeedTheme.violet : SeedTheme.textSecondary,
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!promiseReady)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .presentationDetents([.height(460)])
        .presentationBackground(SeedTheme.background)
    }

    private var promiseReady: Bool {
        selected != nil || !custom.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
