import SwiftUI

// MARK: - 배우기 탭: 레슨 목록 (M3-1)

struct LessonListView: View {
    let store: SeedStore
    @State private var activeLesson: LessonDef?
    @State private var showsDailyMarket = false
    @State private var showsGlossary = false
    @State private var summaryLesson: LessonDef?
    @State private var quiz: QuizQuestion?
    @State private var showsBotCompare = false
    @State private var showsQuantBuilder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("배우기")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("레슨을 마칠 때마다 시장 화면에 도구가 하나씩 열려요.")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)

                morningQuizCard
                dailyMarketCard
                if let practice = PracticeCatalog.todaysTask(store: store) {
                    PracticeCard(task: practice.task)
                }
                deepLinkListener

                // 하루 1레슨 페이스: 처음 3개는 자유, 이후 본편은 하루 1개
                let mainDoneCount = LessonCatalog.all.filter { store.isLessonDone($0.id) }.count
                let paceExhausted = mainDoneCount >= 3 && store.mainLessonsCompletedToday() >= 1
                ForEach(LessonCatalog.all) { lesson in
                    lessonRow(lesson, paceExhausted: paceExhausted)
                }

                // 심화 시리즈 — 책에서 배우는 것들. 잠금 없음, 읽기형.
                VStack(alignment: .leading, spacing: 4) {
                    Text("심화 시리즈")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                        .padding(.top, 10)
                    Text("책 한 권의 핵심을 몇 분 읽기로 — 순서 없이 아무 편이나")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
                ForEach(DeepDiveCatalog.all) { lesson in
                    deepDiveRow(lesson)
                }

                // 용어사전 — 막힌 단어만 바로 해소
                Button {
                    showsGlossary = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(SeedTheme.violetTint)
                                .frame(width: 38, height: 38)
                            Image(systemName: "character.book.closed.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SeedTheme.violetDeep)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("용어사전")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(SeedTheme.textPrimary)
                            Text("슬리피지? 평단? — 막힌 단어를 쉬운 말로")
                                .font(.system(size: 12))
                                .foregroundStyle(SeedTheme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(SeedTheme.textSecondary)
                    }
                    .padding(14)
                    .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                if store.isLessonDone(LessonCatalog.chase.id) {
                    botCompareCard
                    quantBuilderCard
                }

                Text("교육용 모의투자 · 실제 투자 권유가 아닙니다")
                    .font(.system(size: 10))
                    .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            .padding(16)
        }
        .background(SeedTheme.background)
        .fullScreenCover(item: $activeLesson) { lesson in
            LessonFlowView(lesson: lesson, store: store)
        }
        .sheet(isPresented: $showsGlossary) {
            GlossaryView()
        }
        .sheet(item: $quiz) { question in
            MorningQuizSheet(quiz: question)
        }
        .sheet(item: $summaryLesson) { lesson in
            LessonSummarySheet(lesson: lesson) {
                activeLesson = lesson
            }
        }
        .fullScreenCover(isPresented: $showsDailyMarket) {
            DailyMarketView(store: store)
        }
        .fullScreenCover(isPresented: $showsBotCompare) {
            BotCompareView(store: store)
        }
        .fullScreenCover(isPresented: $showsQuantBuilder) {
            QuantBuilderView(store: store)
        }
    }

    // MARK: 전략 실험실 (퀀트 빌더)

    private var quantBuilderCard: some View {
        Button {
            showsQuantBuilder = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(SeedTheme.violetTint)
                        .frame(width: 38, height: 38)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15))
                        .foregroundStyle(SeedTheme.violetDeep)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("전략 실험실")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    Text("조건을 조립해 백테스트 — RSI·이평 교차·돌파")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            .padding(14)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: 나 vs 봇 (⑫ — 레슨 3 완료 후 열린다)

    private var botCompareCard: some View {
        Button {
            showsBotCompare = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(SeedTheme.ink)
                        .frame(width: 38, height: 38)
                    Image(systemName: "tortoise.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(SeedTheme.violetOnDark)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("거장 도장 · 나 vs 거장들")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    Text("같은 급등장, 감정 없는 규칙은 어떻게 매매했을까")
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            .padding(14)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: 오늘의 장 (⑦ — 매일 다른 장이 열린다)

    private var deepLinkListener: some View {
        Color.clear
            .frame(height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .seedOpenDailyMarket)) { _ in
                if !store.isLessonDone(DailyMarket.id()) {
                    showsDailyMarket = true
                }
            }
    }

    /// 아침 복습 — 어제 배운 레슨 1문제 (하루 한 번, 간격 반복)
    @ViewBuilder
    private var morningQuizCard: some View {
        if !QuizRecord.doneToday, let question = QuizCatalog.todaysQuiz(store: store) {
            Button {
                quiz = question
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(SeedTheme.up.opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SeedTheme.up)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("아침 복습 · 1문제")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SeedTheme.textPrimary)
                        Text("배운 건 다음날 꺼내야 진짜 내 것이 돼요")
                            .font(.system(size: 12))
                            .foregroundStyle(SeedTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundStyle(SeedTheme.up)
                }
                .padding(14)
                .background(SeedTheme.up.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private var dailyMarketCard: some View {
        let doneToday = store.isLessonDone(DailyMarket.id())
        let streak = DailyMarket.streak(completed: store.completedLessonIds)
        let week = DailyMarket.lastSevenDays(completed: store.completedLessonIds)
        let patterns = DailyMarket.patternCounts(completed: store.completedLessonIds)

        return Button {
            if !doneToday { showsDailyMarket = true }
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(doneToday ? SeedTheme.card : SeedTheme.violet)
                            .frame(width: 38, height: 38)
                        Image(systemName: doneToday ? "checkmark" : "sunrise.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(doneToday ? SeedTheme.textSecondary : .white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("오늘의 장")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(SeedTheme.textPrimary)
                            if streak >= 2 {
                                Text("🔥 \(streak)일 연속")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(SeedTheme.violetDeep)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(SeedTheme.background, in: Capsule())
                            }
                        }
                        Text(doneToday ? "오늘 완료 · 내일 새로운 장이 열려요" : "오늘은 어떤 장일까요? 자유롭게 매매해보세요")
                            .font(.system(size: 12))
                            .foregroundStyle(SeedTheme.textSecondary)
                    }
                    Spacer()
                    if !doneToday {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(SeedTheme.violet)
                    }
                }

                // 최근 7일 점 캘린더 — 오늘이 맨 오른쪽
                HStack(spacing: 5) {
                    ForEach(Array(week.enumerated()), id: \.offset) { index, done in
                        Circle()
                            .fill(done ? SeedTheme.violet : SeedTheme.band)
                            .frame(width: 7, height: 7)
                            .overlay {
                                if index == week.count - 1 {
                                    Circle().stroke(SeedTheme.violetDeep.opacity(0.5), lineWidth: 1.5)
                                        .frame(width: 11, height: 11)
                                }
                            }
                    }
                    Text("최근 7일")
                        .font(.system(size: 10))
                        .foregroundStyle(SeedTheme.textSecondary)
                        .padding(.leading, 3)
                    Spacer()
                    // 겪어본 패턴 — 많이 겪은 순 상위 2개
                    if !patterns.isEmpty {
                        Text(patterns.prefix(2)
                            .map { "\($0.pattern.revealName) ×\($0.count)" }
                            .joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(SeedTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .background(SeedTheme.violetTint.opacity(doneToday ? 0.4 : 1),
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func lessonRow(_ lesson: LessonDef, paceExhausted: Bool = false) -> some View {
        let done = store.isLessonDone(lesson.id)
        let sequenceOpen = isAvailable(lesson)
        // 순서상 다음 차례지만 오늘 몫(1개)을 이미 쓴 경우 — 내일 예고
        let waitsForTomorrow = sequenceOpen && !done && paceExhausted
        let available = sequenceOpen && !waitsForTomorrow
        return Button {
            if done {
                summaryLesson = lesson
            } else if available {
                activeLesson = lesson
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(done ? SeedTheme.violet : (available ? SeedTheme.violetTint : SeedTheme.card))
                        .frame(width: 38, height: 38)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    } else if waitsForTomorrow {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(SeedTheme.violetDeep.opacity(0.7))
                    } else if available {
                        Text("\(lesson.order)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SeedTheme.violetDeep)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(available ? SeedTheme.textPrimary : SeedTheme.textSecondary)
                    Text(done ? lesson.unlockLabel + " 완료"
                         : (waitsForTomorrow
                            ? "내일 열려요 — 오늘 배운 걸 오늘의 장에서 먼저 써보세요"
                            : lesson.subtitle))
                        .font(.system(size: 12))
                        .foregroundStyle(waitsForTomorrow ? SeedTheme.violetDeep : SeedTheme.textSecondary)
                }
                Spacer()
                if !done && !waitsForTomorrow {
                    Text(lesson.duration)
                        .font(.system(size: 11))
                        .foregroundStyle(SeedTheme.textSecondary.opacity(0.8))
                }
            }
            .padding(14)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
            .opacity(available || done || waitsForTomorrow ? 1 : 0.65)
        }
        .buttonStyle(.plain)
    }

    /// 심화 시리즈 행 — 잠금 없음, 완료 체크만
    private func deepDiveRow(_ lesson: LessonDef) -> some View {
        let done = store.isLessonDone(lesson.id)
        return Button {
            if done { summaryLesson = lesson } else { activeLesson = lesson }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(done ? SeedTheme.card : SeedTheme.violetTint)
                        .frame(width: 38, height: 38)
                    Image(systemName: done ? "checkmark" : "book.pages.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(done ? SeedTheme.textSecondary : SeedTheme.violetDeep)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    Text(lesson.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
                Spacer()
                Text(lesson.duration)
                    .font(.system(size: 11))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            .padding(14)
            .background(SeedTheme.card.opacity(done ? 0.55 : 1),
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func isAvailable(_ lesson: LessonDef) -> Bool {
        guard let index = LessonCatalog.all.firstIndex(where: { $0.id == lesson.id }) else { return false }
        guard index > 0 else { return true }
        return store.isLessonDone(LessonCatalog.all[index - 1].id)
    }
}

// MARK: - 레슨 플로우: 개념 → 미션 → 완료·해금 (M3-1)

struct LessonFlowView: View {
    let lesson: LessonDef
    let store: SeedStore
    @Environment(\.dismiss) private var dismiss

    private enum Stage: Equatable {
        case concept(Int)
        case mission
        case done
    }
    @State private var stage: Stage = .concept(0)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("레슨 \(lesson.order) · \(lesson.duration)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SeedTheme.violetDeep)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 16)

            progressDots
                .padding(.top, 12)

            switch stage {
            case .concept(let index):
                ConceptPageView(
                    lesson: lesson,
                    page: lesson.concept[index],
                    isLast: index == lesson.concept.count - 1
                ) {
                    if index + 1 < lesson.concept.count {
                        stage = .concept(index + 1)
                    } else {
                        // 읽기형 레슨(심화 시리즈)은 미션 없이 완료
                        stage = lesson.mission == nil ? .done : .mission
                    }
                }
            case .mission:
                missionView
            case .done:
                LessonCompletionView(lesson: lesson) {
                    // 레벨 = 레슨 순번 (심화 시리즈 order 100+는 레벨과 무관)
                    store.completeLesson(lesson.id,
                                         unlocksLevel: lesson.order < 100 ? lesson.order : nil)
                    dismiss()
                }
            }
        }
        .background(SeedTheme.background)
        .interactiveDismissDisabled(stage == .mission)
        .onAppear { Analytics.log(.lessonStart, ["lessonId": lesson.id]) }
    }

    @ViewBuilder
    private var missionView: some View {
        switch lesson.mission ?? .tapBullish {
        case .tapBullish:
            TapBullishMissionView { stage = .done }
        case .slippageTutorial:
            SlippageMissionView { stage = .done }
        case .chaseScenario:
            ChaseScenarioMissionView(store: store) { stage = .done }
        case .tapVolumeSpike:
            TapVolumeSpikeMissionView { stage = .done }
        case .crashScenario:
            CrashScenarioMissionView(store: store) { stage = .done }
        case .diversification:
            DiversificationMissionView { stage = .done }
        case .valueTrap:
            ValueTrapMissionView { stage = .done }
        case .supportBounce:
            SupportBounceMissionView { stage = .done }
        case .stopLoss:
            StopLossMissionView { stage = .done }
        case .patience:
            PatienceMissionView { stage = .done }
        }
    }

    private var progressDots: some View {
        let total = lesson.concept.count + 2
        let position: Int
        switch stage {
        case .concept(let index): position = index
        case .mission: position = lesson.concept.count
        case .done: position = total - 1
        }
        return HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= position ? SeedTheme.violet : SeedTheme.band)
                    .frame(width: i == position ? 18 : 6, height: 4)
            }
        }
    }
}

// MARK: - 개념 카드

struct ConceptPageView: View {
    let lesson: LessonDef
    let page: ConceptPage
    let isLast: Bool
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(lesson.title)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
                .padding(.top, 22)

            Text(attributed(page.text))
                .font(.system(size: 15))
                .foregroundStyle(SeedTheme.textPrimary.opacity(0.85))
                .lineSpacing(5)
                .padding(.top, 12)

            conceptVisual
                .padding(.top, 16)

            Spacer()

            Button(action: onNext) {
                Text(isLast ? "미션 하러 가기" : "다음")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var conceptVisual: some View {
        switch page.visual {
        case .candleAnatomy: CandleAnatomyView()
        case .orderBookIntro: OrderBookIntroVisual()
        case .none, .fomoIntro: EmptyView()
        }
    }

    private func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

// MARK: - 캔들 해부도

struct CandleAnatomyView: View {
    var body: some View {
        HStack(spacing: 40) {
            anatomyCandle(color: SeedTheme.up, label: "양봉",
                          annotations: ["고가", "종가", "시가", "저가"])
            anatomyCandle(color: SeedTheme.down, label: "음봉",
                          annotations: ["고가", "시가", "종가", "저가"])
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func anatomyCandle(color: Color, label: String, annotations: [String]) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(annotations[0]).frame(height: 18, alignment: .top)
                Text(annotations[1]).frame(height: 22, alignment: .top)
                Spacer().frame(height: 30)
                Text(annotations[2]).frame(height: 22, alignment: .bottom)
                Text(annotations[3]).frame(height: 18, alignment: .bottom)
            }
            .font(.system(size: 10))
            .foregroundStyle(SeedTheme.textSecondary)

            VStack(spacing: 0) {
                Rectangle().fill(color).frame(width: 2, height: 18)
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 22, height: 52)
                Rectangle().fill(color).frame(width: 2, height: 18)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
                    .padding(.top, 5)
            }
        }
    }
}

// MARK: - 미션 1: 양봉을 탭하세요 (M3-2)

struct TapBullishMissionView: View {
    let onSuccess: () -> Void
    @State private var revealedCount = 0
    @State private var feedback: Feedback?
    @State private var succeeded = false

    private let candles = TapBullishMissionData.candles

    private struct Feedback {
        let text: String
        let positive: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundStyle(SeedTheme.violetOnDark)
                Text(revealedCount < candles.count
                     ? "캔들이 자라는 걸 지켜보세요…"
                     : "이 중에서 **양봉** 하나를 탭하세요")
                    .font(.system(size: 13))
            }
            .foregroundStyle(SeedTheme.inkText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(SeedTheme.ink, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20).padding(.top, 18)

            HStack(alignment: .bottom, spacing: 14) {
                ForEach(Array(candles.enumerated()), id: \.element.id) { index, candle in
                    MiniCandleView(candle: candle)
                        .opacity(index < revealedCount ? 1 : 0.08)
                        .animation(.easeOut(duration: 0.35), value: revealedCount)
                        .onTapGesture { tap(candle) }
                        .allowsHitTesting(revealedCount == candles.count && !succeeded)
                }
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .padding(.top, 28)

            if let feedback {
                Text(feedback.text)
                    .font(.system(size: 14))
                    .foregroundStyle(feedback.positive ? SeedTheme.violetDeep : SeedTheme.textPrimary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(feedback.positive ? SeedTheme.violetTint : SeedTheme.card,
                                in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20).padding(.top, 20)
            }

            Spacer()

            if succeeded {
                Button(action: onSuccess) {
                    Text("다음")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20).padding(.bottom, 18)
            }
        }
        .task {
            for i in 1...candles.count {
                try? await Task.sleep(for: .milliseconds(550))
                revealedCount = i
            }
        }
    }

    private func tap(_ candle: MiniCandle) {
        if candle.isBullish {
            succeeded = true
            feedback = Feedback(
                text: candle.hasLongUpperWick
                    ? "좋아요. 그런데 위꼬리 보이죠? 올랐다가 끝에 밀린 거예요 — 살 땐 이 흔적을 눈여겨봐요."
                    : "맞아요. 이 시간엔 산 사람들이 이겼어요.",
                positive: true
            )
        } else {
            feedback = Feedback(
                text: "이건 파랑, 내리며 끝난 시간이에요. 다시 빨강을 찾아볼까요?",
                positive: false
            )
        }
    }
}

/// 미니 캔들 1개 (미션·해부도 공용 스케일)
struct MiniCandleView: View {
    let candle: MiniCandle
    var priceMin = TapBullishMissionData.priceMin
    var priceMax = TapBullishMissionData.priceMax
    var height: CGFloat = 180

    var body: some View {
        let color = candle.isBullish ? SeedTheme.up : SeedTheme.down
        let unit = height / CGFloat(priceMax - priceMin)
        let bodyTop = CGFloat(priceMax - max(candle.open, candle.close)) * unit
        let bodyHeight = max(CGFloat(abs(candle.open - candle.close)) * unit, 3)
        let wickTop = CGFloat(priceMax - candle.high) * unit
        let wickHeight = CGFloat(candle.high - candle.low) * unit

        return ZStack(alignment: .top) {
            Rectangle()
                .fill(color)
                .frame(width: 2, height: wickHeight)
                .offset(y: wickTop)
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 26, height: bodyHeight)
                .offset(y: bodyTop)
        }
        .frame(width: 30, height: height, alignment: .top)
        .contentShape(Rectangle())
    }
}

// MARK: - 완료·해금 카드

struct LessonCompletionView: View {
    let lesson: LessonDef
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(SeedTheme.violet).frame(width: 58, height: 58)
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }
            Text(lesson.unlockLabel)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
                .padding(.top, 16)
            Text("시장 화면에서 바로 확인해보세요.")
                .font(.system(size: 14))
                .foregroundStyle(SeedTheme.textSecondary)
                .padding(.top, 6)
            Spacer()
            Button(action: onFinish) {
                Text("레슨 \(lesson.order) 완료")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(SeedTheme.violet, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20).padding(.bottom, 18)
        }
    }
}
