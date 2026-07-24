# SEED — 주린이 모의투자 학습 앱 (작업 인수인계)

> 이 문서는 새 세션의 컨텍스트 복원용. 여기 없는 세부는 git log와 코드 주석에 있음.

## 프로젝트 정체성
- **가상 합성 시장**(실데이터 없음)에서 주식 습관을 훈련하는 iOS 앱. 철학: "가상 데이터로 꾸준히 연습하면 지표를 보는 눈이 생긴다."
- §11 가드레일: 종목 추천·가격 예측·수익 보장 금지, 광고 없음, 무가입, 정직한 카피.
- 디자인: 토스 증권 문법 + 아크 바이올렛 #6B4EFF (브랜드 전용, 손익엔 금지). 상승 #F04452 / 하락 #3182F6 고정.

## 구조
- `JurinKit/` — 엔진 SPM 패키지 (호가창 매칭, 에이전트 4종, 시나리오, 거장 봇 5종, **테스트 89개** `swift test`)
- `SEED/` — iOS 앱 (Xcode 26, **타깃 iOS 18**, MV 패턴 — 뷰모델 없음, SwiftData+CloudKit)
  - `SEED/App|Core|Market|Learn|Review|Portfolio|Design|Onboarding/` + `SEEDWidget/`(위젯 익스텐션)
- `server/tutor-worker.js` — 튜터 프록시 (Cloudflare Workers, 배포됨)

## Git 규칙 (엄수)
- develop에서 `feat/fix/*` 분기 → `--no-ff` 병합 → develop·브랜치 push. main은 사용자 지시 시만 승격. release는 미사용.
- **커밋에 Claude 흔적 금지** — Co-Authored-By 트레일러 없이, 작성자 whahdoIsa만.
- 커밋 메시지 한국어, 매 기능마다 빌드 검증 후 커밋.

## 빌드·검증 루프
```bash
# 시뮬레이터 UUID: BCE6E6D4-D5EF-4DF6-B88E-F0FC62334450 (iPhone 17, iOS 26.4) / SE: 7FD35E2C-5D9E-4496-BFEF-D439CAE748C5
cd SEED && xcodebuild -project SEED.xcodeproj -scheme SEED -destination 'platform=iOS Simulator,id=BCE6...' -derivedDataPath build build
xcrun simctl install <UUID> build/Build/Products/Debug-iphonesimulator/SEED.app && xcrun simctl launch <UUID> kr.arcseed.SEED
# 스크린샷 검증: 임시로 RootView body에 대상 뷰 직행 → 캡처 → git checkout -- 로 원복 (기존 패턴)
cd JurinKit && swift test   # 엔진 변경 시 필수
```

