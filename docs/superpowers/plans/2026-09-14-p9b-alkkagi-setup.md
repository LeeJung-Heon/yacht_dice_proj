# P9b 알까기 배치 단계와 큰 판 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 알까기에서 판이 열리면 각자 자기 진영에 돌 다섯을 자유롭게 놓는 배치 단계를 두고, 화면의 판을 지금보다 크게 보인다.

**Architecture:** 규칙의 수를 `Alkkagi.Move { case setup([Point]); case flick(Flick) }`로 넓혀 배치가 좌석당 한 수로 기록·전송되게 하고, `initial()`은 돌이 놓이지 않은 상태에서 시작하며 기본 배치를 `defaultPlacement(seat:)`로 준다. 화면은 배치 단계에서 내 돌을 진영 안 교차점으로 끌어 놓고 "배치 완료"로 확정하며, 판은 화면 폭을 다 쓰고 바깥 여백을 반 칸으로 줄인다.

**Tech Stack:** Swift 6 / SwiftUI / Swift Testing, XcodeGen, Supabase(스키마 그대로).

**Spec:** `docs/superpowers/specs/2026-09-11-p9-alkkagi-design.md` (이 계획이 §2·§3·§4를 아래처럼 고친다)

## Global Constraints

- 명령·환경은 P9 계획(`docs/superpowers/plans/2026-09-11-p9-alkkagi.md`)의 Global Constraints와 같다(단위·패키지·UI·통합 테스트 명령, `-noPush -noGameCenter`, 익명 가입 한도).
- 진영: 좌석 0은 `y ∈ 0…5000`, 좌석 1은 `y ∈ 7000…12000`; x는 `0…12000`; 배치는 교차점(1000의 배수)이며 돌끼리 중심 거리 제곱이 `800²` 이상이다.
- 기본 배치는 지금의 한 줄(좌석 0 `y = 2000`, 좌석 1 `y = 10000`, `x = 4000…8000`).
- 배치 순서: 좌석 0이 먼저, 그다음 좌석 1, 둘 다 끝나면 좌석 0부터 튕긴다.
- 판 여백은 반 칸(`spacing / 2`)이며 판은 화면 폭을 다 쓴다(가로 패딩 0).
- 한국어 `~다` 종결, 커밋 트레일러 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

### Task 1: 규칙 — 배치 단계 (GameCore)

**Files:**
- Modify: `Packages/GameCore/Sources/GameCore/Alkkagi.swift`, `Packages/GameCore/Tests/GameCoreTests/AlkkagiTests.swift`
- Modify (픽스처): `Tests/YachtDiceTests/OnlineMatchTests.swift`(`AlkkagiMatchTests`), `Tests/YachtDiceTests/AlkkagiReplayTests.swift`, `Tests/YachtDiceTests/AppContainerTests.swift`(`알까기_로컬`), `Tests/YachtDiceTests/OnlineMatchOpenTests.swift`(`알까기_행_열기`), `Tests/YachtDiceTests/SupabaseE2ETests.swift`(`알까기_한_판`), `App/Games/Alkkagi/AlkkagiScreen.swift`(컴파일만 맞춘다: `match.play(.flick(flick))`, `simulate(state, flick)`은 그대로)
- Spec: `docs/superpowers/specs/2026-09-11-p9-alkkagi-design.md` §2·§3 갱신

**Interfaces:**
- Produces:
```swift
public enum Alkkagi: Game {
    public enum Move: Codable, Equatable, Sendable { case setup([Point]); case flick(Flick) }
    public enum Phase: Codable, Equatable, Sendable { case setup, play }
    public struct State { public var stones: [[Point?]]; public var placed: [Bool]; public var nextSeat: Int?; public var outcome: Outcome?; public var lastSimulation: Simulation?; public var phase: Phase { placed.allSatisfy { $0 } ? .play : .setup } }
    public static func initial() -> State            // stones 전부 nil, placed [false,false], nextSeat 0
    public static func defaultPlacement(seat: Int) -> [Point]
    public static func placementIsValid(_ points: [Point], seat: Int) -> Bool
    public static func standardStart() -> State       // 두 좌석 기본 배치를 적용한 상태(테스트·미리보기용)
    public static func simulate(_ state: State, _ flick: Flick) -> Simulation   // 그대로
    public static func homeRange(seat: Int) -> ClosedRange<Int>   // 0...5000 / 7000...12000
}
```
- `canApply(.setup(points))`: `phase == .setup`, `nextSeat == seat`, `!placed[seat]`, `placementIsValid(points, seat:)`(개수 5, x·y 범위, 교차점, 서로 800 이상). `apply(.setup)`: `stones[seat] = points`, `placed[seat] = true`, `nextSeat = placed 둘 다 참이면 0 아니면 1 - seat`. `canApply(.flick)`: `phase == .play`와 기존 조건. `apply(.flick)`: 기존.
- `remaining(seat:)`: 그대로(놓이기 전엔 0).

