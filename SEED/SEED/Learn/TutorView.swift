import SwiftUI

/// AI 튜터 — 금융 기초를 묻는 채팅. 필터·직답은 무료(0토큰), 지식 답변만 쿼터 차감.
struct TutorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseStore.self) private var purchases
    @State private var showsRefill = false

    private struct ChatItem: Identifiable {
        let id = UUID()
        let role: String   // "user" | "assistant"
        let content: String
        var countsAgainstQuota = false
    }

    @State private var items: [ChatItem] = []

    private let starterQuestions = [
        "ETF가 뭐야?",
        "배당은 언제, 어떻게 받아?",
        "공매도가 뭐야?",
        "비트코인은 주식이랑 뭐가 달라?",
        "PER이랑 PBR 차이가 뭐야?"
    ]
    @State private var input = ""
    @State private var isThinking = false
    @State private var quotaLeft = TutorQuota.remaining

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        if items.isEmpty {
                            emptyState
                        }
                        ForEach(items) { item in
                            bubble(item)
                        }
                        if isThinking {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("생각하는 중…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SeedTheme.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: items.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }

            inputBar
        }
        .background(SeedTheme.background)
        .sheet(isPresented: $showsRefill) {
            RefillSheet(purchases: purchases, source: "tutor_quota")
                .onDisappear { quotaLeft = TutorQuota.remaining }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(SeedTheme.violet).frame(width: 34, height: 34)
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("AI 튜터")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("금융 기초 질문 · 추천/예측은 안 해요")
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            Spacer()
            if quotaLeft <= 5 {
                Text("남은 질문 \(quotaLeft)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(quotaLeft == 0 ? SeedTheme.down : SeedTheme.textSecondary)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SeedTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(SeedTheme.card, in: Circle())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(SeedTheme.violetTint).frame(width: 64, height: 64)
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(SeedTheme.violet)
            }
            .padding(.top, 28)
            Text("금융 기초, 뭐든 물어보세요")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
            Text("주식·ETF·비트코인의 개념을 쉽게 풀어드려요.\n종목 추천과 가격 예측은 하지 않아요.")
                .font(.system(size: 13))
                .foregroundStyle(SeedTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Text("질문은 답변 생성을 위해 AI 서버로 전송돼요")
                .font(.system(size: 11))
                .foregroundStyle(SeedTheme.textSecondary.opacity(0.7))

            VStack(spacing: 7) {
                ForEach(starterQuestions, id: \.self) { question in
                    Button {
                        input = question
                        send()
                    } label: {
                        HStack {
                            Text(question)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(SeedTheme.violetDeep)
                            Spacer()
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(SeedTheme.violet.opacity(0.6))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(SeedTheme.violetTint.opacity(0.6),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
    }

    private func bubble(_ item: ChatItem) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if item.role == "user" {
                Spacer(minLength: 48)
            } else {
                ZStack {
                    Circle().fill(SeedTheme.violet).frame(width: 24, height: 24)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                }
            }
            Text((try? AttributedString(
                markdown: item.content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(item.content))
                .font(.system(size: 14))
                .foregroundStyle(item.role == "user" ? .white : SeedTheme.textPrimary)
                .lineSpacing(4)
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(item.role == "user" ? SeedTheme.violet : SeedTheme.card,
                            in: UnevenRoundedRectangle(
                                topLeadingRadius: 16,
                                bottomLeadingRadius: item.role == "user" ? 16 : 4,
                                bottomTrailingRadius: item.role == "user" ? 4 : 16,
                                topTrailingRadius: 16))
            if item.role != "user" { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 16)
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if !TutorService.isConfigured {
                Text("튜터 서버 준비 중이에요 — 용어 정의 질문은 지금도 답해드려요.")
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.textSecondary)
            } else if quotaLeft == 0 {
                Button {
                    showsRefill = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 12))
                        Text("질문 리필하기 · Pro 알아보기")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(SeedTheme.violetDeep)
                }
            }
            HStack(spacing: 8) {
                TextField("예: ETF가 뭐야?", text: $input, axis: .vertical)
                    .font(.system(size: 14))
                    .lineLimit(1...3)
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(canSend ? SeedTheme.violet : SeedTheme.textSecondary,
                                    in: Circle())
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespaces).isEmpty && !isThinking
    }

    private func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }
        input = ""
        items.append(.init(role: "user", content: question))

        // ① 규칙 필터 — 0토큰 거절
        if let refusal = TutorService.refusal(for: question) {
            items.append(.init(role: "assistant", content: refusal))
            return
        }
        // ② 용어사전 직답 — 0토큰
        if let direct = TutorService.glossaryAnswer(for: question) {
            items.append(.init(role: "assistant",
                               content: direct + "\n\n(용어사전에서 바로 찾아드렸어요 — 더 깊은 질문도 환영이에요.)"))
            return
        }
        // ③ 클라우드 — 쿼터 차감
        guard TutorService.isConfigured else {
            items.append(.init(role: "assistant",
                               content: "지식 답변 서버가 아직 준비 중이에요. 용어 뜻은 지금도 물어볼 수 있어요 — 예: \u{201C}슬리피지가 뭐야?\u{201D}"))
            return
        }
        guard TutorQuota.remaining > 0 else {
            items.append(.init(role: "assistant",
                               content: "체험 질문을 모두 사용했어요. 아래 '질문 리필하기'로 이어갈 수 있어요 — 용어 뜻 질문은 계속 무료예요!"))
            showsRefill = true
            return
        }

        isThinking = true
        let history = items.map { TutorService.Message(role: $0.role, content: $0.content) }
        Task {
            defer { isThinking = false }
            do {
                let answer = try await TutorService.ask(history: history)
                TutorQuota.consume()
                quotaLeft = TutorQuota.remaining
                items.append(.init(role: "assistant", content: answer, countsAgainstQuota: true))
            } catch TutorService.TutorError.serverLimit {
                items.append(.init(role: "assistant", content: "오늘은 질문이 너무 많았어요 — 내일 다시 물어봐 주세요."))
            } catch {
                items.append(.init(role: "assistant", content: "지금은 연결이 원활하지 않아요. 잠시 뒤 다시 시도해 주세요."))
            }
        }
    }
}
