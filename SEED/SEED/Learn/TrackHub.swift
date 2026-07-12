import SwiftUI

// MARK: - 트랙 카탈로그 — 배우기 탭의 진열 단위
// 트랙 = 교과서 한 권. 탭에는 카드 1장으로 접히고, 목차는 상세 페이지로 들어간다.
// 트랙이 늘어도 배우기 탭에는 카드가 1장씩만 추가되는 구조.

struct TrackDef: Identifiable {
    enum Kind {
        /// 트랙 1 — 무료, 순서 잠금 + 하루 1레슨 페이스
        case main
        /// 트랙 2+ — 1편 무료, 이후 단품/Pro, 순서 잠금 (페이스 없음)
        case etf
        /// 출시 예정 — 카드로 존재만 알린다
        case comingSoon
    }

    let id: String
    let number: Int
    let title: String
    let subtitle: String
    let kind: Kind
    let lessons: [LessonDef]
    /// comingSoon 카드의 예고 문구
    var releaseNote: String? = nil

    func doneCount(store: SeedStore) -> Int {
        lessons.filter { store.isLessonDone($0.id) }.count
    }
}

enum TrackCatalog {
    static let stockBasics = TrackDef(
        id: "track.main",
        number: 1,
        title: "주식 기본기",
        subtitle: "캔들부터 자금 관리까지 — 12편",
        kind: .main,
        lessons: LessonCatalog.all
    )

    static let etf = TrackDef(
        id: "track.etf",
        number: 2,
        title: "ETF·분산투자",
        subtitle: "예측 없이 굴리는 구조 — 8편",
        kind: .etf,
        lessons: ETFTrackCatalog.all
    )

    static let crypto = TrackDef(
        id: "track.crypto",
        number: 3,
        title: "크립토 심화",
        subtitle: "24시간 시장의 제도와 심리",
        kind: .comingSoon,
        lessons: [],
        releaseNote: "출시 예정"
    )

    static let finance = TrackDef(
        id: "track.finance",
        number: 4,
        title: "금융 기초",
        subtitle: "금리·환율·채권, 시장의 배경지식",
        kind: .comingSoon,
        lessons: [],
        releaseNote: "출시 예정"
    )

    static let all: [TrackDef] = [stockBasics, etf, crypto, finance]
}

// MARK: - 이어서 배우기 — 다음 레슨 계산

enum NextLessonFinder {
    struct Candidate {
        let lesson: LessonDef
        let track: TrackDef
        /// 하루 1레슨 몫을 이미 써서 내일 열리는 상태
        var waitsForTomorrow = false
        /// 소장/Pro가 없어 페이월이 필요한 상태
        var needsPurchase = false
    }

    /// 우선순위: 트랙 1 다음 편 → (페이스 소진 시) 트랙 2 다음 편 → 완주면 nil.
    static func next(store: SeedStore, ownsETFTrack: Bool) -> Candidate? {
        let mainDone = TrackCatalog.stockBasics.doneCount(store: store)
        let paceExhausted = mainDone >= 3 && store.mainLessonsCompletedToday() >= 1

        let mainNext = TrackCatalog.stockBasics.lessons.first { !store.isLessonDone($0.id) }
        let etfNext = nextInETF(store: store, ownsETFTrack: ownsETFTrack)

        if let mainNext {
            if !paceExhausted {
                return Candidate(lesson: mainNext, track: TrackCatalog.stockBasics)
            }
            // 오늘 몫 소진 — 페이스 없는 트랙 2로 이어가거나, 내일 예고
            if let etfNext { return etfNext }
            return Candidate(lesson: mainNext, track: TrackCatalog.stockBasics,
                             waitsForTomorrow: true)
        }
        return etfNext
    }

    private static func nextInETF(store: SeedStore, ownsETFTrack: Bool) -> Candidate? {
        let lessons = TrackCatalog.etf.lessons
        guard let index = lessons.firstIndex(where: { !store.isLessonDone($0.id) }) else {
            return nil
        }
        let lesson = lessons[index]
        let reachable = ownsETFTrack || lesson.id == ETFTrackCatalog.freeLessonId
        return Candidate(lesson: lesson, track: TrackCatalog.etf,
                         needsPurchase: !reachable)
    }
}

