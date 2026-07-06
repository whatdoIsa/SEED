# JurinKit — 시뮬레이션 코어

주린이 앱의 심장. 가격을 그리지 않는다 — 에이전트 4종(마켓메이커·노이즈·추세추종·가치투자)이 호가창에 주문을 내고, 가격은 체결의 결과로 발생한다.

## 구성
| 파일 | 내용 |
|---|---|
| `MarketModels.swift` | Order / Trade / Candle / FillResult(슬리피지) / SeededRNG / **OrderBook**(가격-시간 우선 매칭) |
| `MarketAgents.swift` | MarketAgent 프로토콜 + 에이전트 4종 + AgentParams(시나리오 오버라이드용) |
| `MarketEngine.swift` | 틱 루프, fairValue 진화(랜덤워크+평균회귀), 분봉 집계, Portfolio, 사용자 시장가 주문, 이동평균 |

## 설계 결정
- **엔진에 Timer 없음.** UI 레이어가 배속에 맞춰 `step()` / `advance(ticks:)`를 호출한다. 배속(1x/5x/30x)·캔들 스킵·백그라운드 복귀가 전부 `advance` 한 줄로 수렴한다.
- **결정론.** `SeededRNG`(SplitMix64) — 같은 시드면 같은 시장. 시나리오 재현·봇 비교·테스트의 전제.
- **슬리피지는 1급 시민.** `placeMarketOrder`가 `FillResult`(다단계 체결 내역 + 평균 체결가 + 표시가 대비 슬리피지)를 반환한다. 슬리피지 튜토리얼(부록 A-3)의 원료.
- **`fairAnchor`가 시나리오 훅.** ScenarioPreset(M1-3)은 이 값을 키프레임으로 조작해 급등·폭락을 연출한다.
- **거장 봇은 새 아키텍처가 아니다.** `MarketAgent` 프로토콜의 새 구현일 뿐.

## 사용 (엔진 구동)
```swift
import JurinKit

let engine = MarketEngine(seed: 42)   // 같은 시드 = 같은 시장
engine.advance(ticks: 100)            // 배속·스킵·복귀 전부 이걸로

let result = try engine.placeMarketOrder(side: .buy, qty: 1_000)
result.avgFillPrice   // 52,460.0  ← 표시가는 52,300이었는데
result.slippage       // +160.0    ← 이게 슬리피지 튜토리얼의 순간
```

## iOS 앱 타깃 연결
1. Xcode → File → New → Project → iOS App (SwiftUI, 이름 예: `Jurin`)
2. 프로젝트에 로컬 패키지 추가: File → Add Package Dependencies → Add Local → `JurinKit` 폴더 선택
3. 앱 타깃에서 `import JurinKit` 후 `@State var engine = MarketEngine(seed:)` + `TimelineView`/`Task` 루프로 `step()` 호출

## 테스트
```bash
swift test   # 16 tests — 매칭·슬리피지 정본 케이스(52,460)·결정론·포트폴리오 회계
```
