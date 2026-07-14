import SwiftUI

// MARK: - 배우기 탭: 레슨 목록 (M3-1)

struct LessonListView: View {
    let store: SeedStore
    @Environment(PurchaseStore.self) private var purchases
    @State private var showsTrackPaywall = false
    @State private var activeLesson: LessonDef?
    @State private var showsDailyMarket = false
    @State private var quiz: QuizQuestion?
    @State private var selectedTrack: TrackDef?
    @State private var showsLibrary = false
    @State private var showsChallengeArena = false
    @State private var showsChallengeRematch = false
    @State private var showsChallengeLab = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("배우기")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)

                // ── 오늘의 루틴: 복습 → 레슨 → 오늘의 장, 카드 한 장에 (하루 3탭)
                // (다음 레슨·퀴즈 계산은 SwiftData fetch를 동반하므로 렌더당 1회만)
                let next = NextLessonFinder.next(store: store,
                                                 ownsETFTrack: purchases.ownsETFTrack)
                let todaysQuiz = QuizCatalog.todaysQuiz(store: store)
                let quizDone = QuizRecord.doneToday
                let dailyDone = store.isLessonDone(DailyMarket.id())
                routineCard(next, todaysQuiz: todaysQuiz,
                            quizDone: quizDone, dailyDone: dailyDone)

                // ── 오늘의 도전: 루틴을 끝낸 사람에게만 "이제 놀 것"을 건넨다
                let lessonDone = next == nil || next?.waitsForTomorrow == true
                if dailyDone && lessonDone && (todaysQuiz == nil || quizDone)
                    && store.isLessonDone(LessonCatalog.chase.id) {
                    challengeCard
                }
                deepLinkListener

                // ── 트랙: 교과서 진열대 — 목차는 카드 안으로
                sectionHeader("트랙", subtitle: "한 트랙 = 한 주제 · 탭해서 목차 열기")
                ForEach(TrackCatalog.all) { track in
                    trackCard(track, isCurrent: next?.track.id == track.id)
                }

                // ── 라이브러리: 순서 없는 것들은 한 장으로
                libraryCard

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
        .sheet(item: $selectedTrack) { track in
            TrackDetailView(store: store, track: track)
                .environment(purchases)
        }
        .sheet(isPresented: $showsLibrary) {
            LibraryView(store: store)
        }
        .sheet(isPresented: $showsTrackPaywall) {
            TrackPaywallSheet(purchases: purchases, source: "learn_hero")
        }
        .sheet(item: $quiz) { question in
            MorningQuizSheet(quiz: question)
        }
        .fullScreenCover(isPresented: $showsDailyMarket) {
            DailyMarketView(store: store)
        }
        .fullScreenCover(isPresented: $showsChallengeArena) {
            ArenaView()
        }
        .fullScreenCover(isPresented: $showsChallengeRematch) {
            BotCompareView(store: store)
        }
        .fullScreenCover(isPresented: $showsChallengeLab) {
            QuantBuilderView(store: store)
        }
    }

    // MARK: 오늘의 도전 — 요일 로테이션으로 기존 깊이 콘텐츠를 순환 노출

    private struct DailyChallengeDef {
        let title: String
        let subtitle: String
        let icon: String
        let kind: Kind
        enum Kind { case arena, rematch, lab }
    }

    /// 일~토 (Calendar.weekday 1~7)
    private static let weekdayChallenges: [DailyChallengeDef] = [
        .init(title: "일요 아레나 — 거장 5인과 한 판",
              subtitle: "한 주의 마무리, 무작위 장에서 승부", icon: "trophy.fill", kind: .arena),
        .init(title: "전략 실험실 — 규칙 하나 검증하기",
              subtitle: "감이 아니라 백테스트로 한 주를 시작", icon: "slider.horizontal.3", kind: .lab),
        .init(title: "거장 도장 — 그 장을 다시",
              subtitle: "같은 장, 같은 거장 — 이번엔 이길 차례", icon: "tortoise.fill", kind: .rematch),
        .init(title: "수요 아레나 — 중간 점검",
              subtitle: "이번 주의 감, 거장들 상대로 확인", icon: "trophy.fill", kind: .arena),
        .init(title: "실험실 — 모든 장에서 시험하기",
              subtitle: "내 전략은 어느 계절 옷일까", icon: "slider.horizontal.3", kind: .lab),
        .init(title: "거장 도장 — 약한 장 정복",
              subtitle: "전적이 나쁜 장을 골라 리매치", icon: "tortoise.fill", kind: .rematch),
        .init(title: "토요 아레나 — 전적 쌓기",
              subtitle: "주말의 여유, 한 판 더", icon: "trophy.fill", kind: .arena)
    ]

    private var challengeCard: some View {
        let weekday = Calendar.current.component(.weekday, from: .now)
        let challenge = Self.weekdayChallenges[(weekday - 1) % Self.weekdayChallenges.count]
        return Button {
            switch challenge.kind {
            case .arena: showsChallengeArena = true
            case .rematch: showsChallengeRematch = true
            case .lab: showsChallengeLab = true
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(SeedTheme.violetTint)
                        .frame(width: 38, height: 38)
                    Image(systemName: challenge.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SeedTheme.violetDeep)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("오늘의 도전")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SeedTheme.violetDeep)
                    Text(challenge.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    Text(challenge.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SeedTheme.violetDeep)
            }
            .padding(14)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(SeedTheme.violet, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }

    // MARK: 오늘의 루틴 — 하루 할 일을 카드 한 장에 (복습 → 레슨 → 오늘의 장)
    // 오늘의 실천은 독립 카드에서 내려와 "오늘의 장" 행의 서브텍스트가 됐다:
    // 실천은 할 일이 아니라 오늘의 장을 할 때 지킬 것이라서.

    @ViewBuilder
    private func routineCard(_ next: NextLessonFinder.Candidate?,
                             todaysQuiz: QuizQuestion?,
                             quizDone: Bool,
                             dailyDone: Bool) -> some View {
        let streak = DailyMarket.streak(completed: store.completedLessonIds)
        let practiceLine = PracticeCatalog.todaysTask(store: store)?.task

        // 보이는 행 수와 완료 수 — 복습은 복습거리가 있을 때만, 레슨은 완주 전까지만
        let rowCount = (todaysQuiz != nil ? 1 : 0) + (next != nil ? 1 : 0) + 1
        let doneCount = (todaysQuiz != nil && quizDone ? 1 : 0)
            + (next?.waitsForTomorrow == true ? 1 : 0)
            + (dailyDone ? 1 : 0)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("오늘의 루틴")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text("\(doneCount)/\(rowCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SeedTheme.violetDeep)
                Spacer()
                if streak >= 2 {
                    Text("🔥 \(streak)일 연속")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SeedTheme.violetDeep)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(SeedTheme.violetTint, in: Capsule())
                }
            }
            .padding(.bottom, 4)

            if let todaysQuiz {
                routineRow(icon: "sparkles",
                           title: "아침 복습 1문제",
                           subtitle: quizDone ? nil : "배운 건 다음날 꺼내야 내 것이 돼요",
                           done: quizDone) {
                    quiz = todaysQuiz
                }
                Divider().padding(.vertical, 2)
            }

            if let next {
                routineRow(icon: next.needsPurchase ? "lock.fill" : "play.fill",
                           title: next.waitsForTomorrow
                               ? "오늘 레슨 완료"
                               : "다음 레슨 — \(next.lesson.title)",
                           subtitle: next.waitsForTomorrow
                               ? "내일 이어져요 — 배운 걸 오늘의 장에서 써보세요"
                               : (next.needsPurchase
                                  ? "단품 소장 또는 Pro로 이어가기"
                                  : "트랙 \(next.track.number) · \(next.lesson.duration)"),
                           done: next.waitsForTomorrow) {
                    if next.needsPurchase {
                        showsTrackPaywall = true
                    } else {
                        activeLesson = next.lesson
                    }
                }
                Divider().padding(.vertical, 2)
            }

            routineRow(icon: "sunrise.fill",
                       title: "오늘의 장 한 판",
                       subtitle: dailyDone
                           ? "오늘 완료 — 내일 새로운 장이 열려요"
                           : (practiceLine.map { "오늘의 실천: \($0)" } ?? "오늘은 어떤 장일까요?"),
                       done: dailyDone) {
                showsDailyMarket = true
            }
        }
        .padding(14)
        .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(SeedTheme.violet.opacity(0.35), lineWidth: 1.2))
    }

    private func routineRow(icon: String, title: String, subtitle: String?,
                            done: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard !done else { return }
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: done ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(done ? SeedTheme.violet : SeedTheme.violetDeep)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(done ? SeedTheme.textSecondary : SeedTheme.textPrimary)
                        .strikethrough(done, color: SeedTheme.textSecondary.opacity(0.6))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(SeedTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if !done {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(SeedTheme.textSecondary.opacity(0.7))
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 트랙 카드 — 제목 + 진행률만, 목차는 상세로

    @ViewBuilder
    private func trackCard(_ track: TrackDef, isCurrent: Bool) -> some View {
        let done = track.doneCount(store: store)
        let total = track.lessons.count
        let isComingSoon = track.kind == .comingSoon
        Button {
            guard !isComingSoon else { return }
            selectedTrack = track
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    if isComingSoon {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    }
                    Text("트랙 \(track.number) · \(track.title)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isComingSoon ? SeedTheme.textSecondary : SeedTheme.textPrimary)
                    Spacer()
                    if isComingSoon {
                        Text(track.releaseNote ?? "")
                            .font(.system(size: 11))
                            .foregroundStyle(SeedTheme.textSecondary.opacity(0.8))
                    } else if done == total {
                        Text("졸업")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SeedTheme.up)
                    } else if track.kind == .etf && !purchases.ownsETFTrack {
                        Text("1편 무료")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(SeedTheme.violetDeep)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(SeedTheme.violetTint, in: Capsule())
                    } else {
                        Text("\(done)/\(total)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SeedTheme.violetDeep)
                    }
                }
                Text(track.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
                if !isComingSoon {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(SeedTheme.band)
                            Capsule()
                                .fill(done == total ? SeedTheme.up : SeedTheme.violet)
                                .frame(width: geo.size.width * CGFloat(done) / CGFloat(max(total, 1)))
                        }
                    }
                    .frame(height: 5)
                }
            }
            .padding(14)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(SeedTheme.violet.opacity(0.6), lineWidth: 1.2)
                }
            }
            .opacity(isComingSoon ? 0.7 : 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: 라이브러리 카드 — 서가로 가는 문

    private var libraryCard: some View {
        Button {
            showsLibrary = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(SeedTheme.violetTint)
                        .frame(width: 38, height: 38)
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SeedTheme.violetDeep)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("라이브러리")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    Text(store.isLessonDone(LessonCatalog.chase.id)
                         ? "심화 읽기 · 거장 도장 · 실험실 · 튜터 · 용어사전"
                         : "심화 읽기 · AI 튜터 · 용어사전")
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
            .onReceive(NotificationCenter.default.publisher(for: .seedOpenETFTrack)) { _ in
                // 레슨 커버가 닫히는 애니메이션과 겹치지 않게 반 박자 늦춰 연다
                Task {
                    try? await Task.sleep(for: .seconds(0.6))
                    selectedTrack = TrackCatalog.etf
                }
            }
    }

    private func sectionHeader(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SeedTheme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
        }
        .padding(.top, 12)
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

    /// 현재 단계의 이전 단계 — 첫 페이지와 완료 화면에서는 없다.
    private var previousStage: Stage? {
        switch stage {
        case .concept(let index):
            return index > 0 ? .concept(index - 1) : nil
        case .mission:
            return .concept(lesson.concept.count - 1)
        case .done:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // 심화·트랙 시리즈(order 100+)는 번호 대신 소요 시간만
                // 뒤로가기 — "양봉이 뭐였지?" 하는 순간 앞 페이지로 돌아가 확인할 수 있게.
                // 미션에서 누르면 마지막 개념 페이지로 (미션은 돌아오면 처음부터 다시).
                if let previous = previousStage {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { stage = previous }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SeedTheme.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(SeedTheme.card, in: Circle())
                    }
                }
                Text(lesson.order < 100 ? "레슨 \(lesson.order) · \(lesson.duration)" : lesson.duration)
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
                // 졸업 직후 + 트랙 2를 아직 시작 안 했을 때만 다음 여정 CTA
                let promotesTrackTwo = lesson.id == LessonCatalog.graduation.id
                    && !store.isLessonDone(ETFTrackCatalog.what.id)
                LessonCompletionView(
                    lesson: lesson,
                    showsTrackPromo: promotesTrackTwo,
                    onTrackPromo: promotesTrackTwo ? {
                        Analytics.log(.trackPromoTapped, ["source": "graduation"])
                        completeAndDismiss()
                        NotificationCenter.default.post(name: .seedOpenETFTrack, object: nil)
                    } : nil
                ) {
                    completeAndDismiss()
                }
            }
        }
        .background(SeedTheme.background)
        .interactiveDismissDisabled(stage == .mission)
        .onAppear { Analytics.log(.lessonStart, ["lessonId": lesson.id]) }
    }

    /// 레벨 = 레슨 순번 (심화·트랙 시리즈 order 100+는 레벨과 무관)
    private func completeAndDismiss() {
        store.completeLesson(lesson.id,
                             unlocksLevel: lesson.order < 100 ? lesson.order : nil)
        if lesson.id == LessonCatalog.graduation.id {
            ReviewPrompt.askIfEligible(.graduation)
        }
        dismiss()
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
        case .positionSizing:
            PositionSizingMissionView { stage = .done }
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
        SeedMarkdown.bold(text, size: 15, boldColor: SeedTheme.textPrimary)
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
    /// 졸업(레슨 12) 완료 화면에서만: 트랙 2로 잇는 CTA.
    /// 트랙 1을 완주한 직후가 다음 여정에 대한 의지가 가장 높은 순간이다.
    var showsTrackPromo = false
    var onTrackPromo: (() -> Void)? = nil
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
            if showsTrackPromo, let onTrackPromo {
                Button(action: onTrackPromo) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(SeedTheme.violetTint)
                                .frame(width: 38, height: 38)
                            Image(systemName: "basket.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SeedTheme.violetDeep)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("다음 여정 — 트랙 2 · ETF·분산투자")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(SeedTheme.textPrimary)
                            Text("종목을 고르지 않는 투자 · 1편은 무료예요")
                                .font(.system(size: 12))
                                .foregroundStyle(SeedTheme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SeedTheme.violetDeep)
                    }
                    .padding(14)
                    .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(SeedTheme.violet.opacity(0.5), lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20).padding(.bottom, 10)
            }
            Button(action: onFinish) {
                Text(lesson.order < 100 ? "레슨 \(lesson.order) 완료" : "완료")
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