// MARK: - 트랙 상세 — 목차 페이지 (기존 목록 행들이 여기로 이사)

struct TrackDetailView: View {
    let store: SeedStore
    let track: TrackDef
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var activeLesson: LessonDef?
    @State private var summaryLesson: LessonDef?
    @State private var showsTrackPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                progressBar

                ForEach(Array(track.lessons.enumerated()), id: \.element.id) { index, lesson in
                    switch track.kind {
                    case .main:
                        mainLessonRow(lesson)
                    case .etf:
                        etfLessonRow(lesson, index: index)
                    case .comingSoon:
                        EmptyView()
                    }
                }

                if track.kind == .main {
                    Text("레슨을 마칠 때마다 시장 도구가 하나씩 열려요 · 하루 1개")
                        .font(.system(size: 11))
                        .foregroundStyle(SeedTheme.textSecondary.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .background(SeedTheme.background)
        .fullScreenCover(item: $activeLesson) { lesson in
            LessonFlowView(lesson: lesson, store: store)
        }
        .sheet(item: $summaryLesson) { lesson in
            LessonSummarySheet(lesson: lesson) {
                activeLesson = lesson
            }
        }
        .sheet(isPresented: $showsTrackPaywall) {
            TrackPaywallSheet(purchases: purchases)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("트랙 \(track.number)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SeedTheme.violetDeep)
                Text(track.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SeedTheme.textPrimary)
                Text(subtitleText)
                    .font(.system(size: 12))
                    .foregroundStyle(SeedTheme.textSecondary)
            }
            Spacer()
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
        .padding(.top, 8)
    }

    private var subtitleText: String {
        switch track.kind {
        case .main: return "무료 · 순서대로, 하루 1레슨"
        case .etf: return purchases.ownsETFTrack
            ? "소장 중 · 순서대로, 원하는 페이스로"
            : "1편은 무료예요 — 지수·보수·적립식·리밸런싱"
        case .comingSoon: return track.releaseNote ?? ""
        }
    }

    private var progressBar: some View {
        let done = track.doneCount(store: store)
        let total = max(track.lessons.count, 1)
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SeedTheme.band)
                    Capsule().fill(SeedTheme.violet)
                        .frame(width: geo.size.width * CGFloat(done) / CGFloat(total))
                }
            }
            .frame(height: 6)
            Text(done == total ? "완주 — 축하해요" : "\(done)/\(total) 완료")
                .font(.system(size: 11))
                .foregroundStyle(SeedTheme.textSecondary)
        }
    }

    // MARK: 트랙 1 행 — 순서 잠금 + 하루 1레슨 페이스

    private func mainLessonRow(_ lesson: LessonDef) -> some View {
        let done = store.isLessonDone(lesson.id)
        let mainDone = track.doneCount(store: store)
        let paceExhausted = mainDone >= 3 && store.mainLessonsCompletedToday() >= 1
        let sequenceOpen = isSequenceOpen(lesson)
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

    // MARK: 트랙 2 행 — 1편 무료, 이후 소장/Pro + 순서 잠금

    private func etfLessonRow(_ lesson: LessonDef, index: Int) -> some View {
        let done = store.isLessonDone(lesson.id)
        let owned = purchases.ownsETFTrack || lesson.id == ETFTrackCatalog.freeLessonId
        let sequenceOpen = index == 0 || store.isLessonDone(track.lessons[index - 1].id)
        let available = owned && sequenceOpen
        return Button {
            if done {
                summaryLesson = lesson
            } else if !owned {
                showsTrackPaywall = true
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
                    } else if available {
                        Text("\(index + 1)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SeedTheme.violetDeep)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(SeedTheme.textSecondary.opacity(0.6))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(lesson.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(available || done ? SeedTheme.textPrimary : SeedTheme.textSecondary)
                        if index == 0 && !purchases.ownsETFTrack && !done {
                            Text("무료")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(SeedTheme.violetDeep)
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(SeedTheme.violetTint, in: Capsule())
                        }
                    }
                    Text(done ? lesson.unlockLabel + " 완료"
                         : (!owned ? "단품 소장 또는 Pro로 열려요" : lesson.subtitle))
                        .font(.system(size: 12))
                        .foregroundStyle(SeedTheme.textSecondary)
                }
                Spacer()
                if !done {
                    Text(lesson.duration)
                        .font(.system(size: 11))
                        .foregroundStyle(SeedTheme.textSecondary.opacity(0.8))
                }
            }
            .padding(14)
            .background(SeedTheme.card, in: RoundedRectangle(cornerRadius: 14))
            .opacity(available || done || !owned ? 1 : 0.65)
        }
        .buttonStyle(.plain)
    }

    private func isSequenceOpen(_ lesson: LessonDef) -> Bool {
        guard let index = track.lessons.firstIndex(where: { $0.id == lesson.id }) else { return false }
        guard index > 0 else { return true }
        return store.isLessonDone(track.lessons[index - 1].id)
    }
}

