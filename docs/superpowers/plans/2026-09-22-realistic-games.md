# Realistic Games Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 사실적인 컵퐁과 넓어진 오목·알까기, 맵이 바뀌는 알까기 3판 2선승제를 완성해 사용자에게 확인받는다.

**Architecture:** GameCore의 결정적 규칙을 SwiftUI·RealityKit이 그대로 표현한다. 독립적인 컵퐁 물리, 알까기, 오목은 각각 담당자가 구현하고, 루트가 컵퐁 재질·재생·온라인 규칙 버전과 전체 검증을 담당한다.

**Tech Stack:** Swift 6, Swift Testing, XCTest, SwiftUI, RealityKit, Supabase.

**Spec:** `docs/superpowers/specs/2026-09-22-realistic-games.md`

## Global Constraints

- iOS 18+, Swift 6, SwiftUI/RealityKit. 기존 컵별 사진과 온라인 상대 공유 유지.
- 예상 궤적은 표시하지 않는다.
- 사용자 확인: 실제 영역과 화면 모두 확대. 오목은 19줄, 알까기는 17줄.
- 2026-09-22 사용자 컨펌 완료. 제한된 알까기 조준 안내를 추가 검증하고 main 병합·서버 변경·TestFlight 배포를 진행한다.

## 1. 컵퐁 물리

Files: `Packages/GameCore/Sources/GameCore/CupPong.swift`, `CupPongPhysics.swift`, `Packages/GameCore/Tests/GameCoreTests/CupPongTests.swift`.
Interface: `simulate(_:against:) -> Simulation`; `Frame(step:x:y:height:)`, `Event(step:kind:)`, `Simulation.frames/events/landing/steps`.

- [x] 테이블 충돌 전후 높이·림 반사·컵 진입·반복 결정성 테스트를 먼저 작성하고 기존 구현에서 실패를 확인한다.
- [x] 240Hz 시뮬레이션과 감쇠 충돌을 구현하고 `apply`가 같은 결과를 사용하게 한다.
- [x] 모든 컵 도달, 비운 컵 통과, 극단 입력의 유한 종료를 검증한다.

```swift
let shot = CupPong.Shot(dx: 0, power: 0)
let sim = CupPong.simulate(shot, against: Array(repeating: false, count: 10))
#expect(sim.events.contains { $0.kind == .tableBounce })
#expect(sim == CupPong.simulate(shot, against: Array(repeating: false, count: 10)))
```

Run: `swift test --package-path Packages/GameCore --scratch-path /tmp/cuppong-physics-build`

## 2. 알까기 시리즈·맵

Files: `Packages/GameCore/Sources/GameCore/Alkkagi.swift`, related GameCore tests, `App/Games/Alkkagi/*`, Alkkagi unit/UI tests.
Interface: `State.roundNumber/roundWins/roundOutcome/map`, `.nextRound`, `.roundOver`, `.bumper`.

- [x] 한 라운드 승리 후 match outcome이 nil이고 다음 라운드 후 점수가 남는 테스트, 2승 종료, 무승부 재경기를 먼저 실패시킨다.
- [x] 17줄 배치·낙하 경계와 3개 실제 지형을 구현한다.
- [x] 점수·맵명·다음 라운드 버튼과 확대된 보드를 구현한다.
- [x] 기존 보간·원격 재생과 신규 맵 충돌을 검증한다.

```swift
var next = Alkkagi.apply(.nextRound, to: completedRound)
#expect(next.roundWins == [1, 0])
#expect(next.roundNumber == 2)
#expect(next.phase == .setup)
```

Run: `swift test --package-path Packages/GameCore --scratch-path /tmp/alkkagi-series-build`

## 3. 오목 19줄

Files: `Packages/GameCore/Sources/GameCore/Omok.swift`, `App/Games/Omok/*`, Omok tests.

- [x] 19번째 열에 돌을 둘 수 있으며 바깥 가장자리에서 5목 승리를 판정하는 테스트를 실패시킨다.
- [x] 19줄 보드와 화점, 좌우 4pt 여백, 현재 좌석 미리보기를 구현한다.
- [x] 확대된 판 가장자리 탭과 승리 UI를 검증한다.

```swift
#expect(Omok.canApply(.init(x: 18, y: 18), to: Omok.initial()))
```

Run: `swift test --package-path Packages/GameCore --scratch-path /tmp/omok-board-build`

## 4. 컵퐁 실물 표현·시뮬레이션 재생

Files: `App/Games/CupPong/CupPongScene.swift`, new materials/mesh helper as needed, `CupPongScreen.swift`, `CupPongGeometry.swift`, related app tests.

- [x] 공의 물리 높이가 씬 좌표로 정확히 옮겨지는 회귀 테스트를 먼저 실패시킨다.
- [x] 컵 두께·화이트 내부·림·리브·액체, 테이블 재질, 접지 그림자를 구현한다.
- [x] 고정 포물선 대신 시뮬레이션 프레임을 경과 시간으로 보간하고 충돌 타이밍에 소리·햅틱을 재생한다.
- [x] 드래그 예상 궤적 없이 입력 잠금·취소·상대 재생을 검증한다.

```swift
scene.update(cups: cups, ball: (0, 1200, 35), vanishing: nil, customization: store)
#expect(abs(ball.position.y - 0.014) < 0.0001)
```

Run: dedicated simulator with `xcodebuild ... -only-testing:YachtDiceTests/CupPongSceneTests test`.

## 5. 호환성·통합 확인

Files: GameCore `Game.swift/MoveLog.swift`, online room creation/join compatibility, migration, related tests/docs.

- [x] 구 규칙 로그를 새 규칙으로 재생하지 않도록 버전 경계 테스트를 작성한다.
- [x] 방 생성 로그에 버전을 넣고 참가·이어하기에서 비교한다. 기존 클라이언트를 차단하는 SQL 마이그레이션을 운영 DB에 적용했다.
- [x] GameCore와 앱 단위·UI 테스트를 실행하고 실제 화면을 캡처해 시각적으로 검사한다.
- [x] 변경·테스트·적용한 마이그레이션을 기록하고 완성 화면 검토 자료를 준비한다.
- [x] 사용자에게 디자인·규칙 확정 컨펌을 받는다. (2026-09-22 확정)

## Validation record

- GameCore 57개, 앱 단위 173개 (네트워크 통합 13개 제외), UI 고유 16개 최종 실행 통과. UI 전체 실행에서 발견한 알까기 접근성 식별 중복은 수정 후 재검증했다.
- 컵퐁 그림자와 사진 곡면을 실제 시뮬레이터 화면으로 확인했다.
- 로컬 PostgreSQL과 운영 Supabase에서 온라인 규칙 호환성과 동시 참가를 검증했다. 운영 E2E 14개도 통과했다.
- 완성 화면 및 상세 검증 기록: `build/design-review-2026-09-22/index.html`, `verification.md` (로컬 산출물).
