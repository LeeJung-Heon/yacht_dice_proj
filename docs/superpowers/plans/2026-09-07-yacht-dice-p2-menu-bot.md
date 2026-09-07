# Yacht Dice P2 — 던지기 연출, 메뉴, 참가자 모델, 봇 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 던지기가 자연스럽게 보이게 하고, 시작 메뉴에서 혼자 / 컴퓨터(3단계) / 로컬 2~4인 게임을 골라 12턴을 완주할 수 있게 한다.

**Architecture:** 봇과 사람은 같은 `Intent` 경로로 `GameSession`에 들어가므로 3D 연출과 점수판 지연 규칙이 동일하게 적용된다. 봇 두뇌는 새 패키지 `YachtBot`(YachtCore만 의존)의 순수 함수다. 저장 단위는 `MatchRecord`(모드 + 참가자 + 로그)로 올리고 v1 파일은 solo로 읽는다. 온라인(C)은 별도 계획이며, 이 계획은 `Participant.remote`를 자리만 만들어 둔다.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, RealityKit, Swift Testing (단위), XCTest (UI), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-07-yacht-dice-p2-p3-design.md`

## Global Constraints

- iOS 18.0 이상, Swift 6, `SWIFT_STRICT_CONCURRENCY: complete` (project.yml).
- `YachtCore`, `YachtBot`은 Foundation 외에 아무것도 import하지 않는다.
- `TrayGeometry`의 물리 치수는 바꾸지 않는다. 바꾸면 궤적을 다시 구워야 한다.
- Xcode 프로젝트는 `xcodegen generate`로 만든다. `project.yml`을 고친 뒤 반드시 다시 생성한다.
- 빌드·테스트의 `-derivedDataPath`는 저장소 밖(스크래치 디렉터리)을 가리킨다. iCloud 안에서 빌드하면 codesign이 실패한다.
- 테스트 실행 명령 (시뮬레이터 `iPhone 17 Pro`, id `64A5E02A-510C-4E97-AFF0-5BB8AFA368EB`):
  ```sh
  xcodebuild -project YachtDice.xcodeproj -scheme YachtDice \
    -destination 'id=64A5E02A-510C-4E97-AFF0-5BB8AFA368EB' \
    -derivedDataPath "$SCRATCH/dd" -only-testing:YachtDiceTests test 2>&1 | grep -E "error:|✘|Test run"
  ```
  패키지: `swift test --package-path Packages/YachtBot`
- 커밋 메시지는 Conventional Commits, 한국어 제목, 본문은 "왜"만. 끝에 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- 접근성 식별자는 기존 것(`action.roll`, `scoreboard.row.<raw>`, `header.turn`, `result.total`, `action.newGame`)을 유지한다. AccessibilityUITests가 검사한다.

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `App/Resources/trajectories.bin` | 다시 구운 궤적 (Task 1) |
| `App/Scene3D/DiceSceneBuilder.swift` | 주사위에 히트테스트 컴포넌트 추가 (Task 2) |
| `App/Scene3D/DiceStageView.swift` | 3D 탭 → 슬롯 콜백 (Task 2) |
| `Packages/YachtBot/Sources/YachtBot/BotDifficulty.swift` | 난이도 enum (Task 3) |
| `Packages/YachtBot/Sources/YachtBot/HandEvaluator.swift` | 손패 평가·기대값 (Task 3, 4) |
| `Packages/YachtBot/Sources/YachtBot/BotPlayer.swift` | 난이도별 `plan(_:)` (Task 4) |
| `App/Game/Participant.swift` | `Participant`, `GameMode`, `MatchRecord` (Task 5) |
| `App/Game/MatchStore.swift` | v2 저장, v1 호환 (Task 5) |
| `App/Game/GameSession.swift` | 참가자, 차례 소유, 봇 턴, 핸드오프 (Task 6) |
| `App/AppContainer.swift` | 메뉴 상태, 게임 시작/이어하기/메뉴 복귀 (Task 7) |
| `App/Views/MenuScreen.swift` | 시작 메뉴 (Task 7) |
| `App/Views/PlayerStrip.swift` | 좌석별 이름·총점 (Task 8) |
| `App/Views/HandoffOverlay.swift` | 패스앤플레이 기기 넘김 (Task 8) |
| `App/Views/GameScreen.swift`, `GameOverBar.swift` | 다인 결과·메뉴 복귀 (Task 8) |
| `Tests/YachtDiceUITests/*.swift` | 메뉴 경유로 수정, 봇 대전 UI 테스트 (Task 9) |

---

### Task 1: 다시 구운 궤적을 앱에 넣는다

베이커 변경(앞쪽에서 던지기, 선반 장애물, 기각 조건, 대기 프레임 절단)과 `DiceStage`의 리드인은 이미 작업 트리에 있다. 이 태스크는 굽기 결과를 검증하고 앱 리소스로 옮긴 뒤 커밋한다.

**Files:**
- Modify: `App/Resources/trajectories.bin`
- Modify: `Tests/YachtDiceTests/TrajectoryLibraryTests.swift`
- Already modified (커밋 대상): `Tools/TrajectoryBaker/BakerScene.swift`, `Tools/TrajectoryBaker/BakeRunner.swift`, `Packages/DiceTrajectory/Sources/DiceTrajectory/TrajectoryValidator.swift`, `Packages/DiceTrajectory/Tests/DiceTrajectoryTests/SmokeTests.swift`, `App/Scene3D/DiceStage.swift`

**Interfaces:**
- Produces: 번들 궤적. 조합(개수 1~5 × 방향 3)마다 20개 이상, 정지 위치가 `TrayGeometry.shelfFrontZ`보다 앞.

- [ ] **Step 1: 굽기 결과 확인**

베이커는 `open -a`로 띄워야 한다 (샌드박스 셸에서 직접 실행하면 창이 생기지 않아 물리가 돌지 않는다). 로그 끝의 요약에서 조합별 채택 수가 전부 20 이상인지 본다.

```sh
tail -20 "$SCRATCH/bake.log"
ls -la /private/tmp/trajectories.bin
```

20 미만인 조합이 있으면 `BakePlan.variantsPerCombination`을 늘리거나 던지기 속도를 낮춰(`BakerScene.resetDice`) 다시 굽는다.

- [ ] **Step 2: 실패하는 테스트 추가 — 정지 위치가 선반 앞이고, 대기 프레임이 잘려 있다**

`Tests/YachtDiceTests/TrajectoryLibraryTests.swift`에 추가:

```swift
    @Test("멈춘 주사위는 keep 선반 앞에 있다")
    func 선반_앞_정지() throws {
        let library = try TrajectoryLibrary.bundled()
        for trajectory in library.all {
            for pose in trajectory.frames[trajectory.frameCount - 1] {
                #expect(pose.position.z - TrayGeometry.dieSize / 2 > TrayGeometry.shelfFrontZ,
                        "궤적 \(trajectory.id)의 주사위가 선반 띠 안(z=\(pose.position.z))에서 멈췄다")
            }
        }
    }

    @Test("정착 대기 프레임이 잘려 있다 — 마지막 0.5초 안에 움직임이 있다")
    func 대기_프레임_절단() throws {
        let library = try TrajectoryLibrary.bundled()
        let window = library.all[0].frameRate / 2
        for trajectory in library.all {
            let last = trajectory.frames[trajectory.frameCount - 1]
            let earlier = trajectory.frames[max(0, trajectory.frameCount - 1 - window)]
            let moved = zip(last, earlier).contains { simd_length($0.position - $1.position) > 0.0004 }
            #expect(moved, "궤적 \(trajectory.id)는 마지막 0.5초 동안 아무것도 움직이지 않는다")
        }
    }

    @Test("굴림은 0.6초 이상이다")
    func 최소_길이() throws {
        let library = try TrajectoryLibrary.bundled()
        for trajectory in library.all {
            let seconds = Float(trajectory.frameCount) / Float(trajectory.frameRate)
            #expect(seconds >= 0.6, "궤적 \(trajectory.id)가 \(seconds)초로 너무 짧다")
        }
    }
```

파일 상단에 `import simd`가 없으면 추가한다.

- [ ] **Step 3: 테스트 실패 확인 (옛 궤적으로)**

Run: 위 테스트 명령에 `-only-testing:YachtDiceTests/TrajectoryLibraryTests`
Expected: `선반_앞_정지`는 옛 궤적에서 통과할 수 있지만 `대기_프레임_절단`은 FAIL (옛 궤적은 마지막 31프레임이 정지).

- [ ] **Step 4: 궤적 교체**

```sh
cp /private/tmp/trajectories.bin App/Resources/trajectories.bin
```

- [ ] **Step 5: 전체 단위 테스트 통과 확인**

Run: 단위 테스트 전체. 특히 `TrajectoryLibraryTests`, `StageProjectionTests`, `DiceStageTests`.
Expected: 전부 PASS. `StageProjectionTests.선반_화면_안`이 실패하면 정지 위치가 선반과 너무 가깝다는 뜻이다 — 던지기 앞 속도 상한(`0.85`)을 `0.8`로 낮춰 다시 굽는다.

- [ ] **Step 6: 시뮬레이터에서 눈으로 확인**

앱을 설치·실행해 Roll을 누른다. 주사위가 제자리에서 살짝 들려 앞쪽으로 모였다가 뒤로 던져져 구르고 멈춰야 한다. 순간이동이 보이면 `DiceStage.roll`의 리드인이 `slots`의 현재 위치를 쓰는지 확인한다.

- [ ] **Step 7: 커밋**

```sh
git add App/Resources/trajectories.bin App/Scene3D/DiceStage.swift Tools/TrajectoryBaker Packages/DiceTrajectory Tests/YachtDiceTests/TrajectoryLibraryTests.swift
git commit -m "feat(dice): 앞에서 던져 구르는 궤적으로 다시 굽고 리드인을 넣는다

옛 궤적은 뒷벽 위 공중에서 떨어져 앞벽까지 미끄러지는 0.3초짜리였고
나머지 1초는 정착 판정용 대기 프레임이었다. 플레이어 쪽에서 포물선으로
던지고, 선반을 물리 장애물로 넣고, 보이는 벽 위 접촉·선반 위 정지·0.6초 미만은
기각한다. 앱은 굴리기 전에 주사위를 제자리에서 집어 올리는 리드인을 넣어
순간이동을 없앤다.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: 3D 주사위를 탭해서 고정한다

**Files:**
- Modify: `App/Scene3D/DiceSceneBuilder.swift` (makeDice)
- Modify: `App/Scene3D/DiceStageView.swift`
- Modify: `App/Views/GameScreen.swift`
- Test: `Tests/YachtDiceTests/DiceSceneBuilderTests.swift`

**Interfaces:**
- Produces: `DiceStageView(stage:onDieTapped:)`, `DiceSceneBuilder.slot(of entity: Entity) -> Int?`

- [ ] **Step 1: 실패하는 테스트**

`Tests/YachtDiceTests/DiceSceneBuilderTests.swift`에 추가:

```swift
@Suite("씬 구성 - 탭 히트테스트")
struct DiceHitTestTests {
    @Test("주사위 다섯 개가 전부 탭 대상이고, 엔티티에서 슬롯을 되찾는다")
    @MainActor
    func 히트테스트_컴포넌트() {
        let root = DiceSceneBuilder.makeRoot()
        let dice = DiceSceneBuilder.dice(in: root)
        #expect(dice.count == 5)
        for (slot, die) in dice.enumerated() {
            #expect(die.components[InputTargetComponent.self] != nil, "die\(slot)에 InputTargetComponent가 없다")
            #expect(die.components[CollisionComponent.self] != nil, "die\(slot)에 히트테스트용 CollisionComponent가 없다")
            #expect(DiceSceneBuilder.slot(of: die) == slot)
        }
        #expect(DiceSceneBuilder.slot(of: root) == nil)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `-only-testing:YachtDiceTests/DiceHitTestTests`
Expected: 컴파일 에러 (`slot(of:)` 없음).

- [ ] **Step 3: 구현**

`DiceSceneBuilder.makeDice` 안, `GroundingShadowComponent` 설정 다음에:

```swift
            // 탭으로 keep하기 위한 히트테스트. 물리가 아니라 입력용 충돌 형상이다.
            entity.components.set(InputTargetComponent())
            entity.components.set(CollisionComponent(
                shapes: [.generateBox(size: SIMD3(repeating: TrayGeometry.dieSize))]))
```

`DiceSceneBuilder`에 추가:

```swift
    /// 탭 히트테스트가 돌려준 엔티티에서 주사위 슬롯을 찾는다. 주사위가 아니면 nil.
    static func slot(of entity: Entity) -> Int? {
        guard entity.name.hasPrefix("die"), let slot = Int(entity.name.dropFirst(3)),
              (0..<5).contains(slot) else { return nil }
        return slot
    }
```

`DiceStageView.swift` 전체:

```swift
import SwiftUI
import RealityKit

struct DiceStageView: View {
    let stage: DiceStage
    /// 트레이 안 주사위를 탭했을 때. 슬롯 번호를 준다.
    var onDieTapped: (Int) -> Void = { _ in }

    var body: some View {
        RealityView { content in
            stage.attach(to: content)
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    if let slot = DiceSceneBuilder.slot(of: value.entity) { onDieTapped(slot) }
                }
        )
        .accessibilityHidden(true)   // 주사위 값은 ActionBar가 음성으로 읽는다
    }
}
```

`GameScreen.swift`의 `DiceStageView(stage: stage)`를:

```swift
                DiceStageView(stage: stage) { slot in
                    Task { await session.send(.toggleHold(slot)) }
                }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `-only-testing:YachtDiceTests`
Expected: 전부 PASS. `send`는 이미 `allows(.toggleHold)`와 `isBusy`를 확인하므로 굴리기 전·연출 중 탭은 무시된다.

- [ ] **Step 5: 시뮬레이터에서 확인**

굴린 뒤 주사위를 탭하면 선반으로 올라가고 다시 탭하면 내려온다. 위로 쓸어올리는 던지기 제스처(`DragGesture(minimumDistance: 30)`)와 충돌하지 않는다 — 탭은 이동이 없다.

- [ ] **Step 6: 커밋**

```sh
git add App/Scene3D/DiceSceneBuilder.swift App/Scene3D/DiceStageView.swift App/Views/GameScreen.swift Tests/YachtDiceTests/DiceSceneBuilderTests.swift
git commit -m "feat(ui): 트레이의 주사위를 탭해서 keep한다

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: YachtBot 패키지와 손패 평가기

**Files:**
- Create: `Packages/YachtBot/Package.swift`
- Create: `Packages/YachtBot/Sources/YachtBot/BotDifficulty.swift`
- Create: `Packages/YachtBot/Sources/YachtBot/HandEvaluator.swift`
- Create: `Packages/YachtBot/Tests/YachtBotTests/HandEvaluatorTests.swift`
- Modify: `project.yml` (packages, dependencies)

**Interfaces:**
- Consumes: `YachtCore.ScoreCategory.score(_:)`, `ScoreCard.openCategories`, `ScoreCard.upperSubtotal`, `ScoreCard.upperBonusThreshold/upperBonusPoints`, `ScoreCategory.isUpper`.
- Produces:
  - `public enum BotDifficulty: String, Codable, CaseIterable, Sendable { case easy, normal, hard }`
  - `public enum HandEvaluator` with
    - `static func bestCommit(dice: [Int], card: ScoreCard) -> (category: ScoreCategory, points: Int)`
    - `static func value(dice: [Int], card: ScoreCard) -> Double`
    - `static func expectedValue(dice: [Int], holding: Set<Int>, card: ScoreCard) -> Double`
    - `static func bestHoldSet(dice: [Int], card: ScoreCard) -> Set<Int>`

- [ ] **Step 1: 패키지 만들기**

`Packages/YachtBot/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YachtBot",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "YachtBot", targets: ["YachtBot"])],
    dependencies: [.package(path: "../YachtCore")],
    targets: [
        .target(name: "YachtBot", dependencies: ["YachtCore"]),
        .testTarget(name: "YachtBotTests", dependencies: ["YachtBot"]),
    ]
)
```

`Packages/YachtBot/Sources/YachtBot/BotDifficulty.swift`:

```swift
import Foundation

public enum BotDifficulty: String, Codable, CaseIterable, Sendable {
    case easy, normal, hard

    public var displayName: String {
        switch self {
        case .easy: "쉬움"
        case .normal: "보통"
        case .hard: "어려움"
        }
    }
}
```

`project.yml`의 `packages:`에 `YachtBot: { path: Packages/YachtBot }`를, `YachtDice` 타깃 `dependencies:`에 `- package: YachtBot`을 추가한다. `xcodegen generate` 실행.

- [ ] **Step 2: 실패하는 테스트**

`Packages/YachtBot/Tests/YachtBotTests/HandEvaluatorTests.swift`:

```swift
import Testing
import YachtCore
@testable import YachtBot

@Suite("손패 평가")
struct HandEvaluatorTests {

    @Test("빈 칸 중 점수가 가장 높은 칸을 고른다")
    func 최고_기록() {
        let card = ScoreCard()
        let pick = HandEvaluator.bestCommit(dice: [6, 6, 6, 6, 6], card: card)
        #expect(pick.category == .yacht && pick.points == 50)
    }

    @Test("모두 0점이면 가치가 낮은 칸부터 버린다")
    func 버리기_순서() {
        var card = ScoreCard()
        // 1,2,3,4,5,6 상단 칸이 전부 0점이 되는 손패는 없으므로 상단을 다 채운다
        for category in ScoreCategory.upperCases { card.record(category, 0) }
        card.record(.choice, 10)
        // 남은 칸: 4 of a Kind, Full House, S/L Straight, Yacht. 손패 [1,1,2,2,5]는 전부 0점.
        let pick = HandEvaluator.bestCommit(dice: [1, 1, 2, 2, 5], card: card)
        #expect(pick.points == 0)
        #expect(pick.category == .yacht, "가장 나오기 어려운 Yacht부터 버려야 한다: \(pick.category)")
    }

    @Test("상단 보너스를 완성하는 기록은 35점을 더 쳐준다")
    func 보너스_가치() {
        var card = ScoreCard()
        card.record(.aces, 3); card.record(.deuces, 6); card.record(.threes, 9)
        card.record(.fours, 12); card.record(.fives, 15)   // 소계 45, Sixes 18이면 63
        // 6,6,6,1,2: Sixes 18 vs Choice 21. 보너스를 고려하면 Sixes(18+35)가 낫다.
        let pick = HandEvaluator.bestCommit(dice: [6, 6, 6, 1, 2], card: card)
        #expect(pick.category == .sixes)
    }

    @Test("기대값: 6이 셋이면 셋을 고정하는 것이 아무것도 안 고정하는 것보다 낫다")
    func 기대값_비교() {
        let card = ScoreCard()
        let dice = [6, 6, 6, 2, 3]
        let holdThree = HandEvaluator.expectedValue(dice: dice, holding: [0, 1, 2], card: card)
        let holdNone = HandEvaluator.expectedValue(dice: dice, holding: [], card: card)
        let holdAll = HandEvaluator.expectedValue(dice: dice, holding: [0, 1, 2, 3, 4], card: card)
        #expect(holdThree > holdNone)
        #expect(holdThree > holdAll)
        #expect(abs(holdAll - HandEvaluator.value(dice: dice, card: card)) < 1e-9, "전부 고정하면 기대값은 현재 가치다")
    }

    @Test("최적 고정 집합: 6,6,6,2,3 → 6 셋")
    func 최적_고정() {
        #expect(HandEvaluator.bestHoldSet(dice: [6, 6, 6, 2, 3], card: ScoreCard()) == [0, 1, 2])
    }

    @Test("최적 고정 집합: 1,2,3,4,6 은 1234를 고정한다")
    func 스트레이트_고정() {
        let hold = HandEvaluator.bestHoldSet(dice: [1, 2, 3, 4, 6], card: ScoreCard())
        #expect(hold == [0, 1, 2, 3])
    }

    @Test("전수 계산이 빠르다 — 32개 집합 전부 0.5초 안")
    func 계산_시간() {
        let start = ContinuousClock.now
        _ = HandEvaluator.bestHoldSet(dice: [1, 2, 3, 4, 5], card: ScoreCard())
        #expect(ContinuousClock.now - start < .milliseconds(500))
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `swift test --package-path Packages/YachtBot`
Expected: 컴파일 에러 (`HandEvaluator` 없음).

- [ ] **Step 4: 구현**

`Packages/YachtBot/Sources/YachtBot/HandEvaluator.swift`:

```swift
import Foundation
import YachtCore

/// 손패의 가치를 매기고, 재굴림의 기대값을 전수 계산한다.
///
/// 평가 함수는 "빈 칸 중 최고 점수 + 상단 보너스 완성 보정"이다. 12턴 전체를 최적화하지 않는다(1-ply).
/// 그 정도로도 사람 평균은 넘고, 계산은 어느 기기에서든 수십 ms다.
public enum HandEvaluator {

    /// 모두 0점일 때 버리는 순서. 나오기 어려운 칸부터 버려야 나중에 큰 점수를 잃지 않는다.
    static let scratchOrder: [ScoreCategory] = [
        .yacht, .aces, .largeStraight, .deuces, .fourOfAKind, .smallStraight,
        .fullHouse, .threes, .fours, .fives, .sixes, .choice,
    ]

    /// 빈 칸 중 지금 기록하기 가장 좋은 칸. 점수에 보너스 보정을 더해 비교한다.
    public static func bestCommit(dice: [Int], card: ScoreCard) -> (category: ScoreCategory, points: Int) {
        let open = card.openCategories
        precondition(!open.isEmpty, "기록할 칸이 없다")
        var best: (ScoreCategory, Double)?
        for category in open {
            let points = category.score(dice)
            var worth = Double(points) + bonusBoost(category, points: points, card: card)
            if points == 0 {
                // 0점끼리는 버리는 순서가 앞일수록 좋다 (더 큰 음수 = 더 나쁨이 아니라, 먼저 버릴 칸을 고른다)
                let rank = scratchOrder.firstIndex(of: category) ?? scratchOrder.count
                worth = -Double(rank)
            }
            if best == nil || worth > best!.1 { best = (category, worth) }
        }
        return (best!.0, best!.0.score(dice))
    }

    /// 현재 손패의 가치. 기대값 계산의 잎 노드다.
    public static func value(dice: [Int], card: ScoreCard) -> Double {
        var best = -Double.infinity
        for category in card.openCategories {
            let points = category.score(dice)
            best = max(best, Double(points) + bonusBoost(category, points: points, card: card))
        }
        return best
    }

    /// `holding`의 주사위는 두고 나머지를 한 번 다시 굴렸을 때 `value`의 기대값.
    /// 결과를 순서 없는 눈 조합(중복 조합)으로 묶고 경우의 수로 가중해 6^k 대신 C(k+5,5)개만 평가한다.
    public static func expectedValue(dice: [Int], holding: Set<Int>, card: ScoreCard) -> Double {
        let kept = dice.indices.filter { holding.contains($0) }.map { dice[$0] }
        let free = dice.count - kept.count
        if free == 0 { return value(dice: dice, card: card) }

        var total = 0.0
        var weightSum = 0.0
        for (combo, weight) in Self.multisets(count: free) {
            total += weight * value(dice: kept + combo, card: card)
            weightSum += weight
        }
        return total / weightSum
    }

    /// 32개 부분집합 중 기대값이 가장 큰 고정 집합. 동점이면 더 적게 고정하는 쪽(다시 굴릴 여지).
    public static func bestHoldSet(dice: [Int], card: ScoreCard) -> Set<Int> {
        var best: (Set<Int>, Double) = ([], -Double.infinity)
        for mask in 0..<(1 << dice.count) {
            let holding = Set(dice.indices.filter { mask & (1 << $0) != 0 })
            let ev = expectedValue(dice: dice, holding: holding, card: card)
            if ev > best.1 + 1e-9 || (abs(ev - best.1) <= 1e-9 && holding.count < best.0.count) {
                best = (holding, ev)
            }
        }
        return best.0
    }

    // MARK: - 내부

    /// 이 기록으로 상단 소계가 63을 넘기면 보너스 35점을 함께 얻는 셈이다.
    /// 아직 못 넘기더라도 상단 칸에 "눈×3 이상"을 넣는 것은 보너스 페이스를 지키는 것이므로 살짝 쳐준다.
    static func bonusBoost(_ category: ScoreCategory, points: Int, card: ScoreCard) -> Double {
        guard category.isUpper, card.upperBonus == 0 else { return 0 }
        if card.upperSubtotal + points >= ScoreCard.upperBonusThreshold {
            return Double(ScoreCard.upperBonusPoints)
        }
        let face = ScoreCategory.upperCases.firstIndex(of: category)! + 1
        return points >= face * 3 ? 4 : 0
    }

    /// `count`개 주사위의 눈 중복 조합과 그 경우의 수. 캐시해 두면 32개 집합 계산이 같은 표를 재사용한다.
    static func multisets(count: Int) -> [(combo: [Int], weight: Double)] {
        var result: [([Int], Double)] = []
        func build(_ prefix: [Int], from face: Int) {
            if prefix.count == count {
                result.append((prefix, Double(permutations(of: prefix))))
                return
            }
            for next in face...6 { build(prefix + [next], from: next) }
        }
        build([], from: 1)
        return result
    }

    /// 중복 순열의 수: n! / ∏(같은 눈 개수)!
    static func permutations(of combo: [Int]) -> Int {
        var counts = [Int](repeating: 0, count: 7)
        for face in combo { counts[face] += 1 }
        var result = factorial(combo.count)
        for c in counts where c > 1 { result /= factorial(c) }
        return result
    }

    static func factorial(_ n: Int) -> Int { n <= 1 ? 1 : n * factorial(n - 1) }
}
```

- [ ] **Step 5: 통과 확인**

Run: `swift test --package-path Packages/YachtBot`
Expected: 7개 PASS. `스트레이트_고정`이 [0,1,2,3] 외의 답을 내면 평가 함수가 스트레이트를 과소평가하는 것이다 — 그럴 때는 `value`에서 `smallStraight` 15점이 `choice` 합보다 낮게 나오는 손패인지 확인하고 테스트의 손패를 `[1, 2, 3, 4, 1]`로 바꾼다 (이 손패는 Choice 11이라 스트레이트가 확실히 낫다).

- [ ] **Step 6: 커밋**

```sh
git add Packages/YachtBot project.yml
git commit -m "feat(bot): YachtBot 패키지와 손패 기대값 평가기

12턴 전체가 아니라 다음 굴림 하나만 보는 1-ply 평가다. 눈 조합을 중복 조합으로
묶어 32개 고정 집합 × 최대 7776개 결과 대신 1683개 잎만 평가한다.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: BotPlayer — 난이도별 행동 계획

**Files:**
- Create: `Packages/YachtBot/Sources/YachtBot/BotPlayer.swift`
- Create: `Packages/YachtBot/Tests/YachtBotTests/BotPlayerTests.swift`

**Interfaces:**
- Consumes: `HandEvaluator.*`, `GameState` (`phase`, `dice`, `held`, `rollsRemaining`, `scorecards`, `currentPlayer`, `allows(_:)`).
- Produces:
  ```swift
  public struct BotPlayer: Sendable {
      public init(difficulty: BotDifficulty)
      /// 지금 상태에서 다음 굴림 또는 기록까지의 Intent 열. 전부 순서대로 보내면 된다.
      /// 상태가 바뀔 때마다 다시 부른다.
      public func plan(_ state: GameState, using rng: inout some RandomNumberGenerator) -> [Intent]
  }
  ```

- [ ] **Step 1: 실패하는 테스트**

`Packages/YachtBot/Tests/YachtBotTests/BotPlayerTests.swift`:

```swift
import Testing
import YachtCore
@testable import YachtBot

@Suite("봇 플레이어")
struct BotPlayerTests {

    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    @Test("아직 굴리기 전이면 굴린다", arguments: BotDifficulty.allCases)
    func 첫_굴림(difficulty: BotDifficulty) {
        var rng = SeededRNG(state: 1)
        let plan = BotPlayer(difficulty: difficulty).plan(GameState(playerCount: 1), using: &rng)
        #expect(plan == [.roll])
    }

    @Test("굴림이 남았으면 고정 조정 뒤 굴린다 — 어려움은 6 셋을 고정")
    func 고정_후_굴림() {
        var rng = SeededRNG(state: 1)
        let state = GameState(playerCount: 1).applying(.rolled([6, 6, 6, 2, 3]))
        let plan = BotPlayer(difficulty: .hard).plan(state, using: &rng)
        #expect(plan == [.toggleHold(0), .toggleHold(1), .toggleHold(2), .roll])
    }

    @Test("이미 고정된 것은 다시 건드리지 않는다")
    func 고정_유지() {
        var rng = SeededRNG(state: 1)
        let state = GameState(playerCount: 1)
            .applying(.rolled([6, 6, 6, 2, 3]))
            .applying(.holdToggled(0)).applying(.holdToggled(4))   // 0은 맞고 4는 틀림
        let plan = BotPlayer(difficulty: .hard).plan(state, using: &rng)
        #expect(plan == [.toggleHold(1), .toggleHold(2), .toggleHold(4), .roll])
    }

    @Test("굴림이 없으면 기록한다")
    func 기록() {
        var rng = SeededRNG(state: 1)
        var state = GameState(playerCount: 1)
        for _ in 0..<3 { state = state.applying(.rolled(state.rollableIndices.map { _ in 5 })) }
        let plan = BotPlayer(difficulty: .normal).plan(state, using: &rng)
        #expect(plan == [.commit(.yacht)])
    }

    @Test("다 고정할 만큼 좋은 손패면 굴림이 남아도 기록한다")
    func 조기_기록() {
        var rng = SeededRNG(state: 1)
        let state = GameState(playerCount: 1).applying(.rolled([4, 4, 4, 4, 4]))
        let plan = BotPlayer(difficulty: .hard).plan(state, using: &rng)
        #expect(plan == [.commit(.yacht)])
    }

    @Test("계획의 모든 Intent가 순서대로 적용 가능하다", arguments: BotDifficulty.allCases)
    func 계획_합법성(difficulty: BotDifficulty) {
        var rng = SeededRNG(state: 7)
        let bot = BotPlayer(difficulty: difficulty)
        var state = GameState(playerCount: 1)
        var steps = 0
        while state.phase != .finished && steps < 500 {
            for intent in bot.plan(state, using: &rng) {
                #expect(state.allows(intent), "\(difficulty): \(intent)를 허용하지 않는 상태다")
                switch intent {
                case .roll: state = state.applying(.rolled(state.rollableIndices.map { _ in Int(rng.next() % 6) + 1 }))
                case .toggleHold(let i): state = state.applying(.holdToggled(i))
                case .commit(let c):
                    state = state.applying(.committed(c, c.score(state.dice)))
                    state = state.applying(state.isAllScored ? .gameEnded : .turnAdvanced)
                }
                steps += 1
            }
        }
        #expect(state.phase == .finished, "\(difficulty)가 12턴을 끝내지 못했다")
    }

    @Test("어려움은 쉬움보다 평균 점수가 높다 (40판)")
    func 난이도_차이() {
        func play(_ difficulty: BotDifficulty, seed: UInt64) -> Int {
            var rng = SeededRNG(state: seed)
            let bot = BotPlayer(difficulty: difficulty)
            var state = GameState(playerCount: 1)
            while state.phase != .finished {
                for intent in bot.plan(state, using: &rng) {
                    switch intent {
                    case .roll: state = state.applying(.rolled(state.rollableIndices.map { _ in Int(rng.next() % 6) + 1 }))
                    case .toggleHold(let i): state = state.applying(.holdToggled(i))
                    case .commit(let c):
                        state = state.applying(.committed(c, c.score(state.dice)))
                        state = state.applying(state.isAllScored ? .gameEnded : .turnAdvanced)
                    }
                }
            }
            return state.scorecards[0].total
        }
        let hard = (0..<40).map { play(.hard, seed: UInt64($0) + 100) }.reduce(0, +) / 40
        let easy = (0..<40).map { play(.easy, seed: UInt64($0) + 100) }.reduce(0, +) / 40
        #expect(hard > easy + 20, "어려움 \(hard) vs 쉬움 \(easy)")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --package-path Packages/YachtBot`
Expected: 컴파일 에러 (`BotPlayer` 없음).

- [ ] **Step 3: 구현**

`Packages/YachtBot/Sources/YachtBot/BotPlayer.swift`:

```swift
import Foundation
import YachtCore

/// 컴퓨터 상대. 상태를 보고 "다음 굴림 또는 기록까지"의 Intent 열을 돌려준다.
///
/// 한 번에 하나씩 돌려주지 않는 이유: 쉬움 난이도의 무작위 고정을 호출마다 새로 뽑으면
/// 고정을 켰다 껐다 반복할 수 있다. 목표 고정 집합을 한 번 정하고 거기까지의 토글을 다 돌려준다.
public struct BotPlayer: Sendable {
    public let difficulty: BotDifficulty

    public init(difficulty: BotDifficulty) {
        self.difficulty = difficulty
    }

    public func plan(_ state: GameState, using rng: inout some RandomNumberGenerator) -> [Intent] {
        guard state.phase != .finished else { return [] }
        if state.phase == .awaitingFirstRoll { return [.roll] }

        let card = state.scorecards[state.currentPlayer]
        if state.rollsRemaining == 0 {
            return [.commit(HandEvaluator.bestCommit(dice: state.dice, card: card).category)]
        }

        let target = holdSet(dice: state.dice, card: card, using: &rng)
        if target.count == state.dice.count {
            return [.commit(HandEvaluator.bestCommit(dice: state.dice, card: card).category)]
        }
        var intents: [Intent] = state.dice.indices
            .filter { state.held.contains($0) != target.contains($0) }
            .map { .toggleHold($0) }
        intents.append(.roll)
        return intents
    }

    // MARK: - 고정 집합

    func holdSet(dice: [Int], card: ScoreCard, using rng: inout some RandomNumberGenerator) -> Set<Int> {
        switch difficulty {
        case .hard:
            return HandEvaluator.bestHoldSet(dice: dice, card: card)
        case .normal:
            return Self.heuristicHold(dice: dice)
        case .easy:
            if Int(rng.next() % 100) < 40 {
                return Set(dice.indices.filter { _ in rng.next() % 2 == 0 })
            }
            return Self.mostFrequentHold(dice: dice)
        }
    }

    /// 보통: 4연속이 있으면 그것을, 아니면 가장 많은 눈을 고정한다. 다 같으면 전부.
    static func heuristicHold(dice: [Int]) -> Set<Int> {
        if let straight = straightHold(dice: dice) { return straight }
        return mostFrequentHold(dice: dice)
    }

    /// 가장 많이 나온 눈을 고정한다. 개수가 같으면 큰 눈.
    static func mostFrequentHold(dice: [Int]) -> Set<Int> {
        var counts = [Int](repeating: 0, count: 7)
        for face in dice { counts[face] += 1 }
        let face = (1...6).max { (counts[$0], $0) < (counts[$1], $1) }!
        return Set(dice.indices.filter { dice[$0] == face })
    }

    /// 1234 / 2345 / 3456 중 하나가 서로 다른 주사위로 채워지면 그 네 개를 고정한다.
    static func straightHold(dice: [Int]) -> Set<Int>? {
        for start in [2, 1, 3] {
            var chosen: Set<Int> = []
            for face in start..<(start + 4) {
                guard let index = dice.indices.first(where: { dice[$0] == face && !chosen.contains($0) }) else { break }
                chosen.insert(index)
            }
            if chosen.count == 4 { return chosen }
        }
        return nil
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --package-path Packages/YachtBot`
Expected: 전부 PASS. `난이도_차이`가 실패하면 40판 평균의 분산 때문일 수 있다 — 판 수를 100으로 올리고 차이 기준을 15로 낮춘다. 그래도 실패하면 어려움 봇이 실제로 약한 것이다.

- [ ] **Step 5: 커밋**

```sh
git add Packages/YachtBot
git commit -m "feat(bot): 난이도 3단계 봇 플레이어

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Participant, GameMode, MatchRecord와 저장 v2

**Files:**
- Create: `App/Game/Participant.swift`
- Modify: `App/Game/MatchStore.swift`
- Modify: `Tests/YachtDiceTests/MatchStoreTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum Participant: Codable, Equatable, Sendable {
      case human(name: String)
      case bot(BotDifficulty)
      case remote(playerID: String, name: String)
      var displayName: String
      var isHuman: Bool
  }
  enum GameMode: Codable, Equatable, Sendable {
      case solo
      case versusBot(BotDifficulty)
      case passAndPlay(names: [String])
      case online(matchID: String)
      var participants: [Participant]   // online은 빈 배열 — C에서 채운다
  }
  struct MatchRecord: Codable, Equatable, Sendable {
      static let formatVersion = 2
      var formatVersion: Int
      var mode: GameMode
      var participants: [Participant]
      var log: MatchLog
      init(mode: GameMode)                                   // participants = mode.participants, log = MatchLog(playerCount:)
      init(mode: GameMode, participants: [Participant], log: MatchLog)
      var isFinished: Bool
  }
  ```
  `MatchStore.save(_ record: MatchRecord)`, `MatchStore.load() -> MatchRecord?`. 기존 `save(_ log:)`/`load() -> MatchLog?`는 제거한다.

- [ ] **Step 1: 실패하는 테스트**

`Tests/YachtDiceTests/MatchStoreTests.swift`의 기존 테스트를 `MatchRecord` 기반으로 바꾸고 추가한다. 파일 전체:

```swift
import Testing
import Foundation
import YachtCore
import YachtBot
@testable import YachtDice

@Suite("진행 저장")
struct MatchStoreTests {

    private func makeTempStore() throws -> (MatchStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "yacht-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (MatchStore(directory: directory), directory)
    }

    @Test("저장한 기록을 그대로 읽는다 — 모드와 참가자까지")
    func 왕복() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var record = MatchRecord(mode: .versusBot(.hard))
        record.log.append(.rolled([6, 6, 6, 6, 6]))
        record.log.append(.committed(.yacht, 50))
        try store.save(record)

        let loaded = try #require(store.load())
        #expect(loaded == record)
        #expect(loaded.participants == [.human(name: "나"), .bot(.hard)])
        #expect(loaded.log.state.scorecards[0].entry(.yacht) == 50)
    }

    @Test("v1 파일(로그만)은 혼자 연습으로 읽는다")
    func v1_호환() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var log = MatchLog(playerCount: 1)
        log.append(.rolled([1, 2, 3, 4, 5]))
        try log.encoded().write(to: directory.appending(path: "match.json"))

        let loaded = try #require(store.load())
        #expect(loaded.mode == .solo)
        #expect(loaded.participants == [.human(name: "나")])
        #expect(loaded.log == log)
    }

    @Test("참가자 수와 로그의 플레이어 수가 다르면 버린다")
    func 불일치_거부() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let record = MatchRecord(mode: .passAndPlay(names: ["A", "B"]),
                                 participants: [.human(name: "A")],
                                 log: MatchLog(playerCount: 2))
        let data = try JSONEncoder().encode(record)
        try data.write(to: directory.appending(path: "match.json"))
        #expect(store.load() == nil)
    }

    @Test("저장한 적이 없으면 nil이다")
    func 없음() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.load() == nil)
    }

    @Test("clear하면 사라진다")
    func 삭제() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.save(MatchRecord(mode: .solo))
        try store.clear()
        #expect(store.load() == nil)
    }

    @Test("끝난 게임은 저장하지 않고 기존 파일도 지운다")
    func 끝난_게임() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.save(MatchRecord(mode: .solo))

        var record = MatchRecord(mode: .solo)
        for category in ScoreCategory.allCases {
            record.log.append(.rolled([1, 1, 1, 1, 1]))
            record.log.append(.committed(category, category.score([1, 1, 1, 1, 1])))
            record.log.append(record.log.state.applying(.committed(category, 0)).isAllScored ? .gameEnded : .turnAdvanced)
        }
        #expect(record.isFinished)
        try store.save(record)
        #expect(store.load() == nil)
    }

    @Test("패스앤플레이 참가자는 이름 순서대로다")
    func 패스앤플레이_참가자() {
        let record = MatchRecord(mode: .passAndPlay(names: ["철수", "영희", "민수"]))
        #expect(record.participants == [.human(name: "철수"), .human(name: "영희"), .human(name: "민수")])
        #expect(record.log.playerCount == 3)
    }
}
```

`끝난_게임` 테스트의 마지막 이벤트 계산이 복잡하면 기존 `MatchStoreTests`에 있던 종료 로그 생성 코드를 그대로 쓴다 (기존 파일의 해당 테스트 참고).

- [ ] **Step 2: 실패 확인**

Run: `-only-testing:YachtDiceTests/MatchStoreTests`
Expected: 컴파일 에러.

- [ ] **Step 3: 구현**

`App/Game/Participant.swift`:

```swift
import Foundation
import YachtCore
import YachtBot

/// 좌석 하나. 순서는 GameState.currentPlayer와 같다.
enum Participant: Codable, Equatable, Sendable {
    case human(name: String)
    case bot(BotDifficulty)
    /// 다른 기기의 사람. P3(온라인)에서 채운다.
    case remote(playerID: String, name: String)

    var displayName: String {
        switch self {
        case .human(let name): name
        case .bot(let difficulty): "컴퓨터 (\(difficulty.displayName))"
        case .remote(_, let name): name
        }
    }

    var isHuman: Bool {
        if case .human = self { return true }
        return false
    }
}

enum GameMode: Codable, Equatable, Sendable {
    case solo
    case versusBot(BotDifficulty)
    case passAndPlay(names: [String])
    case online(matchID: String)

    /// 이 모드의 좌석 배치. 온라인은 매치가 잡힌 뒤에야 알 수 있어 비어 있다.
    var participants: [Participant] {
        switch self {
        case .solo: [.human(name: "나")]
        case .versusBot(let difficulty): [.human(name: "나"), .bot(difficulty)]
        case .passAndPlay(let names): names.map { .human(name: $0) }
        case .online: []
        }
    }

    var title: String {
        switch self {
        case .solo: "혼자 연습"
        case .versusBot(let difficulty): "컴퓨터 대전 · \(difficulty.displayName)"
        case .passAndPlay(let names): "\(names.count)인 대전"
        case .online: "온라인 대전"
        }
    }
}

/// 저장·복원의 단위. 로그만으로는 상대가 누구였는지 알 수 없다.
struct MatchRecord: Codable, Equatable, Sendable {
    static let formatVersion = 2

    var formatVersion: Int
    var mode: GameMode
    var participants: [Participant]
    var log: MatchLog

    init(mode: GameMode) {
        let participants = mode.participants
        precondition(!participants.isEmpty, "참가자가 없는 모드로는 기록을 만들 수 없다: \(mode)")
        self.init(mode: mode, participants: participants, log: MatchLog(playerCount: participants.count))
    }

    init(mode: GameMode, participants: [Participant], log: MatchLog) {
        self.formatVersion = Self.formatVersion
        self.mode = mode
        self.participants = participants
        self.log = log
    }

    var isFinished: Bool { log.isFinished }
}
```

`App/Game/MatchStore.swift` 전체:

```swift
import Foundation
import YachtCore

/// 진행 중인 판을 파일 하나로 보관한다.
/// 이벤트 소싱이라 저장할 것이 로그와 "누구와 어떤 모드로"뿐이고, 복원은 리플레이다.
struct MatchStore: Sendable {
    private let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appending(path: "match.json")
    }

    static var `default`: MatchStore {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return MatchStore(directory: directory)
    }

    /// 끝난 게임은 저장하지 않는다. 복원했을 때 결과 화면에 갇히기 때문이다.
    func save(_ record: MatchRecord) throws {
        guard !record.isFinished else {
            try clear()
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: fileURL, options: .atomic)
    }

    /// 읽기 실패는 오류로 올리지 않는다. 저장 파일 하나 때문에 앱이 시작조차
    /// 못 하는 것보다, 새 판으로 시작하는 편이 낫다. 그래서 throws가 아니다.
    ///
    /// v1 파일(`MatchLog`만 있던 형식)은 혼자 연습으로 읽는다.
    func load() -> MatchRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return nil }

        if let record = try? JSONDecoder().decode(MatchRecord.self, from: data) {
            guard record.formatVersion == MatchRecord.formatVersion,
                  record.participants.count == record.log.playerCount,
                  // 로그는 신뢰 경계다. 디코더가 아니라 canApply로 끝까지 재생해 본다.
                  let log = try? MatchLog.decoded(from: (try? record.log.encoded()) ?? Data()),
                  !log.isFinished
            else { return nil }
            return MatchRecord(mode: record.mode, participants: record.participants, log: log)
        }

        guard let log = try? MatchLog.decoded(from: data), !log.isFinished, log.playerCount == 1 else { return nil }
        return MatchRecord(mode: .solo, participants: GameMode.solo.participants, log: log)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
```

`YachtDiceTests` 타깃도 `YachtBot`을 import하므로 `project.yml`의 테스트 타깃은 앱 타깃 의존으로 충분하다(패키지가 앱에 링크됨). 컴파일이 안 되면 `YachtDiceTests`의 `dependencies:`에 `- package: YachtBot`을 추가한다.

- [ ] **Step 4: 통과 확인**

Run: `-only-testing:YachtDiceTests/MatchStoreTests`
Expected: 전부 PASS. 이 시점에 `AppContainer`와 `GameSession`이 `save(_ log:)`를 써서 앱 빌드가 깨진다 — Task 6·7에서 고친다. 테스트 타깃만 먼저 컴파일되게 하려면 `AppContainer.swift`의 `try? store.save(log)`를 임시로 `try? store.save(MatchRecord(mode: .solo, participants: GameMode.solo.participants, log: log))`로, `store.load()`의 결과를 `?.log`로 바꾼다.

- [ ] **Step 5: 커밋**

```sh
git add App/Game/Participant.swift App/Game/MatchStore.swift App/AppContainer.swift Tests/YachtDiceTests/MatchStoreTests.swift project.yml
git commit -m "feat(game): 참가자·모드를 담는 MatchRecord로 저장 형식을 올린다

로그만으로는 상대가 컴퓨터였는지 사람이었는지 알 수 없다. v1 파일은 혼자 연습으로 읽는다.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: GameSession — 차례 소유, 봇 턴, 핸드오프

**Files:**
- Modify: `App/Game/GameSession.swift`
- Modify: `Tests/YachtDiceTests/GameSessionTests.swift`

**Interfaces:**
- Consumes: `MatchRecord`, `Participant`, `BotPlayer.plan(_:using:)`.
- Produces (GameSession):
  ```swift
  init(driver: any MatchDriver, stage: DiceStage, record: MatchRecord)
  convenience init(driver:stage:log:)   // 테스트 호환: MatchRecord(mode: .solo, participants: solo, log:)
  var record: MatchRecord { get }
  var participants: [Participant] { get }
  var currentParticipant: Participant { get }
  /// 이 기기의 사람이 지금 입력할 수 있는가. 봇·원격 차례, 핸드오프 대기, 종료면 거짓.
  var isLocalTurn: Bool { get }
  /// 패스앤플레이에서 기기를 넘기는 동안 참. acknowledgeHandoff()로 푼다.
  private(set) var pendingHandoff: Bool
  func acknowledgeHandoff()
  /// 봇 차례가 끝날 때까지 기다린다 (테스트·UI 상태 표시용).
  func waitForBotTurn() async
  var onLogChanged: (@Sendable (MatchRecord) -> Void)?   // MatchLog → MatchRecord
  func startNewGame()   // 같은 모드로
  ```

- [ ] **Step 1: 실패하는 테스트**

`Tests/YachtDiceTests/GameSessionTests.swift`에 새 스위트를 추가한다 (기존 스위트는 `log:` 편의 이니셜라이저로 그대로 통과해야 한다). `import YachtBot` 추가.

```swift
@Suite("게임 세션 - 참가자")
@MainActor
struct GameSessionParticipantTests {

    private struct ConstantDriver: MatchDriver {
        let face: Int
        func requestRoll(count: Int) async throws -> [Int] { Array(repeating: face, count: count) }
        func submit(_ event: Event) async throws {}
        var incoming: AsyncStream<Event> { AsyncStream { $0.finish() } }
    }

    private func makeSession(mode: GameMode, face: Int = 3) throws -> GameSession {
        let session = GameSession(driver: ConstantDriver(face: face),
                                  stage: DiceStage(library: try TrajectoryLibrary.bundled()),
                                  record: MatchRecord(mode: mode))
        session.reduceMotion = true
        return session
    }

    @Test("혼자 연습은 항상 내 차례이고 핸드오프가 없다")
    func 혼자() async throws {
        let session = try makeSession(mode: .solo)
        #expect(session.isLocalTurn)
        await session.send(.roll)
        await session.send(.commit(.threes))
        #expect(session.isLocalTurn)
        #expect(!session.pendingHandoff)
    }

    @Test("내 턴이 끝나면 봇이 자기 턴을 끝까지 두고 차례가 돌아온다")
    func 봇_턴() async throws {
        let session = try makeSession(mode: .versusBot(.normal))
        #expect(session.isLocalTurn)
        await session.send(.roll)
        await session.send(.commit(.threes))
        #expect(!session.isLocalTurn, "봇 차례인데 입력이 열려 있다")

        await session.waitForBotTurn()
        #expect(session.visibleState.currentPlayer == 0)
        #expect(session.visibleState.turnIndex == 2)
        #expect(session.visibleState.scorecards[1].openCategories.count == 11, "봇이 기록하지 않았다")
        #expect(session.isLocalTurn)
    }

    @Test("봇 차례에는 send가 거부된다")
    func 봇_차례_잠금() async throws {
        let session = try makeSession(mode: .versusBot(.easy))
        await session.send(.roll)
        await session.send(.commit(.threes))
        let before = session.visibleState
        await session.send(.roll)   // 봇 차례에 끼어들기
        #expect(session.visibleState.currentPlayer == before.currentPlayer)
        await session.waitForBotTurn()
    }

    @Test("패스앤플레이는 사람 차례가 바뀔 때 핸드오프를 기다린다")
    func 핸드오프() async throws {
        let session = try makeSession(mode: .passAndPlay(names: ["A", "B"]))
        await session.send(.roll)
        await session.send(.commit(.threes))
        #expect(session.pendingHandoff)
        #expect(!session.isLocalTurn)
        #expect(session.currentParticipant == .human(name: "B"))

        await session.send(.roll)
        #expect(session.visibleState.rollsRemaining == 3, "핸드오프 중에 굴려졌다")

        session.acknowledgeHandoff()
        #expect(session.isLocalTurn)
        await session.send(.roll)
        #expect(session.visibleState.rollsRemaining == 2)
    }

    @Test("4인 패스앤플레이 12턴 완주")
    func 사인_완주() async throws {
        let session = try makeSession(mode: .passAndPlay(names: ["A", "B", "C", "D"]))
        for category in ScoreCategory.allCases {
            for _ in 0..<4 {
                if session.pendingHandoff { session.acknowledgeHandoff() }
                await session.send(.roll)
                await session.send(.commit(category))
            }
        }
        #expect(session.visibleState.phase == .finished)
        #expect(session.visibleState.scorecards.allSatisfy(\.isComplete))
    }

    @Test("복원한 판의 현재 차례가 봇이면 바로 봇이 둔다")
    func 복원_봇_차례() async throws {
        var record = MatchRecord(mode: .versusBot(.normal))
        record.log.append(.rolled([3, 3, 3, 3, 3]))
        record.log.append(.committed(.threes, 15))
        record.log.append(.turnAdvanced)
        let session = GameSession(driver: ConstantDriver(face: 2),
                                  stage: DiceStage(library: try TrajectoryLibrary.bundled()),
                                  record: record)
        session.reduceMotion = true
        session.resumeTurnOwner()
        await session.waitForBotTurn()
        #expect(session.visibleState.currentPlayer == 0)
    }

    @Test("onLogChanged는 모드를 담은 기록을 준다")
    func 저장_콜백() async throws {
        let session = try makeSession(mode: .versusBot(.hard))
        var saved: MatchRecord?
        session.onLogChanged = { saved = $0 }
        await session.send(.roll)
        #expect(saved?.mode == .versusBot(.hard))
        #expect(saved?.log.events.count == 1)
    }
}
```

`저장_콜백`에서 `saved`를 클로저에서 바꾸는 것은 `@Sendable` 때문에 컴파일되지 않을 수 있다. 그럴 때는 `final class Box: @unchecked Sendable { var value: MatchRecord? }`로 감싼다.

- [ ] **Step 2: 실패 확인**

Run: `-only-testing:YachtDiceTests/GameSessionParticipantTests`
Expected: 컴파일 에러 (`record:` 이니셜라이저 없음).

- [ ] **Step 3: 구현**

`App/Game/GameSession.swift` 전체:

```swift
import Foundation
import Observation
import YachtCore
import YachtBot
import DiceTrajectory

/// 코어·드라이버·3D 연출을 잇는 유일한 오케스트레이터.
///
/// 핵심: 상태는 이벤트 발생 즉시 전이하지만, 화면에 노출되는 visibleState는
/// 주사위가 착지한 뒤에야 갱신된다. 점수판 미리보기가 주사위보다 먼저 뜨면
/// 게임이 망가진다 (스펙 §8.2).
///
/// 봇과 사람은 같은 `perform(_:)` 경로를 탄다. 사람의 `send(_:)`는 그 앞에 "지금 내 차례인가"만 더한다.
@MainActor
@Observable
final class GameSession {
    private let driver: any MatchDriver
    private let stage: DiceStage
    private(set) var record: MatchRecord

    /// 뷰가 보는 상태. 연출이 끝난 뒤에만 갱신된다.
    private(set) var visibleState: GameState
    /// 연출 중이거나 드라이버를 기다리는 중이면 참. 입력을 잠그는 데 쓴다.
    private(set) var isBusy = false
    /// 패스앤플레이에서 기기를 넘기는 동안 참.
    private(set) var pendingHandoff = false
    var assistEnabled = true
    var reduceMotion = false
    /// 다음 굴림에 쓸 던지는 방향. 제스처가 설정하고 performRoll이 소비한다.
    var nextThrowDirection: ThrowDirection?

    var onLogChanged: (@Sendable (MatchRecord) -> Void)?
    var onCollisionCues: (@MainActor ([CollisionCue]) -> Void)?

    private var botTask: Task<Void, Never>?

    init(driver: any MatchDriver, stage: DiceStage, record: MatchRecord) {
        precondition(record.participants.count == record.log.playerCount,
                     "참가자 \(record.participants.count)명과 로그의 \(record.log.playerCount)명이 다르다")
        self.driver = driver
        self.stage = stage
        self.record = record
        self.visibleState = record.log.state
    }

    /// 테스트 호환. 혼자 연습 기록으로 감싼다.
    convenience init(driver: any MatchDriver, stage: DiceStage, log: MatchLog) {
        self.init(driver: driver, stage: stage,
                  record: MatchRecord(mode: .solo, participants: GameMode.solo.participants, log: log))
    }

    var participants: [Participant] { record.participants }
    var currentParticipant: Participant { participants[visibleState.currentPlayer] }

    /// 이 기기의 사람이 지금 입력할 수 있는가.
    var isLocalTurn: Bool {
        guard visibleState.phase != .finished, !pendingHandoff else { return false }
        return currentParticipant.isHuman
    }

    /// 사람의 입력. 내 차례가 아니면 버린다.
    func send(_ intent: Intent) async {
        guard isLocalTurn else {
            if case .roll = intent { nextThrowDirection = nil }
            return
        }
        await perform(intent)
    }

    func acknowledgeHandoff() {
        pendingHandoff = false
    }

    /// 복원 직후 현재 차례의 주인에게 진행을 넘긴다. 봇이면 바로 둔다.
    func resumeTurnOwner() {
        scheduleTurnOwner(announceHandoff: false)
    }

    func waitForBotTurn() async {
        await botTask?.value
    }

    /// 끝난 판을 접고 같은 모드로 새 판을 시작한다.
    func startNewGame() {
        guard !isBusy, visibleState.phase == .finished else { return }
        record = MatchRecord(mode: record.mode, participants: record.participants,
                             log: MatchLog(playerCount: record.participants.count))
        visibleState = record.log.state
        nextThrowDirection = nil
        pendingHandoff = false
        stage.reset()
        onLogChanged?(record)
        scheduleTurnOwner(announceHandoff: false)
    }

    /// Assist가 켜져 있고 아직 비어 있는 칸에 대해서만 예상 점수를 준다.
    func previewScore(_ category: ScoreCategory) -> Int? {
        guard assistEnabled,
              visibleState.phase == .rolling,
              !visibleState.scorecards[visibleState.currentPlayer].isFilled(category)
        else { return nil }
        return category.score(visibleState.dice)
    }

    // MARK: - 내부

    /// 출처를 가리지 않는 실제 실행 경로. 봇도 여기로 들어온다.
    private func perform(_ intent: Intent) async {
        guard !isBusy, visibleState.allows(intent) else {
            // 굴리지 못하고 되돌아가면 이번 스와이프의 방향은 버린다.
            if case .roll = intent { nextThrowDirection = nil }
            return
        }
        isBusy = true
        defer { isBusy = false }

        switch intent {
        case .roll:
            await performRoll()
        case .toggleHold(let index):
            await commitEvents([.holdToggled(index)])
            stage.placeHeld(visibleState.held.sorted(), values: visibleState.dice)
        case .commit(let category):
            let points = category.score(visibleState.dice)
            var events: [Event] = [.committed(category, points)]
            let afterCommit = visibleState.applying(events[0])
            events.append(afterCommit.isAllScored ? .gameEnded : .turnAdvanced)
            await commitEvents(events)
            if !visibleState.isAllScored {
                stage.reset()
                scheduleTurnOwner(announceHandoff: true)
            }
        }
    }

    /// 새 차례의 주인에 따라 다음 일을 정한다.
    /// - 봇: 자기 턴을 Task로 둔다.
    /// - 사람 (2인 이상): 기기를 넘기도록 핸드오프를 띄운다.
    /// - 원격: P3에서 채운다.
    private func scheduleTurnOwner(announceHandoff: Bool) {
        guard visibleState.phase != .finished else { return }
        switch currentParticipant {
        case .bot(let difficulty):
            botTask = Task { [weak self] in await self?.runBotTurn(difficulty) }
        case .human:
            if announceHandoff && participants.count > 1 { pendingHandoff = true }
        case .remote:
            break
        }
    }

    private func runBotTurn(_ difficulty: BotDifficulty) async {
        let bot = BotPlayer(difficulty: difficulty)
        var rng = SystemRandomNumberGenerator()
        let owner = visibleState.currentPlayer
        var guardCounter = 0
        while visibleState.currentPlayer == owner, visibleState.phase != .finished, guardCounter < 40 {
            let plan = bot.plan(visibleState, using: &rng)
            guard !plan.isEmpty else { break }
            for intent in plan {
                guard visibleState.allows(intent) else { return }
                await think()
                await perform(intent)
                guardCounter += 1
            }
        }
    }

    /// 사람처럼 잠깐 뜸을 들인다. Reduce Motion이면 거의 바로.
    private func think() async {
        let delay: Duration = reduceMotion ? .milliseconds(10) : .milliseconds(Int.random(in: 350...700))
        try? await Task.sleep(for: delay)
    }

    private func performRoll() async {
        let slots = visibleState.rollableIndices
        guard let values = try? await driver.requestRoll(count: slots.count) else { return }

        // 상태는 즉시 전이시키되 화면에는 아직 노출하지 않는다
        let pending = visibleState.applying(.rolled(values))

        let direction = nextThrowDirection ?? ThrowDirection.allCases.randomElement() ?? .center
        nextThrowDirection = nil
        let cues = await stage.roll(values: values, slots: slots,
                                    direction: direction, skipAnimation: reduceMotion)
        onCollisionCues?(cues)

        // 착지한 뒤에 노출한다
        record.log.append(.rolled(values))
        visibleState = pending
        try? await driver.submit(.rolled(values))
        onLogChanged?(record)
    }

    private func commitEvents(_ events: [Event]) async {
        var state = visibleState
        for event in events {
            record.log.append(event)
            state = state.applying(event)
            try? await driver.submit(event)
        }
        visibleState = state
        onLogChanged?(record)
    }
}
```

`AppContainer.swift`의 `session.onLogChanged = { log in try? store.save(log) }`는 이제 `MatchRecord`를 받으므로 그대로 컴파일된다 (Task 5의 임시 변환을 제거한다). 복원 코드는 `store.load()`가 `MatchRecord?`를 주므로 `GameSession(driver:stage:record:)`를 쓰고, `seatRestoredDice` 뒤에 `session.resumeTurnOwner()`를 부른다.

- [ ] **Step 4: 통과 확인**

Run: `-only-testing:YachtDiceTests`
Expected: 기존 `GameSessionTests` 포함 전부 PASS. `봇_턴`이 멈추면(타임아웃) `runBotTurn`의 `perform`이 `isBusy` 때문에 거부되고 있는지 본다 — 봇 Task는 사람의 `send`가 끝난 뒤(`defer { isBusy = false }` 이후)에 시작되어야 한다. `scheduleTurnOwner`가 `perform` 안에서 불리므로 Task는 그 다음 틱에 돈다. 그래도 겹치면 `runBotTurn` 첫 줄에 `await Task.yield()`를 넣는다.

- [ ] **Step 5: 커밋**

```sh
git add App/Game/GameSession.swift App/AppContainer.swift Tests/YachtDiceTests/GameSessionTests.swift
git commit -m "feat(game): 좌석마다 사람·봇을 두고 봇이 자기 턴을 둔다

봇은 사람과 같은 perform 경로를 타서 3D 연출과 점수판 지연이 동일하다.
패스앤플레이는 사람 차례가 바뀔 때 핸드오프로 입력을 막아 기기를 넘길 시간을 준다.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: 시작 메뉴와 AppContainer 상태

**Files:**
- Modify: `App/AppContainer.swift`
- Modify: `App/YachtDiceApp.swift`
- Create: `App/Views/MenuScreen.swift`
- Test: `Tests/YachtDiceTests/AppContainerTests.swift` (새로)

**Interfaces:**
- Produces (AppContainer):
  ```swift
  enum Status { case menu, playing(GameSession), failed(String) }
  private(set) var status: Status
  let stage: DiceStage?                 // 한 번 만들어 재사용
  var savedRecord: MatchRecord?         // 메뉴의 "이어하기" 표시용
  func startGame(mode: GameMode)
  func resumeSavedGame()
  func returnToMenu()
  ```
- 접근성 식별자: `menu.solo`, `menu.bot`, `menu.bot.<easy|normal|hard>`, `menu.local`, `menu.local.count.<2|3|4>`, `menu.local.start`, `menu.online`, `menu.resume`.

- [ ] **Step 1: 실패하는 테스트**

`Tests/YachtDiceTests/AppContainerTests.swift`:

```swift
import Testing
import Foundation
import YachtCore
import YachtBot
@testable import YachtDice

@Suite("앱 컨테이너")
@MainActor
struct AppContainerTests {

    private func makeStore() throws -> (MatchStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "yacht-container-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (MatchStore(directory: directory), directory)
    }

    @Test("저장된 판이 없으면 메뉴에서 시작한다")
    func 메뉴_시작() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = AppContainer(store: store, arguments: [])
        guard case .menu = container.status else { Issue.record("메뉴가 아니다: \(container.status)"); return }
        #expect(container.savedRecord == nil)
    }

    @Test("모드를 고르면 그 모드의 세션이 만들어지고 저장된다")
    func 게임_시작() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = AppContainer(store: store, arguments: [])
        container.startGame(mode: .versusBot(.easy))
        guard case .playing(let session) = container.status else { Issue.record("게임이 아니다"); return }
        #expect(session.participants == [.human(name: "나"), .bot(.easy)])
        session.reduceMotion = true
        await session.send(.roll)
        #expect(store.load()?.mode == .versusBot(.easy))
    }

    @Test("저장된 판이 있으면 메뉴에 이어하기가 뜨고, 이어하면 그 판이다")
    func 이어하기() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        var record = MatchRecord(mode: .passAndPlay(names: ["A", "B"]))
        record.log.append(.rolled([1, 2, 3, 4, 5]))
        try store.save(record)

        let container = AppContainer(store: store, arguments: [])
        #expect(container.savedRecord?.mode == .passAndPlay(names: ["A", "B"]))
        container.resumeSavedGame()
        guard case .playing(let session) = container.status else { Issue.record("게임이 아니다"); return }
        #expect(session.visibleState.dice == [1, 2, 3, 4, 5])
        #expect(session.participants.count == 2)
    }

    @Test("-resetMatch 인자는 저장을 지운다")
    func 리셋_인자() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.save(MatchRecord(mode: .solo))
        let container = AppContainer(store: store, arguments: ["-resetMatch"])
        #expect(container.savedRecord == nil)
    }

    @Test("메뉴로 돌아가면 진행 중인 판은 저장된 채 남는다")
    func 메뉴_복귀() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = AppContainer(store: store, arguments: [])
        container.startGame(mode: .solo)
        guard case .playing(let session) = container.status else { Issue.record("게임이 아니다"); return }
        session.reduceMotion = true
        await session.send(.roll)
        container.returnToMenu()
        guard case .menu = container.status else { Issue.record("메뉴가 아니다"); return }
        #expect(container.savedRecord?.log.events.count == 1)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `-only-testing:YachtDiceTests/AppContainerTests`
Expected: 컴파일 에러.

- [ ] **Step 3: 구현**

`App/AppContainer.swift` 전체:

```swift
import Foundation
import Observation
import YachtCore

/// 앱 조립을 한 곳에 모은다. 씬(DiceStage)은 무겁고 게임마다 같으므로 한 번만 만든다.
@MainActor
@Observable
final class AppContainer {
    enum Status {
        case menu
        case playing(GameSession)
        case failed(String)
    }

    private(set) var status: Status
    /// 메뉴의 "이어하기"에 보여줄 저장된 판.
    private(set) var savedRecord: MatchRecord?

    private let store: MatchStore
    private let stage: DiceStage?

    init(store: MatchStore = .default,
         arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.store = store
        // UI 테스트가 깨끗한 상태에서 시작할 수 있게 한다
        if arguments.contains("-resetMatch") {
            try? store.clear()
        }
        do {
            stage = DiceStage(library: try TrajectoryLibrary.bundled())
            status = .menu
        } catch {
            stage = nil
            status = .failed("주사위 데이터를 읽지 못했습니다: \(error)")
        }
        savedRecord = store.load()
    }

    func startGame(mode: GameMode) {
        try? store.clear()
        savedRecord = nil
        launch(MatchRecord(mode: mode))
    }

    func resumeSavedGame() {
        guard let record = savedRecord ?? store.load() else { return }
        launch(record)
    }

    func returnToMenu() {
        savedRecord = store.load()
        status = .menu
    }

    private func launch(_ record: MatchRecord) {
        guard let stage else { return }
        stage.reset()
        let session = GameSession(driver: LocalDriver(), stage: stage, record: record)
        let store = store
        session.onLogChanged = { record in try? store.save(record) }

        // 복원한 판이면 주사위를 마지막 상태로 앉힌다. 그림은 즉시 확정되지만
        // roll()이 async라 한 틱 뒤에 실행된다 — 첫 입력보다는 항상 먼저다.
        let state = record.log.state
        if state.phase == .rolling {
            Task { @MainActor in
                _ = await stage.roll(values: state.dice, slots: Array(0..<YachtCore.diceCount),
                                     direction: .center, skipAnimation: true)
                stage.placeHeld(state.held.sorted(), values: state.dice)
                session.resumeTurnOwner()
            }
        } else {
            session.resumeTurnOwner()
        }
        status = .playing(session)
    }
}
```

`App/YachtDiceApp.swift`:

```swift
import SwiftUI

@main
struct YachtDiceApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            switch container.status {
            case .menu:
                MenuScreen(container: container)
            case .playing(let session):
                GameScreen(session: session, onReturnToMenu: { container.returnToMenu() })
            case .failed(let message):
                ContentUnavailableView("시작할 수 없습니다", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            }
        }
    }
}
```

`GameScreen`은 Task 8에서 `stage`를 세션에서 받도록 바꾼다. 이 태스크에서는 `GameScreen(session:stage:)` 시그니처를 유지하려면 `AppContainer`에 `var currentStage: DiceStage? { stage }`를 열어 `GameScreen(session: session, stage: container.currentStage!)`로 넘긴다. Task 8에서 정리한다.

`App/Views/MenuScreen.swift`:

```swift
import SwiftUI
import YachtBot

struct MenuScreen: View {
    let container: AppContainer

    @State private var localPlayerCount = 2
    @State private var localNames = ["플레이어 1", "플레이어 2", "플레이어 3", "플레이어 4"]
    @State private var showingBotPicker = false
    @State private var showingLocalSetup = false

    var body: some View {
        NavigationStack {
            List {
                if let saved = container.savedRecord {
                    Section {
                        Button {
                            container.resumeSavedGame()
                        } label: {
                            Label("이어하기 · \(saved.mode.title) · Turn \(saved.log.state.turnIndex)/12",
                                  systemImage: "play.fill")
                        }
                        .accessibilityIdentifier("menu.resume")
                    }
                }

                Section("새 게임") {
                    Button { container.startGame(mode: .solo) } label: {
                        Label("혼자 연습", systemImage: "person")
                    }
                    .accessibilityIdentifier("menu.solo")

                    Button { showingBotPicker = true } label: {
                        Label("컴퓨터 대전", systemImage: "cpu")
                    }
                    .accessibilityIdentifier("menu.bot")

                    Button { showingLocalSetup = true } label: {
                        Label("로컬 2~4인", systemImage: "person.2")
                    }
                    .accessibilityIdentifier("menu.local")

                    Button {} label: {
                        Label("온라인 대전 (준비 중)", systemImage: "network")
                    }
                    .disabled(true)
                    .accessibilityIdentifier("menu.online")
                }
            }
            .navigationTitle("요트 다이스")
            .confirmationDialog("난이도", isPresented: $showingBotPicker, titleVisibility: .visible) {
                ForEach(BotDifficulty.allCases, id: \.self) { difficulty in
                    Button(difficulty.displayName) { container.startGame(mode: .versusBot(difficulty)) }
                        .accessibilityIdentifier("menu.bot.\(difficulty.rawValue)")
                }
            }
            .sheet(isPresented: $showingLocalSetup) { localSetup }
        }
    }

    private var localSetup: some View {
        NavigationStack {
            Form {
                Picker("인원", selection: $localPlayerCount) {
                    ForEach(2...4, id: \.self) { count in
                        Text("\(count)명").tag(count).accessibilityIdentifier("menu.local.count.\(count)")
                    }
                }
                .pickerStyle(.segmented)
                ForEach(0..<localPlayerCount, id: \.self) { index in
                    TextField("플레이어 \(index + 1)", text: $localNames[index])
                        .accessibilityIdentifier("menu.local.name.\(index)")
                }
            }
            .navigationTitle("로컬 대전")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("시작") {
                        showingLocalSetup = false
                        let names = localNames.prefix(localPlayerCount).map {
                            $0.trimmingCharacters(in: .whitespaces).isEmpty ? "플레이어" : $0
                        }
                        container.startGame(mode: .passAndPlay(names: Array(names)))
                    }
                    .accessibilityIdentifier("menu.local.start")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { showingLocalSetup = false }
                }
            }
        }
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `-only-testing:YachtDiceTests`
Expected: 전부 PASS. 앱 빌드도 성공해야 한다.

- [ ] **Step 5: 커밋**

```sh
git add App/AppContainer.swift App/YachtDiceApp.swift App/Views/MenuScreen.swift Tests/YachtDiceTests/AppContainerTests.swift
git commit -m "feat(ui): 시작 메뉴에서 모드를 고르고 저장된 판을 이어한다

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: 게임 화면 — 참가자 띠, 핸드오프, 다인 결과

**Files:**
- Create: `App/Views/PlayerStrip.swift`
- Create: `App/Views/HandoffOverlay.swift`
- Modify: `App/Views/GameScreen.swift`
- Modify: `App/Views/GameOverBar.swift`
- Modify: `App/Views/ActionBarView.swift`, `App/Views/ScoreboardView.swift` (입력 잠금 조건에 `isLocalTurn`)
- Modify: `App/AppContainer.swift` (`currentStage` 제거), `App/YachtDiceApp.swift`

**Interfaces:**
- `GameScreen(session:stage:onReturnToMenu:)`
- 접근성 식별자: `players.seat.<index>` (라벨 "이름, 총점 N점, 현재 차례"), `handoff.start`, `result.rank.<index>`, `result.menu`, `header.status` ("컴퓨터가 생각 중" / "상대 차례").

- [ ] **Step 1: 뷰 구현** (뷰는 UI 테스트가 검증한다 — Task 9)

`App/Views/PlayerStrip.swift`:

```swift
import SwiftUI
import YachtCore

/// 좌석별 이름과 총점. 현재 차례를 강조한다. 2인 이상일 때만 보인다.
struct PlayerStrip: View {
    let session: GameSession

    var body: some View {
        HStack(spacing: 8) {
            ForEach(session.participants.indices, id: \.self) { index in
                let participant = session.participants[index]
                let total = session.visibleState.scorecards[index].total
                let isCurrent = session.visibleState.currentPlayer == index
                    && session.visibleState.phase != .finished
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        if case .bot = participant { Image(systemName: "cpu").font(.caption2) }
                        Text(participant.displayName).font(.caption).lineLimit(1)
                    }
                    Text("\(total)").font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isCurrent ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("players.seat.\(index)")
                .accessibilityLabel("\(participant.displayName), 총점 \(total)점\(isCurrent ? ", 현재 차례" : "")")
            }
        }
        .padding(.horizontal, 16)
    }
}
```

`App/Views/HandoffOverlay.swift`:

```swift
import SwiftUI

/// 패스앤플레이에서 다음 사람에게 기기를 넘기는 동안 점수판을 가린다.
struct HandoffOverlay: View {
    let playerName: String
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.left.arrow.right").font(.largeTitle)
            Text("다음 차례").font(.headline).foregroundStyle(.secondary)
            Text(playerName).font(.system(.title, design: .rounded).weight(.bold))
            Button("시작", action: onStart)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("handoff.start")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .accessibilityAddTraits(.isModal)
    }
}
```

`App/Views/GameScreen.swift` 전체:

```swift
import SwiftUI
import YachtCore
import DiceTrajectory

struct GameScreen: View {
    let session: GameSession
    let stage: DiceStage
    var onReturnToMenu: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                if session.participants.count > 1 {
                    PlayerStrip(session: session).padding(.bottom, 6)
                }
                DiceStageView(stage: stage) { slot in
                    Task { await session.send(.toggleHold(slot)) }
                }
                .frame(height: geometry.size.height * (session.participants.count > 1 ? 0.38 : 0.42))
                .contentShape(Rectangle())
                .gesture(throwGesture)
                Group {
                    if session.visibleState.phase == .finished {
                        GameOverBar(session: session, onReturnToMenu: onReturnToMenu)
                    } else {
                        ActionBarView(session: session)
                    }
                }
                .padding(.vertical, 10)
                Divider()
                ScrollView {
                    ScoreboardView(session: session)
                }
            }
            .overlay {
                if session.pendingHandoff {
                    HandoffOverlay(playerName: session.currentParticipant.displayName) {
                        session.acknowledgeHandoff()
                    }
                }
            }
        }
        .onChange(of: reduceMotion, initial: true) { _, newValue in
            session.reduceMotion = newValue
        }
    }

    private var header: some View {
        HStack {
            Button {
                onReturnToMenu()
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityIdentifier("header.menu")
            .accessibilityLabel("메뉴로")
            // combine을 이 Group에만 걸어서 header.turn의 label이 항상 턴 텍스트가 되게 한다.
            Group {
                Text("Turn \(session.visibleState.turnIndex)/\(YachtCore.turnCount)")
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("header.turn")
            .accessibilityRemoveTraits(.isStaticText)
            Spacer()
            if session.visibleState.phase == .finished {
                Text("게임 종료").font(.headline).foregroundStyle(.green)
            } else if case .bot = session.currentParticipant {
                Text("컴퓨터가 생각 중").font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("header.status")
            } else if case .remote = session.currentParticipant {
                Text("상대 차례").font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("header.status")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// 위로 쓸어올리면 던진다. 좌우 성분으로 궤적 그룹을 고른다.
    private var throwGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard value.translation.height < -20 else { return }
                let horizontal = value.translation.width
                session.nextThrowDirection = if horizontal < -40 {
                    .left
                } else if horizontal > 40 {
                    .right
                } else {
                    .center
                }
                Task { await session.send(.roll) }
            }
    }
}
```

`App/Views/GameOverBar.swift` 전체:

```swift
import SwiftUI
import YachtCore

/// 12턴이 끝난 뒤의 액션 바. 순위를 보여주고 새 판 또는 메뉴로 간다.
struct GameOverBar: View {
    let session: GameSession
    var onReturnToMenu: () -> Void = {}

    private var ranking: [(index: Int, total: Int)] {
        session.visibleState.scorecards.enumerated()
            .map { (index: $0.offset, total: $0.element.total) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        VStack(spacing: 10) {
            if session.participants.count == 1 {
                Text("최종 점수 \(ranking[0].total)점")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .accessibilityIdentifier("result.total")
                    .accessibilityLabel("최종 점수 \(ranking[0].total)점")
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(ranking.enumerated()), id: \.offset) { place, entry in
                        HStack {
                            Text("\(place + 1)위").foregroundStyle(place == 0 ? .orange : .secondary)
                            Text(session.participants[entry.index].displayName)
                            Spacer()
                            Text("\(entry.total)점").monospacedDigit().fontWeight(place == 0 ? .bold : .regular)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("result.rank.\(place)")
                    }
                }
                .font(.system(.subheadline, design: .rounded))
                .padding(.horizontal, 8)
                // 혼자일 때와 같은 식별자로 1위 점수를 노출해 기존 UI 테스트가 깨지지 않게 한다
                .accessibilityIdentifier("result.total")
            }

            HStack(spacing: 12) {
                Button {
                    onReturnToMenu()
                } label: {
                    Label("메뉴로", systemImage: "list.bullet")
                        .font(.headline).padding(.horizontal, 12).padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("result.menu")

                Button {
                    session.startNewGame()
                } label: {
                    Label("새 게임", systemImage: "arrow.clockwise")
                        .font(.headline).padding(.horizontal, 12).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isBusy)
                .accessibilityIdentifier("action.newGame")
                .accessibilityLabel("새 게임 시작")
            }
        }
        .padding(.horizontal, 16)
    }
}
```

`ActionBarView.swift`와 `ScoreboardView.swift`의 `.disabled(...)` 조건 세 곳(주사위 칩, Roll, 점수판 행)에 `|| !session.isLocalTurn`을 더한다. 예:

```swift
.disabled(!state.allows(.roll) || session.isBusy || !session.isLocalTurn)
```

`AppContainer`에 `var currentStage: DiceStage? { stage }`를 두고 `YachtDiceApp`에서 `GameScreen(session: session, stage: container.currentStage!, onReturnToMenu: { container.returnToMenu() })`.

- [ ] **Step 2: 빌드와 단위 테스트**

Run: `-only-testing:YachtDiceTests`
Expected: 전부 PASS.

- [ ] **Step 3: 시뮬레이터에서 확인**

메뉴 → 컴퓨터 대전 → 보통. 내 턴을 마치면 "컴퓨터가 생각 중"이 뜨고 주사위가 굴러가며 봇이 기록한 뒤 내 차례로 돌아온다. 로컬 2인 → 첫 턴 뒤 핸드오프 오버레이 → 시작 → 두 번째 사람 차례.

- [ ] **Step 4: 커밋**

```sh
git add App/Views App/AppContainer.swift App/YachtDiceApp.swift
git commit -m "feat(ui): 참가자 띠, 핸드오프, 다인 결과 화면

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: UI 테스트를 메뉴 경유로 고치고 봇 대전을 검증한다

**Files:**
- Modify: `Tests/YachtDiceUITests/FullGameUITests.swift`
- Modify: `Tests/YachtDiceUITests/AccessibilityUITests.swift`
- Create: `Tests/YachtDiceUITests/MenuUITests.swift`

- [ ] **Step 1: 기존 UI 테스트가 메뉴를 지나가게 한다**

`FullGameUITests`와 `AccessibilityUITests`에서 `app.launch()` 직후에 아래를 넣는다 (각 테스트의 첫 화면 접근 전):

```swift
        let solo = app.buttons["menu.solo"]
        XCTAssertTrue(solo.waitForExistence(timeout: 10), "메뉴가 뜨지 않았다")
        solo.tap()
```

`FullGameUITests`의 복원 테스트(앱을 재시작해 진행이 남는지 보는 것)는 재시작 뒤 `menu.resume`을 탭하고 이어서 검증한다:

```swift
        let resume = app.buttons["menu.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "이어하기가 뜨지 않았다")
        resume.tap()
```

- [ ] **Step 2: 봇 대전과 로컬 대전 UI 테스트**

`Tests/YachtDiceUITests/MenuUITests.swift`:

```swift
import XCTest

final class MenuUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    @MainActor
    func test_컴퓨터_대전_한_턴() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch"]
        app.launch()

        app.buttons["menu.bot"].tap()
        let normal = app.buttons["menu.bot.normal"]
        XCTAssertTrue(normal.waitForExistence(timeout: 5))
        normal.tap()

        XCTAssertTrue(app.otherElements["players.seat.1"].waitForExistence(timeout: 10), "참가자 띠가 없다")
        let roll = app.buttons["action.roll"]
        XCTAssertTrue(roll.waitForHittable(timeout: 10))
        roll.tap()
        let row = app.buttons["scoreboard.row.choice"]
        XCTAssertTrue(row.waitForHittable(timeout: 15))
        row.tap()

        // 봇 차례: 상태 표시가 뜨고 입력이 잠긴다
        XCTAssertTrue(app.staticTexts["header.status"].waitForExistence(timeout: 5), "봇 차례 표시가 없다")
        XCTAssertFalse(roll.isEnabled, "봇 차례인데 Roll이 활성이다")

        // 봇이 끝내면 내 차례로 돌아온다 (굴림 3회 연출 최대 ~8초)
        XCTAssertTrue(roll.waitForHittable(timeout: 30), "봇 턴이 끝나지 않았다")
        XCTAssertEqual(app.otherElements["header.turn"].label, "Turn 2/12")
    }

    @MainActor
    func test_로컬_2인_핸드오프() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch"]
        app.launch()

        app.buttons["menu.local"].tap()
        let start = app.buttons["menu.local.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let roll = app.buttons["action.roll"]
        XCTAssertTrue(roll.waitForHittable(timeout: 10))
        roll.tap()
        let row = app.buttons["scoreboard.row.choice"]
        XCTAssertTrue(row.waitForHittable(timeout: 15))
        row.tap()

        let handoff = app.buttons["handoff.start"]
        XCTAssertTrue(handoff.waitForExistence(timeout: 5), "핸드오프가 뜨지 않았다")
        handoff.tap()
        XCTAssertTrue(roll.waitForHittable(timeout: 5), "두 번째 사람이 굴릴 수 없다")
    }

    @MainActor
    func test_메뉴로_돌아가면_이어하기가_있다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch"]
        app.launch()
        app.buttons["menu.solo"].tap()
        let roll = app.buttons["action.roll"]
        XCTAssertTrue(roll.waitForHittable(timeout: 10))
        roll.tap()
        XCTAssertTrue(app.buttons["scoreboard.row.choice"].waitForHittable(timeout: 15))
        app.buttons["header.menu"].tap()
        XCTAssertTrue(app.buttons["menu.resume"].waitForExistence(timeout: 5), "이어하기가 없다")
    }
}
```

- [ ] **Step 3: 전체 테스트 실행**

Run: 스킴 전체 `test` (단위 + UI).
Expected: 전부 PASS. `header.status`가 `staticTexts`로 안 잡히면 `otherElements`로 바꾼다. `players.seat.1`은 `.accessibilityElement(children: .combine)`이라 `otherElements`다.

- [ ] **Step 4: 커밋**

```sh
git add Tests/YachtDiceUITests
git commit -m "test(ui): 메뉴 경유로 고치고 봇 대전·핸드오프를 검증한다

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: README와 스펙 상태 갱신

**Files:**
- Modify: `README.md` (구조 표에 `Packages/YachtBot`, `App/Views/MenuScreen.swift` 추가, "베이커는 `open -a`로 띄운다" 메모)
- Modify: `docs/superpowers/specs/2026-09-07-yacht-dice-p2-p3-design.md` (A·B 완료 표시)

- [ ] **Step 1: README 갱신**

구조 표에 두 줄 추가:

```
| `Packages/YachtBot` | 컴퓨터 상대. 난이도 3단계, 손패 기대값 전수 계산. YachtCore만 의존. |
| `App/Views/MenuScreen.swift` | 시작 메뉴. 모드 선택과 이어하기. |
```

"궤적 다시 굽기" 절의 1번을:

```
1. 스킴 `TrajectoryBaker`를 빌드한 뒤 **Finder나 `open -a`로 앱을 띄운다.** 셸에서 바이너리를 직접 실행하면
   창이 생기지 않아 RealityKit 물리가 돌지 않는다 (CPU 0%로 영원히 대기). 진행 로그는 `open --stdout 파일`로 받는다.
```

- [ ] **Step 2: 커밋**

```sh
git add README.md docs/superpowers/specs/2026-09-07-yacht-dice-p2-p3-design.md
git commit -m "docs: P2 완료 반영과 베이커 실행 방법

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
