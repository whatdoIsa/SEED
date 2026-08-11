# ASC 마무리 입력값 시트 (2026-07-18)

> 브라우저 연결 후 이 값 그대로 진행. 직접 하실 경우에도 이 시트만 보고 끝낼 수 있게 작성.

## 1. 구독 그룹 현지화 (누락 시 상품이 '메타데이터 누락'으로 잠김)
- 위치: 앱 → 수익화 → 구독 → 그룹 "SEED Pro" → 현지화 (한국어)
- **구독 그룹 표시명**: `SEED Pro`
- 앱 이름 표시 옵션: 앱 이름 그대로 (SEED)

## 2. 연간 구독 등록 — `seed.pro.yearly.v2`
- 위치: 구독 그룹 SEED Pro → "+" 구독 생성
- 참조 이름: `SEED Pro Yearly`
- 제품 ID: `seed.pro.yearly.v2`
- 기간: 1년
- 가격: **₩22,000** (KRW 기준가)
- 현지화(한국어):
  - 표시명: `SEED Pro 연간`
  - 설명: `모든 학습 트랙과 AI 코치·튜터를 1년 동안 이용해요.`
- 심사 정보: 스크린샷 = `~/Desktop/iap-screenshot-pro.png`, 심사 메모 불필요
- 월간(`seed.pro.monthly.v2`)과 같은 그룹·같은 등급(레벨 1)인지 확인

## 3. 트랙 단품 등록 — `seed.track.etf`
- 위치: 앱 → 수익화 → 앱 내 구입 → "+" 생성
- 유형: **비소모성(Non-Consumable)**
- 참조 이름: `Track 2 ETF`
- 제품 ID: `seed.track.etf`
- 가격: **₩5,000**
- 현지화(한국어):
  - 표시명: `트랙 2 · ETF·분산투자`
  - 설명: `ETF 레슨 8편과 ETF 모의 시장을 기한 없이 이용해요.`
- 심사 스크린샷: `~/Desktop/iap-screenshot-pro.png` 재사용 가능 (페이월에 단품 노출됨)

## 4. 앱 정보 URL
- 위치: 앱 → 일반 → 앱 정보
- **개인정보처리방침 URL**: `https://www.arcseed.kr/seed/privacy` (라이브 확인 완료 — AI 튜터 조항 포함본)
- 위치: 버전 페이지
- **지원 URL**: `https://www.arcseed.kr/seed`
- EULA: 표준 Apple EULA 사용 (커스텀 불필요 — 앱 내 약관 링크는 /seed/terms)

## 5. App Privacy 라벨
- 위치: 앱 → 앱 개인 정보 보호 → 시작하기
- 데이터 수집 여부: **예** ("데이터 수집 안 함"은 불가 — 튜터 질문이 서버 경유)
- 수집 항목 1: **사용자 콘텐츠 > 기타 사용자 콘텐츠** (튜터 질문 텍스트)
  - 사용 목적: 앱 기능(App Functionality)
  - 사용자 신원과 연결: **아니요**
  - 추적 목적 사용: **아니요**
- 그 외 항목 전부: 수집 안 함 (매매기록·진행은 사용자 iCloud 개인 DB — Apple 정의상 '수집' 아님. 로컬 통계 파일도 미전송이라 해당 없음)

## 6. CloudKit 프로덕션 스키마 배포 — ✅ 완료 (2026-07-18)
- 레코드 5종(CD_AppProgress·CD_LessonProgress·CD_Season·CD_SymbolState·CD_TradeLog)+인덱스 Production 배포 확인 ("Changes Deployed")
- ⚠️ 배포 시점 개발 스키마의 CD_SymbolState 필드 = code·entityName·lastTick·seasonNumber·seedBits 5개 — **openOrdersData 없음** (지정가 미체결 상태가 iCloud로 동기화된 적이 없어 필드 미생성)
- **출시 전 재배포 절차**: 실기기에서 지정가 1건 걸어둔 채 iCloud 동기화 → Console에서 CD_SymbolState에 openOrdersData 생성 확인 → Deploy Schema Changes 재실행

## 7. 남은 사용자 클릭 (2번)
- ASC → 수익화 → 앱 내 구입 → **튜터 리필 30문** → 심사 정보 > 스크린샷 → `~/Desktop/iap-screenshot-pro.png`
- 같은 방법으로 **트랙 2 ETF 분산투자**에도 업로드
- 최종 제출 시: 버전 페이지에서 구독·앱 내 구입을 버전에 연결 (페이지 상단 배너 안내대로)