// MARK: - 라이브러리 — 순서 없는 것들의 서가

struct LibraryView: View {
    let store: SeedStore
    @Environment(\.dismiss) private var dismiss
    @State private var activeLesson: LessonDef?
    @State private var summaryLesson: LessonDef?
    @State private var showsTutor = false
    @State private var showsGlossary = false
    @State private var showsBotCompare = false
    @State private var showsQuantBuilder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("라이브러리")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(SeedTheme.textPrimary)
                        Text("순서 없이, 언제든 꺼내 읽는 것들")
                            .font(.system(size: 12))
                            .foregroundStyle(SeedTheme.textSecondary)
                    }
                    Spacer()
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
                .padding(.top, 8)

                if store.isLessonDone(LessonCatalog.chase.id) {
                    toolCard(title: "거장 도장 · 나 vs 거장들",
                             subtitle: "같은 급등장, 감정 없는 규칙은 어떻게 매매했을까",
                             icon: "tortoise.fill", dark: true) {
                        showsBotCompare = true
                    }
                    toolCard(title: "전략 실험실",
                             subtitle: "조건을 조립해 백테스트 — RSI·이평 교차·돌파",
                             icon: "slider.horizontal.3") {
                        showsQuantBuilder = true
                    }
                }
                toolCard(title: "AI 튜터",
                         subtitle: "ETF? 배당? — 궁금한 금융 기초를 직접 물어보세요",
                         icon: "graduationcap.fill") {
                    showsTutor = true
                }
                toolCard(title: "용어사전",
                         subtitle: "슬리피지? 평단? — 막힌 단어를 쉬운 말로",
                         icon: "character.book.closed.fill") {
                    showsGlossary = true
                }

                sectionLabel("심화 읽기", subtitle: "책에서 배우는 것들을 쉬운 말로")
                ForEach(DeepDiveCatalog.all) { lesson in
                    deepDiveRow(lesson)
                }
            }
            .padding(16)
        }
        .background(SeedTheme.background)
        .fullScreenCover(item: $activeLesson) { lesson in
            LessonFlowView(lesson: lesson, store: store)
        }
        .sheet(item: $summaryLesson) { lesson in
            LessonSummarySheet(lesson: lesson) {
                activeLesson = lesson
            }
        }
        .sheet(isPresented: $showsTutor) { TutorView() }
        .sheet(isPresented: $showsGlossary) { GlossaryView() }
        .fullScreenCover(isPresented: $showsBotCompare) {
            BotCompareView(store: store)
        }
        .fullScreenCover(isPresented: $showsQuantBuilder) {
            QuantBuilderView(store: store)
        }
    }

    private func sectionLabel(_ title: String, subtitle: String?) -> some View {
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

    private func toolCard(title: String, subtitle: String, icon: String,
                          dark: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(dark ? SeedTheme.ink : SeedTheme.violetTint)
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(dark ? SeedTheme.violetOnDark : SeedTheme.violetDeep)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SeedTheme.textPrimary)
                    Text(subtitle)
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
}
