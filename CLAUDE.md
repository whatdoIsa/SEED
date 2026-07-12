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
- **시장**: 6종목(한빛전자·중공업·바이오·식품·골드·비트씨) 공유원장, β 상관관계, 제도팩(수수료·세금·상하한가·거래일·동시호가), 뉴스 84종, 지정가/미체결, 토스식 상세차트+핀치줌+전체화면(회전), 세션 연속성(리플레이, 30만 스텝 초과 시 LedgerSnapshot 폴백)
- **배우기**: 본편 12편 완결(하루 1레슨, 첫 3개 자유) + 심화 6편(터틀3·퀀트3) + 용어사전 41 + 요약카드 + 아침퀴즈 + 오늘의실천. 3섹션(오늘/커리큘럼/라이브러리). 레벨=완료 레슨 수, 도구해금 Lv1캔들/2호가/4거래량/5전체
- **오늘의 장**: 날짜시드 패턴 5종, 스트릭+7일 점, 공유카드. **아레나**: 무작위 장 나vs거장5+내전략, 라이브 순위, 전적. **거장 도장**: 5인 프로필(데니스·그레이엄·오닐·코스톨라니·템플턴)×장4종, 매매일지(이유 포함), 리매치. **전략 실험실**: 3템플릿+가치스크리너+장별성적표+아레나 출전 슬롯
- **복기**: 태그·매매지도·보유습관(FIFO 페어링)·부검·시즌 아카이브(성장그래프, Pro게이트)
- **인프라**: iCloud 백업(복원 병합 refreshAfterRemoteImport), 홈/잠금 위젯(App Group+딥링크 seed://daily), 주간 푸시(일 19시), 설정 화면, 앱아이콘/런치, 접근성 요약, 하루1레슨 페이스
- **배우기 탭 = 트랙 허브 구조 (develop)**: 오늘 섹션 + "이어서 배우기" 히어로 카드(`Learn/TrackHub.swift`의 NextLessonFinder — 트랙1 다음 편 → 페이스 소진 시 트랙2 → 완주 시 예고 카드) + 트랙 카드 4장(1 주식기본기·2 ETF·3 크립토 예정·4 금융기초 예정, 진행률 바·진행 중 보라 테두리·미소유 "1편 무료" 배지) + 라이브러리 카드 1장. 레슨 목차는 `TrackDetailView` 시트로, 심화·도장·실험실·튜터·용어사전은 `LibraryView` 시트로 이사. 트랙 추가 시 `TrackCatalog.all`에 TrackDef 1개만 추가하면 됨.
- **트랙 2 — ETF·분산투자 (develop, Phase 3 완료)**: `JurinKit/ETFFund.swift`(고정 좌수 바스켓 NAV + 연보수/252 일할 차감, 테스트 13개 — 총 102개), ETF 2종(`Core/ETFCatalog.swift` — HIX 한빛300 지수 0.15% / HBA 균형 자산배분 0.35%, BTX 제외), NAV 즉시 체결(호가창 없음·매도 거래세 없음), MarketSession 통합(리플레이·스냅샷·totalEquity·분산 β 반영), `Market/ETFMarketView.swift`(NAV 라인차트·구성·보수 누적 카드·주문 시트), 레슨 8편 `Learn/ETFTrack.swift`(order 201+, 읽기형, 1편 무료→순서 잠금, 하루 페이스 없음) + 요약·퀴즈·실천·용어사전 8종("ETF·분산투자" 카테고리). 진입: 시장 탭 ETF 칩 + 배우기 트랙 2 섹션, 비소유 시 `Learn/TrackPaywallSheet.swift`

## AI 스택 (Phase 1 완료 — 검증됨)
- **온디바이스 (Foundation Models, iOS 26)**: `Core/AICoach.swift` — 주간복기·부검·오늘의장·아레나 해설. 캐시(키+지문, "같은 데이터에 두 번 안 묻기"), 미지원기기(iPhone 15 Pro 미만)→룰기반 폴백. **실기기 검증 아직 안 함** (시뮬은 미지원 정상).
- **튜터 (Haiku)**: 3겹 — ①규칙필터(추천·예측 거절, 0토큰) ②용어사전 직답(0토큰) ③`claude-haiku-4-5-20251001` via Cloudflare Worker `https://seed-tutor.throbbing-sun-9e1e.workers.dev/` (배포·크레딧 충전·종단 테스트 완료, 가드레일 검증 완료). 서버측 기기별 일30문 KV 상한.
- 무료 튜터 **총 5문**(일회성, 월리필 아님). 사용량: 설정 화면 표시.

## 수익 모델 (확정)
- 무료 영원히: 트랙1(12편)+시장+오늘의장+아레나+룰기반 복기
- **트랙 단품** 각 ₩5,000 일회성(영구소장, AI 미포함) / **Pro** 월 ₩3,300·연 ₩22,000(전 트랙+AI코멘트+튜터 월40문) / **리필** 10문 ₩1,100·30문 ₩2,900(소모성)
- 상품 ID: `seed.pro.monthly` `seed.pro.yearly` `seed.tutor.refill10` `seed.tutor.refill30` `seed.track.etf`(트랙2 단품 ₩5,000 비소모성 — **App Store Connect 미등록, 등록 필요**) — `Core/PurchaseStore.swift`(ownsETFTrack = Pro ∨ 단품), `Learn/RefillSheet.swift`·`Learn/TrackPaywallSheet.swift`(정직 페이월), 개발용 `SEED/Products.storekit`+스킴 연결
- 결제 트리거 (구현 완료): 졸업 완료 화면 CTA→트랙 2 목차→1편 무료→페이월 / 배우기 히어로·시장 ETF 칩·목차 잠금 행 / 튜터 소진 / 아카이브 잠금. 계측: paywall_shown(sheet·source별)·purchase_completed·track_promo_tapped — 전환율 = purchase/paywall_shown
- 유저당 AI 하드캡 ~200원/월 설계. 손익분기 = 유료 5명.

## 진행 중 / 다음 할 일
1. **[사용자 진행 중] App Store Connect 상품 등록** — 리필10문 등록했으나 "메타데이터 누락" = 심사 스크린샷 미첨부. **바탕화면 `iap-screenshot-refill.png`**(1206×2622) 업로드하면 해결. 나머지 3개 상품(refill30, pro monthly/yearly)도 같은 캡처 재사용. 유료 앱 계약(은행·세금) 활성 필수.
2. **TestFlight 새 빌드** (main에서 Archive) — AI+결제 실기기 검증: 온디바이스 코치 카드(15 Pro+), 튜터 5문, 리필 시트 원화 표시(샌드박스 — 실결제 없음, 구독 갱신 가속됨)
3. **Phase 3 — 트랙 2: ETF·분산투자 ✅ 완료 (develop)** — 남은 것: ①App Store Connect에 `seed.track.etf` ₩5,000 비소모성 등록(기존 심사 스크린샷 재사용 가능) ②main 승격은 사용자 지시 시 ③완성 시점 = App Store 정식 출시 타이밍. 이후 트랙3 크립토심화, 트랙4 금융기초(분기당 1트랙).
4. **배포 트랙 병행** (매출 = 트래픽×전환율 — 제품만으론 구매 없음): 개발일지, 쇼츠(터틀 실험·기대값 퀴즈 소재), 커뮤니티 시딩, Apple 피처드 신청(온디바이스 AI 스토리 강점).
5. **P0 출시 준비 (develop 반영)**: 페이월 2종+설정에 약관·방침 링크(`Core/SeedLinks.swift` — **URL 3개 플레이스홀더, 홈페이지 게시 후 교체 필수**), 설정 구독관리·복원·문의, iPhone 전용(TARGETED_DEVICE_FAMILY=1). 문서: `claudedocs/legal-docs-요약.md`(방침·약관에 들어갈 내용), `claudedocs/appstore-메타데이터.md`(ASC 문안·심사노트·체크리스트). 남은 것: 문서 게시→URL 교체, 스크린샷 6장 제작, P1(온보딩 '왜 가상인가'·평가요청·수료 공유카드).
6. 보류: CloudKit 프로덕션 스키마 배포(icloud.developer.apple.com — TestFlight iCloud 동기화에 필요, 앱 동작엔 지장 없음). 베타 테스터 프로모 코드. KPI 게이트: D7 리텐션 20%+.

## 주의사항
- Xcode 스킴에 `queueDebuggingEnabled=No` 필수 유지 (디버거 크래시 방지 — 절대 되돌리지 말 것)
- `Info.plist`(부분)·`WidgetInfo.plist`·entitlements 2개·`Products.storekit`는 프로젝트 루트/SEED에 있음 — 동기화 폴더 밖 (리소스 충돌 방지)
- 오늘의 장 완료 기록 = `daily.YYYYMMDD` LessonProgress. 스트릭·패턴은 날짜에서 결정론 재계산
- SeedStore.completedLessonIds가 관찰 캐시 — 레슨 상태 변경 시 반드시 이 집합도 갱신
- 시뮬레이터에서 온디바이스 AI는 항상 미지원 폴백 (버그 아님)