- [ ] **Step 1: 실패하는 테스트** — `AlkkagiTests`에 더한다: `초기_배치_전`(initial은 돌이 없고 phase setup, nextSeat 0, 기본 배치는 다섯 점이 진영 안), `배치_검증`(개수 4·진영 밖·교차점 아님·겹침 800 미만·남의 진영·같은 좌석 두 번 거부), `배치_순서`(0이 놓으면 nextSeat 1, 1이 놓으면 phase play·nextSeat 0, 배치 전 flick 거부), `표준_시작`(`standardStart()`가 기존 한 줄과 같다). 기존 테스트는 `Alkkagi.initial()`을 `Alkkagi.standardStart()`로 바꾸고, `완주`·`왕복`의 수 목록 앞에 `.setup(defaultPlacement(seat: 0))`, `.setup(defaultPlacement(seat: 1))`을 붙이고 `flick`은 `.flick(...)`으로 감싼다. 앱 쪽 픽스처(`winningMoves()`, E2E, 컨테이너·열기 테스트의 로그)도 같은 두 수를 앞에 둔다.
- [ ] **Step 2: 실패 확인** — 패키지 테스트가 `Move` 없음으로 컴파일 실패.
- [ ] **Step 3: 구현** — 위 인터페이스대로. `Move`의 Codable은 합성(연관값 enum). `State`의 `init(from:)`/`encode(to:)`에 `placed`를 더한다. `AlkkagiScreen`은 `match.play(.flick(flick))`로만 바꿔 컴파일을 맞춘다(배치 UI는 Task 2).
- [ ] **Step 4: 통과 확인** — 패키지 전체, 단위 전체(UI 제외). 통합 테스트는 Task 2 뒤 한 번.
- [ ] **Step 5: 스펙 갱신** — §2 결정표에 배치 행, §3에 `Move`·`Phase`·`placed`·배치 검증·순서를 적는다. 커밋 `feat(alkkagi): 돌 배치를 수로 두어 각자 진영에 놓는다`.

---

### Task 2: 화면 — 배치 UI와 큰 판

**Files:**
- Modify: `App/Games/Alkkagi/AlkkagiScreen.swift`, `App/Games/Alkkagi/AlkkagiGeometry.swift`(여백 반 칸), `App/Games/Alkkagi/AlkkagiBoardView.swift`(진영 음영, 배치 중 돌), `Tests/YachtDiceTests/AlkkagiGeometryTests.swift`, `Tests/YachtDiceUITests/AlkkagiUITests.swift`, `README.md`, spec §4

**Interfaces:**
- `AlkkagiGeometry.margin = Alkkagi.spacing / 2`(모든 사상이 이 값을 쓴다), `snap(_ p: Point) -> Point`(가장 가까운 교차점), `unit`은 `min(side) / (boardMax + 2 * margin)`.
- `AlkkagiBoardView`에 `homeShade: ClosedRange<Int>?`(배치 중인 좌석의 진영을 옅게 칠한다)와 `dragging: (seat: Int, stone: Int, at: Point)?`(끌리는 돌을 그 자리에 그린다).
- 화면: `phase == .setup`이면 안내 "내 돌을 진영 안에 놓는다"(상대 차례면 "<이름>이(가) 돌을 놓는 중"), 내 배치 초안 `@State draft: [Point]`(기본 배치로 시작), 드래그로 돌을 옮기면 놓는 순간 `snap`하고 진영·겹침을 검사해 유효하지 않으면 제자리로 되돌린다, "배치 완료" 버튼(`alkkagi.placeDone`)은 `placementIsValid`일 때만 활성이며 누르면 `match.play(.setup(draft))`. 상대의 `setup`은 `onRemoteMove`에서 애니메이션 없이 지나간다. 온라인 게스트(뒤집힌 판)는 자기 진영이 아래에 보인다.
- 큰 판: 판 컨테이너의 `.padding(.horizontal, 8)` 제거, 명패를 한 줄 높이 28pt로, 헤더를 한 줄로 합쳐(`header.status`와 `header.turn`은 유지) 판이 화면 폭을 다 쓰게 한다. 잡는 반경 `r * 1.3` → `r * 1.6`.
- UI 테스트: 배치 단계에서 "배치 완료"를 두 번(흑, 백) 누른 뒤 기존 튕김 시나리오. 좌표는 새 여백(반 칸)으로 다시 계산: 흑 돌 2 `(6000, 2000)` → 정규화 `(0.5, 1 - 2.5/13)`, 당김 끝 `(0.5, 1 - 0.5/13)`.

- [ ] **Step 1: 실패하는 테스트** — 기하 테스트의 여백 가정 갱신과 `snap` 테스트, UI 테스트에 `alkkagi.placeDone` 두 번 탭 추가(RED: 버튼 없음).
- [ ] **Step 2: 구현** — 위대로. `AlkkagiScreen`의 드래그 제스처는 `phase`로 갈라진다(배치: 초안 옮기기 / 플레이: 새총).
- [ ] **Step 3: 통과 확인** — 단위 전체, UI 전체, 통합 한 번(`알까기_한_판`이 setup 두 수를 먼저 보낸다).
- [ ] **Step 4: 문서** — README 알까기 문단에 배치 단계 한 문장, spec §4 흐름 1에 배치 단계. 커밋 `feat(alkkagi): 배치 단계 화면과 큰 판`.