## 완성된 기능 (전부 main 반영)
- **시장**: 6종목(한빛전자·중공업·바이오·식품·골드·비트씨) 공유원장, β 상관관계, 제도팩(수수료·세금·상하한가·거래일·동시호가), 뉴스 84종, 지정가/미체결, 토스식 상세차트+핀치줌+전체화면(회전), 세션 연속성(리플레이, 30만 스텝 초과 시 타임라인 리셋 — 계좌를 Season.ledgerBaselineData(CloudKit 동기화)에 베이스라인으로 못박고 timelineEpoch +1, 이후 매매만 리플레이. LedgerSnapshot(UserDefaults)은 시드 XOR 지문 일치 시만 신뢰. 재설치 시 임포트 도착하면 RootView가 session.adoptRemoteStateIfNeeded()로 원장·엔진 재구성 — 시드 불일치가 신호)
- **배우기**: 본편 12편 완결(하루 1레슨, 첫 3개 자유) + 심화 6편(터틀3·퀀트3) + 용어사전 41 + 요약카드 + 아침퀴즈 + 오늘의실천. 3섹션(오늘/커리큘럼/라이브러리). 레벨=완료 레슨 수, 도구해금 Lv1캔들/2호가/4거래량/5전체
- **오늘의 장**: 날짜시드 패턴 5종, 스트릭+7일 점, 공유카드. **아레나**: 무작위 장 나vs거장5+내전략, 라이브 순위, 전적. **거장 도장**: 5인 프로필(데니스·그레이엄·오닐·코스톨라니·템플턴)×장4종, 매매일지(이유 포함), 리매치. **전략 실험실**: 3템플릿+가치스크리너+장별성적표+아레나 출전 슬롯
- **복기**: 태그·매매지도·보유습관(FIFO 페어링)·부검·시즌 아카이브(성장그래프, Pro게이트)
- **인프라**: iCloud 백업(복원 병합 refreshAfterRemoteImport), 홈/잠금 위젯(App Group+딥링크 seed://daily), 로컬 알림 4종(아침 08시 루틴·저녁 20시 오늘의장 리마인더[7일 개별 예약, 완료 시 당일 취소]·일 19시 주간 복기·**체결 영수증**[시장 탭+ETF의 사용자 체결 즉시 "🧾 한빛전자 100주 매수 체결 · 주당/총액", 게임 모드는 제외, 포그라운드 배너는 SeedNotificationDelegate] — 기본 전부 켬, 설정 토글), 설정 화면, 앱아이콘/런치(런치 화면=바이올렛 #6B4EFF 풀스크린+새싹/SEED/투자 연습장 락업 이미지 LaunchLockup, 인앱 오버레이는 두지 않음 — 캐시 어긋난 기기에서 반짝임을 만들어 제거했음(실기기 확인). 주의: 런치 화면은 iOS가 캐시해 기존 설치 기기엔 옛것이 보일 수 있음 — 재부팅·신규 설치로 갱신), 접근성 요약, 하루1레슨 페이스
- **배우기 탭 = 트랙 허브 구조 (develop)**: "오늘의 루틴" 카드 1장(아침 복습·다음 레슨·오늘의 장 체크리스트 — 오늘의 실천은 오늘의 장 행 서브텍스트로 흡수, PracticeCard/PracticeRecord 삭제) + 다음 레슨 계산 히어로 카드(`Learn/TrackHub.swift`의 NextLessonFinder — 트랙1 다음 편 → 페이스 소진 시 트랙2 → 완주 시 예고 카드) + 트랙 카드 4장(1 주식기본기·2 ETF·3 크립토 예정·4 금융기초 예정, 진행률 바·진행 중 보라 테두리·미소유 "1편 무료" 배지) + 라이브러리 카드 1장. 레슨 목차는 `TrackDetailView` 시트로, 심화·도장·실험실·튜터·용어사전은 `LibraryView` 시트로 이사. 트랙 추가 시 `TrackCatalog.all`에 TrackDef 1개만 추가하면 됨.
- **트랙 2 — ETF·분산투자 (develop, Phase 3 완료)**: `JurinKit/ETFFund.swift`(고정 좌수 바스켓 NAV + 연보수/252 일할 차감, 테스트 13개 — 총 102개), ETF 2종(`Core/ETFCatalog.swift` — HIX 한빛300 지수 0.15% / HBA 균형 자산배분 0.35%, BTX 제외), NAV 즉시 체결(호가창 없음·매도 거래세 없음), MarketSession 통합(리플레이·스냅샷·totalEquity·분산 β 반영), `Market/ETFMarketView.swift`(NAV 라인차트·구성·보수 누적 카드·주문 시트), 레슨 8편 `Learn/ETFTrack.swift`(order 201+, 읽기형, 1편 무료→순서 잠금, 하루 페이스 없음) + 요약·퀴즈·실천·용어사전 8종("ETF·분산투자" 카테고리). 진입: 시장 탭 ETF 칩 + 배우기 트랙 2 섹션, 비소유 시 `Learn/TrackPaywallSheet.swift`

- **UX 폴리시 (develop=main)**: 주문시트(예상 주문/매도 금액 실시간·보유 N주·평단·매도 '전부' 버튼·매도 스테퍼 상한·500주 프리셋 제거), 시장 스트립 보유 평가금액(주 수는 라벨로), 복기 습관분석 분리(사는 이유=분포 보라 바 / 파는 이유=확정 성적 손익 바 — 그냥감 중복·빈막대 해소), 레슨 뒤로가기(개념·미션 간), 본문 볼드 `Design/SeedMarkdown.swift`(CommonMark 한국어 조사 문제로 ** 직접 파싱)

## AI 스택 (Phase 1 완료 — 검증됨)
- **온디바이스 (Foundation Models, iOS 26)**: `Core/AICoach.swift` — 주간복기·부검·오늘의장·아레나 해설. 캐시(키+지문, "같은 데이터에 두 번 안 묻기"), 미지원기기(iPhone 15 Pro 미만)→룰기반 폴백. **실기기 검증 아직 안 함** (시뮬은 미지원 정상).
- **튜터 (Haiku)**: 3겹 — ①규칙필터(추천·예측 거절, 0토큰) ②용어사전 직답(0토큰) ③`claude-haiku-4-5-20251001` via Cloudflare Worker `https://seed-tutor.throbbing-sun-9e1e.workers.dev/` (배포·크레딧 충전·종단 테스트 완료, 가드레일 검증 완료). 서버측 기기별 일30문 KV 상한.
- 무료 튜터 **총 5문**(일회성, 월리필 아님). 사용량: 설정 화면 표시.

## 수익 모델 (확정)
- 무료 영원히: 트랙1(12편)+시장+오늘의장+아레나+룰기반 복기
- **트랙 단품** 각 ₩5,000 일회성(영구소장, AI 미포함) / **Pro** 월 ₩3,300·연 ₩22,000(전 트랙+AI코멘트+튜터 월40문) / **리필** 10문 ₩1,100·30문 ₩2,900(소모성)
- 상품 ID: `seed.pro.monthly.v2` `seed.pro.yearly.v2`(초기 ID는 ASC 삭제로 영구 잠김) `seed.tutor.refill10` `seed.tutor.refill30` `seed.track.etf`(트랙2 단품 ₩5,000 비소모성) — **5종 전부 ASC 등록 완료(2026-07-18, '제출 준비 중')** — `Core/PurchaseStore.swift`(ownsETFTrack = Pro ∨ 단품), `Learn/RefillSheet.swift`·`Learn/TrackPaywallSheet.swift`(정직 페이월), 개발용 `SEED/Products.storekit`+스킴 연결
- 결제 트리거 (구현 완료): 졸업 완료 화면 CTA→트랙 2 목차→1편 무료→페이월 / 배우기 히어로·시장 ETF 칩·목차 잠금 행 / 튜터 소진 / 아카이브 잠금. 계측: paywall_shown(sheet·source별)·purchase_completed·track_promo_tapped — 전환율 = purchase/paywall_shown
- 유저당 AI 하드캡 ~200원/월 설계. 손익분기 = 유료 5명.

## 진행 중 / 다음 할 일
1. **스크린샷 6장 — 완성** (2026-07-24 재규격): 프로젝트 루트 `appstore-screenshots/` **1284×2778** PNG 6장(ASC 6.5형 슬롯 규격 — 1290×2796에서 0.5% 축소+배경 크롭). **[사용자] ASC 버전 페이지 iPhone 슬롯에 01→06 순서로 드래그 업로드만 하면 됨.** 스크래치패드의 제작 파이프라인 원본(make_pages.py·raw)은 세션 정리로 소실 — 재생산 필요 시 `claudedocs/appstore-메타데이터.md` 스크린샷 절의 방법대로 재구축.
2. **튜터 워커 — 완료·검증됨** (2026-07-18 종단 재검증: 인증 헤더는 **`x-seed-client`** — 토큰 없이 401, 올바른 토큰+정상 body(`deviceId` UUID + `messages` 배열, 마지막 role=user)로 200 실답변). 남은 것: **[사용자] console.anthropic.com → Settings → Limits 월 지출 한도** 설정(비용 폭주 최후 방어벽). 코드리뷰 처리 현황은 `claudedocs/코드리뷰-2026-07.md` 상단 참고 (P0·P1·P2 전부 수정 완료).
3. **ASC 마무리 — 메타데이터 전부 입력·저장 완료** (2026-07-24): 상품 5종 등록('제출 준비 중') + 버전 페이지(프로모션·설명·키워드 89자·심사 메모·연락처(정송헌/+821025142426/gmlwns5504@naver.com)·로그인 불필요·**수동 출시**) + 앱 정보(부제 "잃어도 되는 돈으로 천 번 연습하기"·카테고리 교육+금융) + **연령 등급 4+ 설문 완료**(한국 "전체", 가상도박·시합·UGC·웹액세스 전부 아니요) + 개인정보/지원 URL·저작권·App Privacy 라벨 게시. **유료 앱 계약 활성 확인**(무료·유료 모두 활성, 세금 양식 3종 활성 — 은행 계좌 Toss-arcseed만 Apple '처리 중': 지급용이라 제출 블로커 아님). **[사용자] 남은 클릭**: ①버전 페이지에 스크린샷 6장 드래그 ②튜터 리필 30문·트랙 2 ETF 심사 스크린샷(`iap-screenshot-pro.png`) 업로드. 최종 제출 시 버전에 빌드·구독·IAP 연결. 입력값 전체는 `claudedocs/ASC-입력값-시트.md`.
   - 법률 문안: `/seed/privacy`·`/seed/terms`에 AI 튜터·구독 조항 포함본이 **이미 라이브** — 앱 링크도 여기로 수정 완료(SeedLinks). /ko/* 붙여넣기 불필요.
4. **실기기 검증 대기**: 사용자 iPhone 17 Pro에서 **AI 체험 카드**(복기 탭, EmptyView task 앵커 버그 수정 후 재확인 요청한 상태 — 마지막 미확인), 구독 v2 샌드박스, 알림 4종(**신규: 체결 영수증 — 시장가·지정가 대기 체결·ETF 각각 배너 확인**), 위젯 딥링크, **재설치 iCloud 현금 복원**(삭제→재설치→수 초 내 매매기록과 함께 현금·보유 합류 — fix/icloud-cash-restore) + **아침 복습이 진행 트랙 문제를 내는지**(fix/morning-quiz-target). main Archive → TestFlight.
5. **출시 후 백로그** (우선순위): 친구 대결(결정론 시드 → 도전 링크, 서버 불요) > 차트게임 스낵 모드(§11 프레임 필수) > MetricKit 로컬 진단+문의 첨부 > 트랙3 크립토 > 시즌 누적 프로필. Pro 체험(주간복기 AI 1회 무료)은 구현 완료.
6. **CloudKit 프로덕션 스키마 배포 완료** (2026-07-18 — 레코드 5종+인덱스 Production 반영). **단, `CD_SymbolState.openOrdersData`가 개발 스키마에 아직 미생성** (nil 아닌 값이 iCloud로 동기화돼야 필드가 잡히는데 지정가 미체결 상태로 동기화된 적이 없음) → **출시 전: 실기기에서 지정가 1건 걸어둔 채 동기화 → CloudKit Console에서 필드 생성 확인 → Deploy Schema Changes 재실행** (추가 배포는 언제든 안전). 그 전까지 프로덕션 환경에서 미체결 주문의 iCloud 내보내기만 지연되고 재시도됨(데이터 유실 없음).
7. 보류: 베타 프로모 코드. KPI 게이트: D7 리텐션 20%+.

## 주의사항
- **저장소가 public** (github.com/whatdoIsa/SEED) — 시크릿은 절대 커밋 금지. `SEED/SEED/Learn/TutorSecrets.swift`(워커 공유 토큰)는 gitignore 대상이라 **새 장비 체크아웃 시 수동 복원 필요**(없으면 빌드 실패). 값 변경 시 Cloudflare Secret `CLIENT_TOKEN`도 같이 교체.
- 튜터 크레딧·지급 기록은 `NSUbiquitousKeyValueStore`(iCloud KV, TutorCloudStore) — UserDefaults로 되돌리면 재설치 시 유료 크레딧 증발. entitlements에 kvstore 권한 추가됨.
- 평단(avgCost) = **매수 수수료 포함 취득원가**(본전가). Σ실현손익 = 현금 변화 불변식이 테스트로 고정돼 있음.
- 사용자 주문은 자기 대기 주문과 체결되지 않음(STP) — OrderBook의 `excluding` 파라미터. 봇·에이전트 경로는 영향 없음.
- 미체결 지정가는 SymbolState.openOrdersData로 영속 — 정확 리플레이 경로에서만 재접수(스냅샷 폴백 시 소멸, 의도된 것).
- 차트 MA는 전체 히스토리로 계산 후 창만 그림 — 창 슬라이스로 계산하면 MA60/120이 사라진다 (ChartCanvas.windowedMA).
- 복기 탭은 방문 시점 스냅샷(ReportSnapshot) — body에서 store 집계·session을 직접 읽으면 틱마다 재실행된다. 부검(AutopsyView)도 equity 스냅샷 방식. AI 지문(fingerprint)에 틱마다 변하는 값 넣지 말 것.
- Xcode 스킴에 `queueDebuggingEnabled=No` 필수 유지 (디버거 크래시 방지 — 절대 되돌리지 말 것)
- `Info.plist`(부분)·`WidgetInfo.plist`·entitlements 2개·`Products.storekit`는 프로젝트 루트/SEED에 있음 — 동기화 폴더 밖 (리소스 충돌 방지)
- 오늘의 장 완료 기록 = `daily.YYYYMMDD` LessonProgress. 스트릭·패턴은 날짜에서 결정론 재계산
- SeedStore.completedLessonIds가 관찰 캐시 — 레슨 상태 변경 시 반드시 이 집합도 갱신
- 시뮬레이터에서 온디바이스 AI는 항상 미지원 폴백 (버그 아님) — **AI 관련 UI는 실기기 캡처가 유일한 검증 수단**
- SwiftUI 함정: EmptyView로 풀리는 뷰의 `.task`는 실행 안 됨 — 조건부 카드엔 `Color.clear.frame(height:0)` 앵커 필수 (AICoachCard 참고)
- 빌드 검증은 `grep -cE "BUILD SUCCEEDED"`로 — `grep error:`는 에러를 찾으면 exit 0이라 && 체인이 안 멈춘다 (한 번 깨진 빌드가 병합된 사고 있음)
- 시뮬 캡처: 콜드부트 직후 첫 캡처는 빈 화면일 수 있음 — terminate 후 재launch가 정석
