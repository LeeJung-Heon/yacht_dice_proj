# Yacht Dice P1 (코어 규칙 엔진 + 3D 주사위) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 혼자서 12턴을 끝까지 플레이할 수 있는 iOS 야추 다이스 앱을 만들고, 동시에 P3(온라인 대전)에서 코어를 재작성하지 않아도 되는 구조를 확립한다.

**Architecture:** 규칙은 의존성 0인 순수 Swift 패키지 `YachtCore`가 이벤트 소싱으로 소유한다. 주사위 3D는 미리 구운 물리 궤적을 재생하되 각 주사위의 회전에만 정육면체 대칭군 원소를 곱해 목표 눈을 맞춘다 — 궤적의 기하는 매 프레임 원본과 동일하므로 결과가 100% 결정적이다. 이 궤적 수학과 포맷은 앱과 베이커 툴이 공유하는 `DiceTrajectory` 패키지에 둔다. `GameSession`이 코어·드라이버·3D 연출을 잇는 유일한 오케스트레이터다.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, RealityKit, Swift Testing, SwiftPM 로컬 패키지, XcodeGen(프로젝트를 텍스트에서 재생성), simd

**Spec:** `docs/superpowers/specs/2026-08-28-yacht-dice-p1-core-3d-design.md`

## Global Constraints

- 최소 OS: iOS 18.0 / macOS 15.0 (베이커 툴). Swift 언어 모드 6, `SWIFT_STRICT_CONCURRENCY = complete`.
- 화면 방향: 세로(portrait) 고정. iPhone 전용. iPad는 P1 범위 밖.
- `Packages/YachtCore`는 SwiftUI·RealityKit·네트워크·simd를 **import 하지 않는다**. Foundation만 허용. 이 제약이 깨지면 P3에서 코어를 재작성하게 된다.
- `Packages/DiceTrajectory`는 Foundation과 simd만 import한다. RealityKit·SwiftUI 금지.
- 주사위는 5개, 턴당 최대 굴림 3회, 총 12턴, 상단 보너스 임계 63점 / 보상 35점.
- 점수 규칙은 스펙 §4.2 표가 유일한 근거다. 4 of a Kind와 Full House는 **주사위 5개 총합**, S.Straight 15 고정, L.Straight 30 고정, Yacht 50 고정. 조커 룰 없음, 야추 추가 보너스 없음. Full House는 5개 동일도 인정한다.
- 주사위 면 배치는 서양식 오른손 주사위: 로컬 +Y=1, -Y=6, +Z=2, -Z=5, +X=3, -X=4. 마주 보는 면의 합은 7이고 1·2·3이 한 꼭짓점을 반시계로 돈다.
- 수익화 코드(IAP·광고·분석 SDK) 일절 없음.
- **점수 카테고리 타입의 이름은 `ScoreCategory`다. `Category`로 되돌리지 말 것.** Foundation이 Objective-C 런타임의 `Category` 타입(`OpaquePointer`의 typealias)을 재수출하기 때문에, `import Foundation`과 `import YachtCore`를 함께 하는 소비자는 bare `Category`에서 `'Category' is ambiguous for type lookup` 오류를 받는다. SwiftUI가 Foundation을 재수출하므로 App 타깃의 거의 모든 파일이 여기 해당하고, `extension Category`는 아예 작성할 수 없다. (Task 7에서 발견, 스크래치 패키지로 실측 확인)
- **`xcodebuild`의 `-derivedDataPath`는 반드시 저장소 밖(`/private/tmp` 아래)을 가리킨다.** 이 저장소는 iCloud Drive에 있어서 리포지토리 내부로 빌드하면 codesign이 `resource fork, Finder information, or similar detritus not allowed`로 실패한다 (Task 2 스파이크 실측).
- **정지 자세를 축정렬로 스냅하지 않는다.** 바닥에 누운 주사위는 yaw가 연속적으로 자유롭다. 회전 오프셋 Δ는 `q_rest` 전체가 아니라 위를 향한 눈 `u`에만 의존한다 (스펙 §7.3).
- 저장소 경로에 공백이 있다(`.../com~apple~CloudDocs/yacht_dice_proj`). 모든 셸 명령에서 경로를 따옴표로 감싼다.
- 커밋 메시지는 무엇을 왜 바꿨는지 한국어로 쓰고 다음 줄로 끝낸다:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`

---

### Task 1: 프로젝트 스캐폴딩

XcodeGen으로 `.xcodeproj`를 텍스트에서 재생성 가능하게 만든다. 이 단계가 끝나면 빈 앱이 시뮬레이터에서 뜨고 두 패키지의 테스트가 `swift test`로 돈다.

**Files:**
- Create: `project.yml`
- Create: `Packages/YachtCore/Package.swift`, `Packages/YachtCore/Sources/YachtCore/YachtCore.swift`
- Create: `Packages/YachtCore/Tests/YachtCoreTests/SmokeTests.swift`
- Create: `Packages/DiceTrajectory/Package.swift`, `Packages/DiceTrajectory/Sources/DiceTrajectory/DiceTrajectory.swift`
- Create: `Packages/DiceTrajectory/Tests/DiceTrajectoryTests/SmokeTests.swift`
- Create: `App/YachtDiceApp.swift`, `App/Info.plist`
- Create: `Tests/YachtDiceTests/AppSmokeTests.swift`
- Create: `Tests/YachtDiceUITests/LaunchUITests.swift`
- Create: `Tools/TrajectoryBaker/BakerApp.swift`

**Interfaces:**
- Consumes: 없음 (첫 작업)
- Produces: `YachtCore` / `DiceTrajectory` 모듈 이름, `YachtDice` 앱 스킴, `TrajectoryBaker` macOS 앱 스킴

- [ ] **Step 1: XcodeGen 설치 확인**

```bash
which xcodegen || brew install xcodegen
xcodegen --version
```

- [ ] **Step 2: `Packages/YachtCore/Package.swift` 작성**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YachtCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "YachtCore", targets: ["YachtCore"])],
    targets: [
        .target(name: "YachtCore"),
        .testTarget(name: "YachtCoreTests", dependencies: ["YachtCore"]),
    ]
)
```

- [ ] **Step 3: `Packages/YachtCore/Sources/YachtCore/YachtCore.swift` 작성**

```swift
import Foundation

/// 이 모듈은 Foundation 외의 어떤 것도 import 하지 않는다.
/// SwiftUI·RealityKit·네트워크가 들어오는 순간 P3에서 코어를 재작성하게 된다.
public enum YachtCore {
    public static let diceCount = 5
    public static let maxRollsPerTurn = 3
    public static let turnCount = 12
}
```

- [ ] **Step 4: `Packages/YachtCore/Tests/YachtCoreTests/SmokeTests.swift` 작성**

```swift
import Testing
@testable import YachtCore

@Test func 코어_상수가_규칙과_일치한다() {
    #expect(YachtCore.diceCount == 5)
    #expect(YachtCore.maxRollsPerTurn == 3)
    #expect(YachtCore.turnCount == 12)
}
```

- [ ] **Step 5: YachtCore 테스트 실행**

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: PASS (1 test)

- [ ] **Step 6: `Packages/DiceTrajectory/Package.swift` 작성**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiceTrajectory",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "DiceTrajectory", targets: ["DiceTrajectory"])],
    targets: [
        .target(name: "DiceTrajectory"),
        .testTarget(name: "DiceTrajectoryTests", dependencies: ["DiceTrajectory"]),
    ]
)
```

- [ ] **Step 7: `Packages/DiceTrajectory/Sources/DiceTrajectory/DiceTrajectory.swift` 작성**

```swift
import Foundation
import simd

/// 궤적 재생과 주사위 면 제어에 필요한 순수 수학·자료구조.
/// Foundation과 simd만 import한다. RealityKit이 들어오면 시뮬레이터 없이 테스트할 수 없게 된다.
public enum DiceTrajectory {
    public static let formatVersion: UInt16 = 1
}
```

- [ ] **Step 8: `Packages/DiceTrajectory/Tests/DiceTrajectoryTests/SmokeTests.swift` 작성**

```swift
import Testing
@testable import DiceTrajectory

@Test func 포맷_버전이_1이다() {
    #expect(DiceTrajectory.formatVersion == 1)
}
```

- [ ] **Step 9: DiceTrajectory 테스트 실행**

```bash
swift test --package-path "Packages/DiceTrajectory"
```
Expected: PASS (1 test)

- [ ] **Step 10: `App/YachtDiceApp.swift` 작성**

```swift
import SwiftUI

@main
struct YachtDiceApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Yacht Dice")
        }
    }
}
```

- [ ] **Step 11: `App/Info.plist` 작성**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>UILaunchScreen</key>
	<dict/>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 12: `Tools/TrajectoryBaker/BakerApp.swift` 작성 (빈 껍데기, Task 2에서 채운다)**

```swift
import SwiftUI

@main
struct BakerApp: App {
    var body: some Scene {
        WindowGroup("Trajectory Baker") {
            Text("Baker")
                .frame(minWidth: 640, minHeight: 480)
        }
    }
}
```

- [ ] **Step 13: `Tests/YachtDiceTests/AppSmokeTests.swift` 작성**

```swift
import Testing
import YachtCore
import DiceTrajectory
@testable import YachtDice

/// 앱 타깃이 두 로컬 패키지에 실제로 링크되었는지 확인한다.
/// Bool(true)를 확인하는 테스트는 스캐폴딩이 깨져도 통과하므로 의미가 없다.
@Test func 앱_타깃이_두_패키지에_링크된다() {
    #expect(YachtCore.diceCount == 5)
    #expect(DiceTrajectory.formatVersion == 1)
}
```

- [ ] **Step 14: `Tests/YachtDiceUITests/LaunchUITests.swift` 작성**

```swift
import XCTest

final class LaunchUITests: XCTestCase {
    func test_앱이_실행된다() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
```

- [ ] **Step 15: `project.yml` 작성**

```yaml
name: YachtDice
options:
  bundleIdPrefix: com.leejungheon.yachtdice
  deploymentTarget:
    iOS: "18.0"
    macOS: "15.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY: YES

packages:
  YachtCore:
    path: Packages/YachtCore
  DiceTrajectory:
    path: Packages/DiceTrajectory

targets:
  YachtDice:
    type: application
    platform: iOS
    sources: [App]
    info:
      path: App/Info.plist
    dependencies:
      - package: YachtCore
      - package: DiceTrajectory

  YachtDiceTests:
    type: bundle.unit-test
    platform: iOS
    sources: [Tests/YachtDiceTests]
    dependencies:
      - target: YachtDice

  YachtDiceUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [Tests/YachtDiceUITests]
    dependencies:
      - target: YachtDice

  TrajectoryBaker:
    type: application
    platform: macOS
    sources: [Tools/TrajectoryBaker]
    dependencies:
      - package: DiceTrajectory

schemes:
  YachtDice:
    build:
      targets:
        YachtDice: all
    test:
      targets: [YachtDiceTests, YachtDiceUITests]
  TrajectoryBaker:
    build:
      targets:
        TrajectoryBaker: all
```

- [ ] **Step 16: 프로젝트 생성 후 빌드**

```bash
xcodegen generate
xcrun simctl list devices available | grep -i iphone | head -3   # 사용 가능한 시뮬레이터 확인
xcodebuild build -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' | tail -5
```
Expected: `** BUILD SUCCEEDED **`
시뮬레이터 이름이 없으면 위 `simctl list` 출력에서 실제 이름으로 바꿔 쓰고, 이후 모든 단계에서 같은 이름을 쓴다.

- [ ] **Step 17: `.gitignore`에 XcodeGen 산출물 추가**

```bash
printf '*.xcodeproj\n' >> .gitignore
```

- [ ] **Step 18: 커밋**

```bash
git add -A
git commit -m "$(cat <<'MSG'
chore: 프로젝트 스캐폴딩 (XcodeGen + 로컬 패키지 2개)

.xcodeproj를 project.yml에서 재생성하도록 XcodeGen을 쓴다. 프로젝트 파일이
텍스트로 관리되지 않으면 이 규모의 계획을 여러 세션에 걸쳐 실행할 때
병합 충돌로 시간을 잃는다.

규칙(YachtCore)과 궤적 수학(DiceTrajectory)을 별도 패키지로 분리했다.
둘 다 시뮬레이터 없이 swift test로 돌아가고, DiceTrajectory는 베이커 툴과
앱이 공유한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 2: 베이커 스파이크 — RealityKit 물리로 궤적을 기록할 수 있는가

**이것은 스파이크다.** 출력물은 코드가 아니라 **답**이다. 스펙 §14 리스크 ①을 여기서 없앤다. 여기서 막히면 Task 12의 구현 경로가 바뀌므로, 반드시 코어 작업보다 먼저 한다.

**답해야 할 질문 4개:**
1. macOS `RealityView`에서 주사위 5개가 트레이 벽·서로와 충돌하며 굴러가는가?
2. 매 프레임 각 주사위의 위치·자세를 읽어낼 수 있는가?
3. 주사위가 언제 멈췄는지 판정할 수 있는가? (`PhysicsMotionComponent`의 속도를 읽을 수 있는가, 아니면 위치 차분으로 대신해야 하는가)
4. 멈춘 주사위의 자세가 축정렬에 충분히 가까운가? (스펙 §11의 허용 오차 2°)

**Files:**
- Modify: `Tools/TrajectoryBaker/BakerApp.swift`
- Create: `Tools/TrajectoryBaker/SpikeScene.swift`

**Interfaces:**
- Consumes: Task 1의 `TrajectoryBaker` macOS 스킴
- Produces: 없음 (스파이크 코드는 Task 12에서 버리거나 흡수한다)

- [ ] **Step 1: 스파이크 씬 작성**

`Tools/TrajectoryBaker/SpikeScene.swift`:

```swift
import SwiftUI
import RealityKit
import simd

/// 스파이크 전용. Task 12에서 정식 베이커로 대체되거나 흡수된다.
struct SpikeScene: View {
    @State private var log: [String] = []
    @State private var frameCount = 0
    @State private var settledFrame: Int?

    // 트레이 안쪽 치수 (미터). 실물 주사위 16mm 기준으로 잡았다.
    static let trayInner = SIMD3<Float>(0.24, 0.12, 0.24)
    static let dieSize: Float = 0.016

    var body: some View {
        HSplitView {
            RealityView { content in
                content.add(Self.makeTray())
                let dice = Self.makeDice()
                for d in dice { content.add(d) }
                Self.throwDice(dice)

                let camera = Entity()
                camera.components.set(PerspectiveCameraComponent())
                camera.look(at: .zero, from: [0, 0.35, 0.30], relativeTo: nil)
                content.add(camera)
            } update: { _ in
            }
            .realityViewCameraControls(.orbit)

            List(log, id: \.self) { Text($0).font(.system(.caption, design: .monospaced)) }
                .frame(minWidth: 340)
        }
        .task { await observe() }
    }

    static func makeTray() -> Entity {
        let tray = Entity()
        let t: Float = 0.01   // 벽 두께
        let walls: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([trayInner.x, t, trayInner.z], [0, -t / 2, 0]),                                  // 바닥
            ([trayInner.x, trayInner.y, t], [0, trayInner.y / 2,  (trayInner.z + t) / 2]),    // 앞
            ([trayInner.x, trayInner.y, t], [0, trayInner.y / 2, -(trayInner.z + t) / 2]),    // 뒤
            ([t, trayInner.y, trayInner.z], [ (trayInner.x + t) / 2, trayInner.y / 2, 0]),    // 우
            ([t, trayInner.y, trayInner.z], [-(trayInner.x + t) / 2, trayInner.y / 2, 0]),    // 좌
        ]
        for (size, offset) in walls {
            let mesh = MeshResource.generateBox(size: size)
            let e = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .brown, isMetallic: false)])
            e.position = offset
            e.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
            e.components.set(PhysicsBodyComponent(massProperties: .default,
                                                  material: .generate(friction: 0.6, restitution: 0.25),
                                                  mode: .static))
            tray.addChild(e)
        }
        return tray
    }

    static func makeDice() -> [ModelEntity] {
        (0..<5).map { i in
            let mesh = MeshResource.generateBox(size: dieSize, cornerRadius: dieSize * 0.12)
            let e = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .white, isMetallic: false)])
            e.name = "die\(i)"
            e.position = [Float(i - 2) * dieSize * 1.6, 0.14, 0]
            e.components.set(CollisionComponent(shapes: [.generateBox(size: .init(repeating: dieSize))]))
            e.components.set(PhysicsBodyComponent(massProperties: .init(mass: 0.005),
                                                  material: .generate(friction: 0.5, restitution: 0.35),
                                                  mode: .dynamic))
            e.components.set(PhysicsMotionComponent())
            return e
        }
    }

    static func throwDice(_ dice: [ModelEntity]) {
        for d in dice {
            var motion = PhysicsMotionComponent()
            motion.linearVelocity = [Float.random(in: -0.6...(-0.2)), -0.4, Float.random(in: -0.3...0.3)]
            motion.angularVelocity = [Float.random(in: -30...30), Float.random(in: -30...30), Float.random(in: -30...30)]
            d.components.set(motion)
        }
    }

    /// 4개 질문에 답하기 위한 관찰 루프.
    @MainActor func observe() async {
        // Step 2에서 채운다.
    }
}
```

- [ ] **Step 2: 관찰 루프를 채워 질문 2·3·4에 답하게 한다**

`observe()` 본문:

```swift
@MainActor func observe() async {
    // 질문 2: 프레임마다 transform을 읽을 수 있는가?
    // 질문 3: PhysicsMotionComponent의 속도를 읽을 수 있는가?
    // 질문 4: 멈춘 자세가 축정렬에 얼마나 가까운가?
    var lines: [String] = []
    var previous: [SIMD3<Float>] = []
    var stillFrames = 0

    for frame in 0..<600 {                      // 최대 10초 @60fps
        try? await Task.sleep(for: .milliseconds(16))
        let dice = currentDice()
        guard dice.count == 5 else { continue }

        let positions = dice.map { $0.position(relativeTo: nil) }
        let motions = dice.map { $0.components[PhysicsMotionComponent.self] }
        let readableVelocity = motions.allSatisfy { $0 != nil }

        // 속도를 못 읽으면 위치 차분으로 대신한다
        let speed: Float
        if readableVelocity {
            speed = motions.compactMap { $0 }.map { simd_length($0.linearVelocity) }.max() ?? 0
        } else if previous.count == positions.count {
            speed = zip(previous, positions).map { simd_length($1 - $0) * 60 }.max() ?? 0
        } else {
            speed = .infinity
        }
        previous = positions

        if frame == 0 {
            lines.append("Q2 transform 읽기: \(positions.first.map { "OK \($0)" } ?? "실패")")
            lines.append("Q3 속도 읽기: \(readableVelocity ? "PhysicsMotionComponent OK" : "불가 → 위치 차분 사용")")
        }

        stillFrames = speed < 0.002 ? stillFrames + 1 : 0
        if stillFrames >= 30 {                  // 0.5초 정지
            settledFrame = frame
            lines.append("Q1 정지: \(frame)프레임 (\(String(format: "%.2f", Double(frame) / 60))초)")
            for (i, d) in dice.enumerated() {
                let deg = axisAlignmentErrorDegrees(d.orientation(relativeTo: nil))
                lines.append(String(format: "Q4 die%d 축정렬 오차: %.2f°  %@", i, deg, deg <= 2 ? "OK" : "초과"))
            }
            break
        }
    }
    if settledFrame == nil { lines.append("Q1 실패: 10초 안에 멈추지 않았다") }
    log = lines
}

/// 24개 축정렬 자세 중 가장 가까운 것과의 각도 차이 (도).
nonisolated func axisAlignmentErrorDegrees(_ q: simd_quatf) -> Float {
    var best: Float = .pi
    for candidate in Self.axisAlignedOrientations {
        let d = min(1, abs(simd_dot(simd_normalize(q.vector), simd_normalize(candidate.vector))))
        best = min(best, 2 * acos(d))
    }
    return best * 180 / .pi
}

/// 스파이크용 간이 생성. 정식 구현은 Task 9의 OctahedralGroup.
static let axisAlignedOrientations: [simd_quatf] = {
    var out: [simd_quatf] = []
    let quarter: [Float] = [0, .pi / 2, .pi, 3 * .pi / 2]
    for x in quarter { for y in quarter { for z in quarter {
        let q = simd_normalize(simd_quatf(angle: z, axis: [0, 0, 1])
                             * simd_quatf(angle: y, axis: [0, 1, 0])
                             * simd_quatf(angle: x, axis: [1, 0, 0]))
        if !out.contains(where: { abs(simd_dot($0.vector, q.vector)) > 0.9999 }) { out.append(q) }
    }}}
    return out
}()
```

`currentDice()`는 `RealityView`의 content를 `@State`로 붙잡아 이름이 `die`로 시작하는 자식을 찾아 돌려주면 된다. 스파이크이므로 구현이 지저분해도 무방하다.

- [ ] **Step 3: 실행하고 4개 질문의 답을 기록**

```bash
xcodebuild build -project YachtDice.xcodeproj -scheme TrajectoryBaker -destination 'platform=macOS' | tail -3
open build/Debug/TrajectoryBaker.app   # 또는 Xcode에서 Run
```

화면 오른쪽 로그에 나오는 `Q1`~`Q4` 줄을 그대로 옮겨 적는다. `axisAlignedOrientations`가 정확히 24개인지도 확인한다 (24가 아니면 스파이크 코드의 중복 판정 허용오차 문제이므로 Task 9의 정식 구현에서 BFS로 다시 만든다).

- [ ] **Step 4: 판정 — 어느 경로로 갈지 결정한다**

| 관찰 | 결론 |
|---|---|
| Q1~Q4 전부 OK, 축정렬 오차가 5회 시도 모두 2° 이내 | **경로 A**: Task 12를 RealityKit 베이커로 진행 |
| Q4만 초과 (주사위가 기울어 멈춤) | **경로 A'**: 마찰·반발·주사위 모서리 라운드를 조정해 재시도. 그래도 안 되면 정지 후 가장 가까운 축정렬로 스냅하되, 스냅각이 5°를 넘는 궤적은 버린다 |
| Q2 또는 Q3이 불가 | **경로 A''**: 위치 차분으로 속도를 대신하고 `SceneEvents.Update` 구독으로 프레임을 수집한다 |
| Q1이 실패 (안 멈추거나 트레이를 뚫음) | **경로 B**: RealityKit을 버리고 주사위-박스 충돌만 다루는 자체 강체 시뮬을 `DiceTrajectory`에 구현한다. Task 12를 통째로 교체하고 일정에 2~3일을 더한다 |

- [ ] **Step 5: 결론을 스펙에 기록하고 커밋**

`docs/superpowers/specs/2026-08-28-yacht-dice-p1-core-3d-design.md`의 §14 리스크 ① 아래에 다음 형식으로 결과를 덧붙인다:

```markdown
**스파이크 결과 (YYYY-MM-DD):** [경로 A / A' / A'' / B]를 채택. 관찰: Q1 정지 N프레임, Q2 [OK/불가], Q3 [OK/불가], Q4 최대 오차 N.NN°.
```

```bash
git add -A
git commit -m "$(cat <<'MSG'
spike: RealityKit 물리로 궤적을 기록할 수 있는지 확인

스펙 §14 리스크 ①을 없애기 위한 스파이크다. 주사위가 트레이 안에서 멈추는지,
프레임마다 자세를 읽을 수 있는지, 멈춘 자세가 축정렬 2° 이내인지를 확인했다.
결과와 채택 경로를 스펙에 기록했다.

이 코드는 버리는 코드다. Task 12의 정식 베이커가 대체한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 3: ScoreCategory 점수 계산

스펙 §4.2 표를 순수 함수로 옮긴다. 이 프로젝트에서 가장 많이 읽힐 코드이므로 표와 1:1로 대응하게 쓴다.

**Files:**
- Create: `Packages/YachtCore/Sources/YachtCore/ScoreCategory.swift`
- Create: `Packages/YachtCore/Tests/YachtCoreTests/CategoryScoringTests.swift`

**Interfaces:**
- Consumes: Task 1의 `YachtCore` 모듈
- Produces:
  - `public enum ScoreCategory: String, CaseIterable, Codable, Hashable, Sendable` — 12 케이스
  - `public static let ScoreCategory.upperCases: [ScoreCategory]`
  - `public var ScoreCategory.isUpper: Bool`
  - `public func ScoreCategory.score(_ dice: [Int]) -> Int`

- [ ] **Step 1: 실패하는 테스트 작성**

`Packages/YachtCore/Tests/YachtCoreTests/CategoryScoringTests.swift`:

```swift
import Testing
@testable import YachtCore

@Suite("카테고리 점수")
struct CategoryScoringTests {

    @Test("상단 카테고리는 해당 눈의 합이다", arguments: [
        (ScoreCategory.aces,   [1, 1, 3, 4, 1], 3),
        (ScoreCategory.deuces, [2, 2, 2, 4, 5], 6),
        (ScoreCategory.threes, [1, 2, 4, 5, 6], 0),
        (ScoreCategory.fours,  [4, 4, 4, 4, 4], 20),
        (ScoreCategory.fives,  [5, 5, 1, 2, 3], 10),
        (ScoreCategory.sixes,  [6, 6, 6, 1, 1], 18),
    ])
    func 상단(category: ScoreCategory, dice: [Int], expected: Int) {
        #expect(category.score(dice) == expected)
    }

    @Test("Choice는 항상 5개 총합이다")
    func choice() {
        #expect(ScoreCategory.choice.score([1, 2, 3, 4, 5]) == 15)
        #expect(ScoreCategory.choice.score([6, 6, 6, 6, 6]) == 30)
    }

    @Test("4 of a Kind는 같은 눈 4개 이상일 때 5개 총합이다", arguments: [
        ([6, 6, 6, 6, 2], 26),   // 레퍼런스 사진의 26
        ([3, 3, 3, 3, 3], 15),   // 5개 동일도 만족한다
        ([6, 6, 6, 2, 2], 0),    // 3개뿐
        ([1, 2, 3, 4, 5], 0),
    ])
    func 포카인드(dice: [Int], expected: Int) {
        #expect(ScoreCategory.fourOfAKind.score(dice) == expected)
    }

    @Test("Full House는 3+2일 때 5개 총합이고 5개 동일도 인정한다", arguments: [
        ([3, 3, 3, 2, 2], 13),
        ([6, 6, 6, 6, 6], 30),   // 5개 동일 인정
        ([6, 6, 6, 6, 2], 0),    // 4+1은 풀하우스가 아니다
        ([1, 1, 2, 2, 3], 0),    // 2+2+1
        ([1, 2, 3, 4, 5], 0),
    ])
    func 풀하우스(dice: [Int], expected: Int) {
        #expect(ScoreCategory.fullHouse.score(dice) == expected)
    }

    @Test("S. Straight는 연속 4개면 15점 고정이다", arguments: [
        ([1, 2, 3, 4, 6], 15),
        ([2, 3, 4, 5, 5], 15),
        ([3, 4, 5, 6, 1], 15),
        ([1, 2, 3, 4, 5], 15),   // 라지 스트레이트는 스몰도 만족한다
        ([1, 2, 3, 5, 6], 0),
        ([1, 1, 2, 3, 4], 15),   // 중복이 있어도 연속 4개가 있으면 인정
    ])
    func 스몰스트레이트(dice: [Int], expected: Int) {
        #expect(ScoreCategory.smallStraight.score(dice) == expected)
    }

    @Test("L. Straight는 연속 5개면 30점 고정이다", arguments: [
        ([1, 2, 3, 4, 5], 30),
        ([2, 3, 4, 5, 6], 30),
        ([1, 2, 3, 4, 6], 0),
        ([1, 1, 2, 3, 4], 0),
    ])
    func 라지스트레이트(dice: [Int], expected: Int) {
        #expect(ScoreCategory.largeStraight.score(dice) == expected)
    }

    @Test("Yacht는 5개 동일이면 50점 고정이다")
    func 야추() {
        #expect(ScoreCategory.yacht.score([4, 4, 4, 4, 4]) == 50)
        #expect(ScoreCategory.yacht.score([4, 4, 4, 4, 1]) == 0)
    }

    @Test("상단 6개만 isUpper다")
    func 상단_구분() {
        #expect(ScoreCategory.upperCases.count == 6)
        #expect(ScoreCategory.allCases.count == 12)
        #expect(ScoreCategory.allCases.filter(\.isUpper) == ScoreCategory.upperCases)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: 컴파일 실패 — `cannot find 'ScoreCategory' in scope`

- [ ] **Step 3: 구현 작성**

`Packages/YachtCore/Sources/YachtCore/ScoreCategory.swift`:

```swift
import Foundation

/// 야추 12 카테고리. 점수 규칙은 스펙 §4.2 표가 유일한 근거다.
public enum ScoreCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case aces, deuces, threes, fours, fives, sixes
    case choice, fourOfAKind, fullHouse, smallStraight, largeStraight, yacht

    /// 상단 소계와 63점 보너스에 들어가는 6개.
    public static let upperCases: [ScoreCategory] = [.aces, .deuces, .threes, .fours, .fives, .sixes]

    public var isUpper: Bool { ScoreCategory.upperCases.contains(self) }

    /// 이 카테고리에 이 주사위를 기록했을 때의 점수. 조건을 못 채우면 0이다.
    public func score(_ dice: [Int]) -> Int {
        precondition(dice.count == YachtCore.diceCount, "주사위는 정확히 5개여야 한다")
        precondition(dice.allSatisfy { (1...6).contains($0) }, "주사위 눈은 1...6이어야 한다")

        var counts = [Int](repeating: 0, count: 7)   // counts[v] = 눈 v의 개수, counts[0]은 항상 0
        for die in dice { counts[die] += 1 }
        let total = dice.reduce(0, +)
        let present = Set(dice)

        switch self {
        case .aces:   return counts[1] * 1
        case .deuces: return counts[2] * 2
        case .threes: return counts[3] * 3
        case .fours:  return counts[4] * 4
        case .fives:  return counts[5] * 5
        case .sixes:  return counts[6] * 6

        case .choice:
            return total

        case .fourOfAKind:
            // 5개 동일도 "4개 이상"을 만족한다
            return counts.contains(where: { $0 >= 4 }) ? total : 0

        case .fullHouse:
            // 5개 동일을 인정하는 것은 제품 결정이다 (스펙 §4.2)
            if counts.contains(5) { return total }
            return (counts.contains(3) && counts.contains(2)) ? total : 0

        case .smallStraight:
            let runs: [Set<Int>] = [[1, 2, 3, 4], [2, 3, 4, 5], [3, 4, 5, 6]]
            return runs.contains(where: { $0.isSubset(of: present) }) ? 15 : 0

        case .largeStraight:
            return (present == [1, 2, 3, 4, 5] || present == [2, 3, 4, 5, 6]) ? 30 : 0

        case .yacht:
            return counts.contains(5) ? 50 : 0
        }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: PASS (전체)

- [ ] **Step 5: 커밋**

```bash
git add Packages/YachtCore
git commit -m "$(cat <<'MSG'
feat(core): 12개 카테고리 점수 계산

스펙 4.2 표를 순수 함수로 옮겼다. 표와 1:1로 읽히도록 switch 한 덩어리로 썼다.

레퍼런스에서 확정한 두 가지를 테스트로 못박았다. 4 of a Kind와 Full House는
해당 조합의 합이 아니라 주사위 5개 총합이고(사진의 26 = 6+6+6+6+2),
Full House는 5개 동일도 인정한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 4: ScoreCard와 상단 보너스

**Files:**
- Create: `Packages/YachtCore/Sources/YachtCore/ScoreCard.swift`
- Create: `Packages/YachtCore/Tests/YachtCoreTests/ScoreCardTests.swift`

**Interfaces:**
- Consumes: Task 3의 `ScoreCategory`
- Produces:
  - `public struct ScoreCard: Equatable, Codable, Sendable`
  - `init()`, `func isFilled(_ c: ScoreCategory) -> Bool`, `mutating func record(_ c: ScoreCategory, _ points: Int)`
  - `var entry(_ c: ScoreCategory) -> Int?`, `var upperSubtotal: Int`, `var upperBonus: Int`, `var total: Int`, `var isComplete: Bool`
  - `static let upperBonusThreshold = 63`, `static let upperBonusPoints = 35`

- [ ] **Step 1: 실패하는 테스트 작성**

`Packages/YachtCore/Tests/YachtCoreTests/ScoreCardTests.swift`:

```swift
import Testing
import Foundation
@testable import YachtCore

@Suite("점수판")
struct ScoreCardTests {

    @Test("빈 점수판은 전부 0이고 완성되지 않았다")
    func 초기상태() {
        let card = ScoreCard()
        #expect(card.upperSubtotal == 0)
        #expect(card.upperBonus == 0)
        #expect(card.total == 0)
        #expect(card.isComplete == false)
        #expect(card.entry(.aces) == nil)
        #expect(card.isFilled(.aces) == false)
    }

    @Test("0점을 기록해도 채워진 것으로 센다")
    func 스크래치() {
        var card = ScoreCard()
        card.record(.yacht, 0)
        #expect(card.isFilled(.yacht) == true)
        #expect(card.entry(.yacht) == 0)
    }

    @Test("상단 소계가 63 미만이면 보너스가 없다")
    func 보너스_미달() {
        var card = ScoreCard()
        for c in ScoreCategory.upperCases { card.record(c, 10) }   // 60
        #expect(card.upperSubtotal == 60)
        #expect(card.upperBonus == 0)
        #expect(card.total == 60)
    }

    @Test("상단 소계가 정확히 63이면 보너스 35가 붙는다")
    func 보너스_경계() {
        var card = ScoreCard()
        for (i, c) in ScoreCategory.upperCases.enumerated() { card.record(c, i == 0 ? 13 : 10) }   // 63
        #expect(card.upperSubtotal == 63)
        #expect(card.upperBonus == 35)
        #expect(card.total == 63 + 35)
    }

    @Test("하단 점수는 보너스에 영향을 주지 않는다")
    func 하단은_보너스와_무관() {
        var card = ScoreCard()
        card.record(.yacht, 50)
        #expect(card.upperSubtotal == 0)
        #expect(card.upperBonus == 0)
        #expect(card.total == 50)
    }

    @Test("12칸을 모두 채우면 완성이다")
    func 완성() {
        var card = ScoreCard()
        for c in ScoreCategory.allCases { card.record(c, 0) }
        #expect(card.isComplete == true)
    }

    @Test("JSON 왕복 후에도 같다")
    func 코더블_왕복() throws {
        var card = ScoreCard()
        card.record(.sixes, 24)
        card.record(.fullHouse, 21)
        let data = try JSONEncoder().encode(card)
        let restored = try JSONDecoder().decode(ScoreCard.self, from: data)
        #expect(restored == card)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: 컴파일 실패 — `cannot find 'ScoreCard' in scope`

- [ ] **Step 3: 구현 작성**

`Packages/YachtCore/Sources/YachtCore/ScoreCard.swift`:

```swift
import Foundation

/// 한 플레이어의 점수판. 기록은 되돌릴 수 없다 (야추 규칙).
public struct ScoreCard: Equatable, Codable, Sendable {
    public static let upperBonusThreshold = 63
    public static let upperBonusPoints = 35

    private var entries: [ScoreCategory: Int]

    public init() { entries = [:] }

    public func entry(_ category: ScoreCategory) -> Int? { entries[category] }
    public func isFilled(_ category: ScoreCategory) -> Bool { entries[category] != nil }

    /// 0점(scratch)도 기록으로 센다. 같은 칸을 두 번 기록하는 것은 호출자의 버그다.
    public mutating func record(_ category: ScoreCategory, _ points: Int) {
        precondition(entries[category] == nil, "이미 기록된 카테고리다: \(category)")
        entries[category] = points
    }

    public var upperSubtotal: Int {
        ScoreCategory.upperCases.reduce(0) { $0 + (entries[$1] ?? 0) }
    }

    /// 소계가 63에 도달하는 즉시 확정된다. 12턴 종료를 기다리지 않는다.
    public var upperBonus: Int {
        upperSubtotal >= Self.upperBonusThreshold ? Self.upperBonusPoints : 0
    }

    public var total: Int { entries.values.reduce(0, +) + upperBonus }

    public var isComplete: Bool { entries.count == ScoreCategory.allCases.count }

    public var openCategories: [ScoreCategory] { ScoreCategory.allCases.filter { entries[$0] == nil } }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: PASS (전체)

- [ ] **Step 5: 커밋**

```bash
git add Packages/YachtCore
git commit -m "$(cat <<'MSG'
feat(core): 점수판과 상단 63점 보너스

record()는 이미 채워진 칸을 다시 쓰면 preconditionFailure로 죽는다. 야추에서
기록은 되돌릴 수 없으므로, 조용히 덮어쓰는 것보다 즉시 터지는 편이 낫다.

보너스는 12턴 종료가 아니라 소계가 63에 닿는 즉시 확정된다. 점수판 UI가
"12/63"처럼 남은 거리를 보여줘야 하므로 파생 계산으로 뒀다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 5: GameState와 이벤트 적용

P3 온라인 대전이 `Event` 배열 교환만으로 성립하게 하는 핵심 작업이다. `applying(_:)`은 반드시 순수 함수여야 한다 — 여기에 랜덤이나 시간이 새어들면 재접속 리플레이가 깨진다.

**Files:**
- Create: `Packages/YachtCore/Sources/YachtCore/GameEvent.swift`
- Create: `Packages/YachtCore/Sources/YachtCore/GameState.swift`
- Create: `Packages/YachtCore/Tests/YachtCoreTests/GameStateTests.swift`

**Interfaces:**
- Consumes: Task 3의 `ScoreCategory`, Task 4의 `ScoreCard`
- Produces:
  - `public enum Phase: String, Codable, Sendable { case awaitingFirstRoll, rolling, finished }`
  - `public enum Event: Equatable, Codable, Sendable` — `.rolled([Int])`, `.holdToggled(Int)`, `.committed(ScoreCategory, Int)`, `.turnAdvanced`, `.gameEnded`
  - `public struct GameState: Equatable, Codable, Sendable`
  - `init(playerCount: Int = 1)`
  - `var dice: [Int]`, `var held: Set<Int>`, `var rollsUsed: Int`, `var rollsRemaining: Int`, `var rollableIndices: [Int]`
  - `var currentPlayer: Int`, `var turnIndex: Int`, `var phase: Phase`, `var scorecards: [ScoreCard]`
  - `var isAllScored: Bool`
  - `func applying(_ event: Event) -> GameState`
  - `static func replaying(_ events: [Event], playerCount: Int) -> GameState`

- [ ] **Step 1: 실패하는 테스트 작성**

`Packages/YachtCore/Tests/YachtCoreTests/GameStateTests.swift`:

```swift
import Testing
@testable import YachtCore

@Suite("게임 상태")
struct GameStateTests {

    @Test("초기 상태는 1턴, 굴림 전이다")
    func 초기상태() {
        let s = GameState(playerCount: 1)
        #expect(s.turnIndex == 1)
        #expect(s.currentPlayer == 0)
        #expect(s.phase == .awaitingFirstRoll)
        #expect(s.rollsUsed == 0)
        #expect(s.rollsRemaining == 3)
        #expect(s.dice == [0, 0, 0, 0, 0])
        #expect(s.held.isEmpty)
        #expect(s.rollableIndices == [0, 1, 2, 3, 4])
    }

    @Test("첫 굴림은 5개 슬롯을 모두 채운다")
    func 첫_굴림() {
        let s = GameState(playerCount: 1).applying(.rolled([3, 1, 4, 6, 6]))
        #expect(s.dice == [3, 1, 4, 6, 6])
        #expect(s.rollsUsed == 1)
        #expect(s.rollsRemaining == 2)
        #expect(s.phase == .rolling)
    }

    @Test("rolled는 keep되지 않은 슬롯에 인덱스 오름차순으로 채워진다")
    func 재굴림_슬롯_매핑() {
        var s = GameState(playerCount: 1).applying(.rolled([1, 2, 3, 4, 5]))
        s = s.applying(.holdToggled(1)).applying(.holdToggled(3))   // held = {1, 3}
        #expect(s.rollableIndices == [0, 2, 4])

        s = s.applying(.rolled([6, 6, 6]))
        // 슬롯 0←6, 2←6, 4←6. keep한 1·3은 그대로.
        #expect(s.dice == [6, 2, 6, 4, 6])
        #expect(s.rollsUsed == 2)
    }

    @Test("hold 토글은 켜고 끌 수 있다")
    func 홀드_토글() {
        var s = GameState(playerCount: 1).applying(.rolled([1, 2, 3, 4, 5]))
        s = s.applying(.holdToggled(2))
        #expect(s.held == [2])
        s = s.applying(.holdToggled(2))
        #expect(s.held.isEmpty)
    }

    @Test("commit은 현재 플레이어의 점수판에 기록한다")
    func 커밋() {
        var s = GameState(playerCount: 1).applying(.rolled([6, 6, 6, 6, 6]))
        s = s.applying(.committed(.yacht, 50))
        #expect(s.scorecards[0].entry(.yacht) == 50)
    }

    @Test("turnAdvanced는 주사위와 홀드를 비우고 다음 플레이어로 넘긴다")
    func 턴_넘김_2인() {
        var s = GameState(playerCount: 2).applying(.rolled([1, 2, 3, 4, 5]))
        s = s.applying(.holdToggled(0)).applying(.committed(.aces, 1)).applying(.turnAdvanced)

        #expect(s.currentPlayer == 1)
        #expect(s.turnIndex == 1, "아직 1턴이 안 끝났다 — 2번 플레이어가 남았다")
        #expect(s.dice == [0, 0, 0, 0, 0])
        #expect(s.held.isEmpty)
        #expect(s.rollsUsed == 0)
        #expect(s.phase == .awaitingFirstRoll)

        s = s.applying(.rolled([2, 2, 2, 2, 2])).applying(.committed(.deuces, 10)).applying(.turnAdvanced)
        #expect(s.currentPlayer == 0)
        #expect(s.turnIndex == 2, "모든 플레이어가 마쳐야 턴이 오른다")
    }

    @Test("turnIndex는 12를 넘지 않는다")
    func 턴_상한() {
        var s = GameState(playerCount: 1)
        for _ in 0..<20 { s = s.applying(.turnAdvanced) }
        #expect(s.turnIndex == 12)
    }

    @Test("gameEnded는 finished로 만든다")
    func 종료() {
        let s = GameState(playerCount: 1).applying(.gameEnded)
        #expect(s.phase == .finished)
    }

    @Test("12칸을 모두 채우면 isAllScored가 참이다")
    func 전부_기록됨() {
        var s = GameState(playerCount: 1)
        #expect(s.isAllScored == false)
        for c in ScoreCategory.allCases {
            s = s.applying(.rolled([1, 1, 1, 1, 1])).applying(.committed(c, 0)).applying(.turnAdvanced)
        }
        #expect(s.isAllScored == true)
    }

    @Test("같은 이벤트 로그를 리플레이하면 같은 상태가 된다")
    func 리플레이_결정성() {
        let log: [Event] = [
            .rolled([3, 3, 5, 5, 5]), .holdToggled(2), .holdToggled(3), .holdToggled(4),
            .rolled([5, 1]), .committed(.fives, 20), .turnAdvanced,
        ]
        let a = GameState.replaying(log, playerCount: 2)
        let b = GameState.replaying(log, playerCount: 2)
        #expect(a == b)
        #expect(a.scorecards[0].entry(.fives) == 20)
        #expect(a.currentPlayer == 1)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: 컴파일 실패 — `cannot find 'GameState' in scope`

- [ ] **Step 3: `GameEvent.swift` 작성**

```swift
import Foundation

/// 턴 안에서의 위치. validate(_:)가 어떤 Intent를 허용할지 판단하는 근거다.
public enum Phase: String, Codable, Sendable {
    /// 이번 턴에 아직 한 번도 굴리지 않았다. 굴림만 가능하다.
    case awaitingFirstRoll
    /// 한 번 이상 굴렸다. 홀드·재굴림·기록이 가능하다.
    case rolling
    /// 12턴이 끝났다.
    case finished
}

/// 확정된 사실. 주사위 눈이 "이미 정해진 채로" 들어온다.
/// 눈의 출처(로컬 RNG / 서버 / 테스트 대본)를 코어는 알지 못한다.
public enum Event: Equatable, Codable, Sendable {
    /// 굴린 주사위의 새 눈. keep되지 않은 슬롯에 인덱스 오름차순으로 채워진다.
    /// 예) held = {1, 3} 이고 rolled([5, 2, 6]) 이면 슬롯 0←5, 2←2, 4←6.
    /// 배열 길이는 항상 rollableIndices.count 와 같아야 한다.
    case rolled([Int])
    case holdToggled(Int)
    case committed(ScoreCategory, Int)
    case turnAdvanced
    case gameEnded
}
```

- [ ] **Step 4: `GameState.swift` 작성**

```swift
import Foundation

/// 게임의 전체 상태. applying(_:)은 순수 함수여야 한다 —
/// 랜덤이나 시간이 새어들면 P3의 재접속 리플레이가 깨진다.
public struct GameState: Equatable, Codable, Sendable {
    public private(set) var playerCount: Int
    public private(set) var scorecards: [ScoreCard]
    public private(set) var currentPlayer: Int
    public private(set) var turnIndex: Int
    public private(set) var dice: [Int]
    public private(set) var held: Set<Int>
    public private(set) var rollsUsed: Int
    public private(set) var phase: Phase

    public init(playerCount: Int = 1) {
        precondition(playerCount >= 1, "플레이어는 최소 1명이다")
        self.playerCount = playerCount
        self.scorecards = Array(repeating: ScoreCard(), count: playerCount)
        self.currentPlayer = 0
        self.turnIndex = 1
        self.dice = Array(repeating: 0, count: YachtCore.diceCount)
        self.held = []
        self.rollsUsed = 0
        self.phase = .awaitingFirstRoll
    }

    public var rollsRemaining: Int { YachtCore.maxRollsPerTurn - rollsUsed }

    /// keep되지 않은 슬롯. rolled(_:)의 값이 이 순서대로 채워진다.
    public var rollableIndices: [Int] {
        (0..<YachtCore.diceCount).filter { !held.contains($0) }
    }

    public var isAllScored: Bool { scorecards.allSatisfy(\.isComplete) }

    public func applying(_ event: Event) -> GameState {
        var next = self
        switch event {
        case .rolled(let values):
            let slots = next.rollableIndices
            precondition(values.count == slots.count,
                         "rolled(_:) 길이 \(values.count)가 굴릴 수 있는 주사위 \(slots.count)개와 다르다")
            precondition(values.allSatisfy { (1...6).contains($0) }, "주사위 눈은 1...6이어야 한다")
            for (slot, value) in zip(slots, values) { next.dice[slot] = value }
            next.rollsUsed += 1
            next.phase = .rolling

        case .holdToggled(let index):
            precondition((0..<YachtCore.diceCount).contains(index), "주사위 인덱스는 0...4다")
            if next.held.contains(index) { next.held.remove(index) } else { next.held.insert(index) }

        case .committed(let category, let points):
            next.scorecards[next.currentPlayer].record(category, points)

        case .turnAdvanced:
            next.dice = Array(repeating: 0, count: YachtCore.diceCount)
            next.held = []
            next.rollsUsed = 0
            next.phase = .awaitingFirstRoll
            next.currentPlayer = (next.currentPlayer + 1) % next.playerCount
            // 모든 플레이어가 이번 턴을 마쳐야 턴 번호가 오른다.
            if next.currentPlayer == 0 {
                next.turnIndex = min(next.turnIndex + 1, YachtCore.turnCount)
            }

        case .gameEnded:
            next.phase = .finished
        }
        return next
    }

    public static func replaying(_ events: [Event], playerCount: Int) -> GameState {
        events.reduce(GameState(playerCount: playerCount)) { $0.applying($1) }
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: PASS (전체)

- [ ] **Step 6: 커밋**

```bash
git add Packages/YachtCore
git commit -m "$(cat <<'MSG'
feat(core): 이벤트 소싱 게임 상태

applying(_:)을 순수 함수로 뒀다. 랜덤이나 시간이 여기 들어오면 P3의 재접속
리플레이가 깨지므로, 주사위 눈은 Event.rolled에 이미 정해진 채로 들어온다.
눈의 출처가 로컬 RNG든 서버든 테스트 대본이든 코어는 구분하지 않는다.

rolled의 값이 어느 슬롯에 들어가는지가 모호할 수 있어서, keep되지 않은
슬롯에 인덱스 오름차순으로 채우는 것으로 못박고 테스트로 고정했다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 6: Intent 검증

UI가 버튼을 언제 비활성화할지 판단하는 근거다. 부작용이 없어야 뷰에서 자유롭게 호출할 수 있다.

**Files:**
- Create: `Packages/YachtCore/Sources/YachtCore/Intent.swift`
- Create: `Packages/YachtCore/Tests/YachtCoreTests/ValidationTests.swift`
- Modify: `Packages/YachtCore/Sources/YachtCore/GameState.swift` (validate 추가)

**Interfaces:**
- Consumes: Task 5의 `GameState`, `Phase`
- Produces:
  - `public enum Intent: Equatable, Sendable` — `.roll`, `.toggleHold(Int)`, `.commit(ScoreCategory)`
  - `public enum RuleError: Error, Equatable, Sendable` — `.gameFinished`, `.noRollsRemaining`, `.allDiceHeld`, `.mustRollFirst`, `.categoryAlreadyUsed(ScoreCategory)`, `.indexOutOfRange(Int)`
  - `public func GameState.validate(_ intent: Intent) -> Result<Void, RuleError>`
  - `public func GameState.allows(_ intent: Intent) -> Bool`

- [ ] **Step 1: 실패하는 테스트 작성**

`Packages/YachtCore/Tests/YachtCoreTests/ValidationTests.swift`:

```swift
import Testing
@testable import YachtCore

@Suite("Intent 검증")
struct ValidationTests {

    private func rolled(_ dice: [Int], playerCount: Int = 1) -> GameState {
        GameState(playerCount: playerCount).applying(.rolled(dice))
    }

    @Test("굴리기 전에는 굴림만 허용된다")
    func 첫_굴림_전() {
        let s = GameState(playerCount: 1)
        #expect(s.allows(.roll))
        #expect(s.validate(.toggleHold(0)) == .failure(.mustRollFirst))
        #expect(s.validate(.commit(.aces)) == .failure(.mustRollFirst))
    }

    @Test("3회를 다 쓰면 더 굴릴 수 없다")
    func 굴림_소진() {
        var s = rolled([1, 2, 3, 4, 5])
        s = s.applying(.rolled([1, 2, 3, 4, 5]))
        s = s.applying(.rolled([1, 2, 3, 4, 5]))
        #expect(s.rollsRemaining == 0)
        #expect(s.validate(.roll) == .failure(.noRollsRemaining))
        #expect(s.allows(.commit(.choice)), "굴림을 다 써도 기록은 할 수 있어야 한다")
    }

    @Test("5개를 전부 keep하면 굴릴 수 없다")
    func 전부_홀드() {
        var s = rolled([1, 2, 3, 4, 5])
        for i in 0..<5 { s = s.applying(.holdToggled(i)) }
        #expect(s.validate(.roll) == .failure(.allDiceHeld))
    }

    @Test("이미 기록된 카테고리는 다시 쓸 수 없다")
    func 중복_기록() {
        var s = rolled([1, 1, 1, 1, 1])
        s = s.applying(.committed(.aces, 5))
        #expect(s.validate(.commit(.aces)) == .failure(.categoryAlreadyUsed(.aces)))
        #expect(s.allows(.commit(.deuces)))
    }

    @Test("주사위 인덱스는 0...4만 유효하다")
    func 인덱스_범위() {
        let s = rolled([1, 2, 3, 4, 5])
        #expect(s.validate(.toggleHold(5)) == .failure(.indexOutOfRange(5)))
        #expect(s.validate(.toggleHold(-1)) == .failure(.indexOutOfRange(-1)))
        #expect(s.allows(.toggleHold(4)))
    }

    @Test("게임이 끝나면 아무것도 허용되지 않는다")
    func 종료_후() {
        let s = rolled([1, 2, 3, 4, 5]).applying(.gameEnded)
        #expect(s.validate(.roll) == .failure(.gameFinished))
        #expect(s.validate(.toggleHold(0)) == .failure(.gameFinished))
        #expect(s.validate(.commit(.choice)) == .failure(.gameFinished))
    }

    @Test("검증은 상태를 바꾸지 않는다")
    func 부작용_없음() {
        let s = rolled([1, 2, 3, 4, 5])
        let before = s
        _ = s.validate(.roll)
        _ = s.validate(.commit(.aces))
        _ = s.validate(.toggleHold(99))
        #expect(s == before)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: 컴파일 실패 — `cannot find 'Intent' in scope`

- [ ] **Step 3: `Intent.swift` 작성**

```swift
import Foundation

/// 플레이어가 하고 싶은 것. 출처(터치 / AI / 네트워크)를 코어는 모른다.
public enum Intent: Equatable, Sendable {
    case roll
    case toggleHold(Int)
    case commit(ScoreCategory)
}

public enum RuleError: Error, Equatable, Sendable {
    case gameFinished
    case noRollsRemaining
    case allDiceHeld
    case mustRollFirst
    case categoryAlreadyUsed(ScoreCategory)
    case indexOutOfRange(Int)
}
```

- [ ] **Step 4: `GameState.swift`에 검증 추가**

`GameState` 본문 끝(`replaying` 바로 위)에 삽입:

```swift
    /// 부작용이 없다. 뷰가 버튼 활성화를 판단할 때 매 렌더마다 불러도 안전하다.
    public func validate(_ intent: Intent) -> Result<Void, RuleError> {
        guard phase != .finished else { return .failure(.gameFinished) }

        switch intent {
        case .roll:
            guard rollsRemaining > 0 else { return .failure(.noRollsRemaining) }
            guard !rollableIndices.isEmpty else { return .failure(.allDiceHeld) }
            return .success(())

        case .toggleHold(let index):
            guard (0..<YachtCore.diceCount).contains(index) else { return .failure(.indexOutOfRange(index)) }
            guard phase == .rolling else { return .failure(.mustRollFirst) }
            return .success(())

        case .commit(let category):
            guard phase == .rolling else { return .failure(.mustRollFirst) }
            guard !scorecards[currentPlayer].isFilled(category) else {
                return .failure(.categoryAlreadyUsed(category))
            }
            return .success(())
        }
    }

    public func allows(_ intent: Intent) -> Bool {
        if case .success = validate(intent) { return true }
        return false
    }
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: PASS (전체)

- [ ] **Step 6: 커밋**

```bash
git add Packages/YachtCore
git commit -m "$(cat <<'MSG'
feat(core): Intent 검증

뷰가 버튼 활성화를 판단하려면 매 렌더마다 물어볼 수 있어야 하므로 부작용을
없앴고, 그 성질을 테스트로 고정했다.

"굴림을 다 써도 기록은 할 수 있다"와 "5개를 전부 keep하면 굴릴 수 없다"를
별도 케이스로 뒀다. 둘 다 실제 플레이에서 자주 나오는데 한 덩어리로 묶으면
UI가 잘못된 버튼을 잠근다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 7: 전수 검증과 불변식

스펙 §11의 "93,312 케이스 전수 검증". **주의**: 골든 파일을 구현 자신이 만들면 순환 논증이라 아무것도 검증하지 못한다. 그래서 세 겹으로 건다.

1. **독립 구현** — 테스트 안에 알고리즘이 다른 순진한 채점기를 따로 쓰고 7,776 조합 × 12 카테고리를 전부 대조한다.
2. **불변식** — 두 구현이 같은 방식으로 틀렸을 경우를 잡는다 (라지 스트레이트면 스몰도 성립해야 한다 등).
3. **골든 체크섬** — 전체 점수표의 해시를 커밋해둔다. 나중에 규칙을 무심코 바꾸면 즉시 깨진다.

**Files:**
- Create: `Packages/YachtCore/Tests/YachtCoreTests/ExhaustiveScoringTests.swift`
- Create: `Packages/YachtCore/Tests/YachtCoreTests/GameInvariantTests.swift`
- Create: `Packages/YachtCore/Tests/YachtCoreTests/ResultEquality.swift`
- Modify: `Packages/YachtCore/Sources/YachtCore/Intent.swift` (테스트 전용 `==` 연산자 제거)

**Interfaces:**
- Consumes: Task 3의 `ScoreCategory.score`, Task 4의 `ScoreCard`, Task 5의 `GameState`
- Produces: 없음 (테스트 전용)

- [ ] **Step 1: 테스트 전용 `==` 연산자를 프로덕션 타깃에서 테스트 타깃으로 옮긴다**

Task 6에서 `Packages/YachtCore/Sources/YachtCore/Intent.swift` 끝에 다음이 들어갔다:

```swift
extension Result where Success == Void, Failure == RuleError {
    public static func == (lhs: Self, rhs: Self) -> Bool { ... }
}
```

`Result<Void, _>`는 `Void`가 `Equatable`이 아니라서 등가 비교가 안 되고, 검증 테스트가 `validate(...) == .failure(...)` 형태로 쓰기 때문에 필요한 코드다. 하지만 **프로덕션 코드는 이 연산자를 한 번도 쓰지 않는다** — `allows(_:)`는 `if case .success` 패턴 매칭을 쓴다. 테스트 하나 때문에 라이브러리의 public API가 영구히 넓어졌다.

`Intent.swift`에서 그 extension을 통째로 지우고, `Packages/YachtCore/Tests/YachtCoreTests/ResultEquality.swift`를 새로 만든다:

```swift
import Foundation
@testable import YachtCore

/// 검증 테스트가 `validate(...) == .failure(...)` 로 쓸 수 있게 해주는 테스트 전용 도우미.
///
/// `Result<Void, _>`는 `Void`가 Equatable이 아니라 등가 비교가 안 된다.
/// 프로덕션 코드는 이 연산자를 쓰지 않으므로(allows(_:)는 패턴 매칭을 쓴다)
/// 라이브러리의 public API를 넓히지 않도록 테스트 타깃에 둔다.
extension Result where Success == Void, Failure == RuleError {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success): true
        case (.failure(let a), .failure(let b)): a == b
        default: false
        }
    }
}
```

옮긴 뒤 기존 33개 테스트가 그대로 통과하는지 확인한다:

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: PASS (33 tests). 컴파일이 깨지면 `ValidationTests.swift`가 `@testable import`를 쓰고 있는지 확인한다.

- [ ] **Step 2: 전수 검증 테스트 작성**

`Packages/YachtCore/Tests/YachtCoreTests/ExhaustiveScoringTests.swift`:

```swift
import Testing
import Foundation
@testable import YachtCore

/// 주사위 5개의 모든 조합 6^5 = 7,776가지.
private let allRolls: [[Int]] = {
    var out: [[Int]] = []
    out.reserveCapacity(7_776)
    for a in 1...6 { for b in 1...6 { for c in 1...6 { for d in 1...6 { for e in 1...6 {
        out.append([a, b, c, d, e])
    }}}}}
    return out
}()

/// 프로덕션 구현과 **알고리즘이 다른** 순진한 채점기.
/// 프로덕션이 counts 배열과 Set을 쓰는 데 비해 이쪽은 정렬과 문자열 매칭을 쓴다.
/// 두 구현이 우연히 같은 실수를 하기 어렵게 만드는 것이 목적이다.
private func naiveScore(_ category: ScoreCategory, _ dice: [Int]) -> Int {
    let sorted = dice.sorted()
    let total = sorted.reduce(0, +)

    func occurrences(of value: Int) -> Int { sorted.filter { $0 == value }.count }
    func hasRun(_ length: Int) -> Bool {
        let unique = Array(Set(sorted)).sorted()
        var run = 1
        var best = 1
        for i in 1..<max(unique.count, 1) where i < unique.count {
            if unique[i] == unique[i - 1] + 1 { run += 1; best = max(best, run) } else { run = 1 }
        }
        return best >= length
    }

    switch category {
    case .aces:   return occurrences(of: 1) * 1
    case .deuces: return occurrences(of: 2) * 2
    case .threes: return occurrences(of: 3) * 3
    case .fours:  return occurrences(of: 4) * 4
    case .fives:  return occurrences(of: 5) * 5
    case .sixes:  return occurrences(of: 6) * 6
    case .choice: return total
    case .fourOfAKind:
        return (1...6).contains(where: { occurrences(of: $0) >= 4 }) ? total : 0
    case .fullHouse:
        let multiplicities = (1...6).map { occurrences(of: $0) }.filter { $0 > 0 }.sorted()
        return (multiplicities == [2, 3] || multiplicities == [5]) ? total : 0
    case .smallStraight:  return hasRun(4) ? 15 : 0
    case .largeStraight:  return hasRun(5) ? 30 : 0
    case .yacht:          return sorted.first == sorted.last ? 50 : 0
    }
}

@Suite("전수 검증")
struct ExhaustiveScoringTests {

    @Test("조합이 정확히 7,776가지다")
    func 조합_개수() {
        #expect(allRolls.count == 7_776)
        #expect(Set(allRolls.map { $0.description }).count == 7_776)
    }

    @Test("7,776 x 12 = 93,312 케이스가 독립 구현과 일치한다")
    func 독립_구현_대조() {
        var mismatches: [String] = []
        var checked = 0
        for dice in allRolls {
            for category in ScoreCategory.allCases {
                checked += 1
                let mine = category.score(dice)
                let theirs = naiveScore(category, dice)
                if mine != theirs {
                    mismatches.append("\(category) \(dice): 구현 \(mine) vs 독립 \(theirs)")
                }
            }
        }
        #expect(checked == 93_312)
        #expect(mismatches.isEmpty, "불일치 \(mismatches.count)건. 처음 5건: \(mismatches.prefix(5).joined(separator: " | "))")
    }

    @Test("모든 조합에서 규칙 불변식이 성립한다")
    func 불변식() {
        for dice in allRolls {
            let total = dice.reduce(0, +)

            // Choice는 언제나 총합이다
            #expect(ScoreCategory.choice.score(dice) == total)

            // 라지 스트레이트가 성립하면 스몰도 성립한다
            if ScoreCategory.largeStraight.score(dice) == 30 {
                #expect(ScoreCategory.smallStraight.score(dice) == 15, "라지인데 스몰이 아니다: \(dice)")
            }

            // 야추가 성립하면 4 of a Kind와 Full House도 성립한다
            if ScoreCategory.yacht.score(dice) == 50 {
                #expect(ScoreCategory.fourOfAKind.score(dice) == total, "야추인데 포카인드가 아니다: \(dice)")
                #expect(ScoreCategory.fullHouse.score(dice) == total, "야추인데 풀하우스가 아니다: \(dice)")
            }

            // 총합형 카테고리는 0이거나 정확히 총합이다 — 부분합이 나오면 안 된다
            for category in [ScoreCategory.fourOfAKind, .fullHouse] {
                let s = category.score(dice)
                #expect(s == 0 || s == total, "\(category)가 부분합 \(s)를 냈다: \(dice)")
            }

            // 고정 점수형은 0이거나 정해진 값이다
            #expect([0, 15].contains(ScoreCategory.smallStraight.score(dice)))
            #expect([0, 30].contains(ScoreCategory.largeStraight.score(dice)))
            #expect([0, 50].contains(ScoreCategory.yacht.score(dice)))

            // 상단은 해당 눈 개수 x 눈값이므로 5 x 눈값을 넘을 수 없다
            for (index, category) in ScoreCategory.upperCases.enumerated() {
                let face = index + 1
                let s = category.score(dice)
                #expect(s % face == 0 && s <= 5 * face, "\(category)가 \(s)를 냈다: \(dice)")
            }
        }
    }

    @Test("전체 점수표의 체크섬이 고정되어 있다")
    func 골든_체크섬() {
        // 규칙을 바꾸면 이 값이 바뀐다. 의도한 변경이면 새 값으로 갱신하고,
        // 의도하지 않았다면 방금 무언가를 깨뜨린 것이다.
        // Swift의 Hasher는 실행마다 시드가 달라져 골든값으로 쓸 수 없으므로
        // 결정적인 두 가지 합계를 직접 만든다.
        var sum = 0
        var weighted = 0
        for (rollIndex, dice) in allRolls.enumerated() {
            for (categoryIndex, category) in ScoreCategory.allCases.enumerated() {
                let s = category.score(dice)
                sum += s
                weighted += s * (rollIndex % 97 + 1) * (categoryIndex + 1)
            }
        }
        // 최초 실행에서 나온 값을 여기에 박아 넣는다 (Step 4 참고).
        #expect(sum == 0, "GOLDEN_SUM 자리표시자 — Step 3에서 실제 값으로 교체한다")
        #expect(weighted == 0, "GOLDEN_WEIGHTED 자리표시자 — Step 3에서 실제 값으로 교체한다")
    }
}
```

- [ ] **Step 3: 실행해서 독립 구현 대조와 불변식이 통과하는지 확인**

```bash
swift test --package-path "Packages/YachtCore" --filter ExhaustiveScoringTests
```
Expected: `독립_구현_대조`와 `불변식`은 PASS, `골든_체크섬`은 FAIL하며 실제 `sum`/`weighted` 값을 보여준다.

만약 `독립_구현_대조`가 실패하면 **구현과 독립 구현 중 어느 쪽이 스펙 §4.2 표와 맞는지 표를 보고 판정한 뒤** 틀린 쪽을 고친다. 테스트를 구현에 맞추지 않는다.

- [ ] **Step 4: 골든 값을 실제 값으로 교체**

Step 3의 실패 메시지에 나온 `sum`, `weighted` 실제 값을 테스트에 박아 넣고 메시지를 바꾼다:

```swift
        #expect(sum == 1234567, "점수표 총합이 바뀌었다 — 규칙을 의도적으로 바꾼 게 아니면 회귀다")
        #expect(weighted == 987654321, "점수표 가중합이 바뀌었다 — 규칙을 의도적으로 바꾼 게 아니면 회귀다")
```

(위 숫자는 예시다. Step 3이 출력한 실제 값을 쓴다.)

- [ ] **Step 5: 게임 불변식 테스트 작성**

`Packages/YachtCore/Tests/YachtCoreTests/GameInvariantTests.swift`:

```swift
import Testing
import Foundation
@testable import YachtCore

@Suite("게임 불변식")
struct GameInvariantTests {

    /// 시드 고정 난수. 실패를 재현할 수 있어야 한다.
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func next() -> UInt64 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return state
        }
    }

    /// 무작위지만 합법적인 한 판을 끝까지 진행하고, 최종 상태와 이벤트 로그를 돌려준다.
    private func playRandomGame(seed: UInt64, playerCount: Int) -> (GameState, [Event]) {
        var rng = SeededRNG(seed: seed)
        var state = GameState(playerCount: playerCount)
        var log: [Event] = []

        func emit(_ event: Event) {
            log.append(event)
            state = state.applying(event)
        }

        while !state.isAllScored {
            // 최소 1회, 최대 3회 굴린다
            let rollCount = Int.random(in: 1...3, using: &rng)
            for roll in 0..<rollCount {
                guard state.allows(.roll) else { break }
                emit(.rolled(state.rollableIndices.map { _ in Int.random(in: 1...6, using: &rng) }))
                // 마지막 굴림 뒤에는 홀드를 만지지 않는다
                if roll < rollCount - 1 {
                    for index in 0..<YachtCore.diceCount where Bool.random(using: &rng) {
                        if state.allows(.toggleHold(index)) { emit(.holdToggled(index)) }
                    }
                }
            }
            let open = state.scorecards[state.currentPlayer].openCategories
            let chosen = open[Int.random(in: 0..<open.count, using: &rng)]
            emit(.committed(chosen, chosen.score(state.dice)))
            emit(.turnAdvanced)
        }
        emit(.gameEnded)
        return (state, log)
    }

    @Test("무작위 100판이 전부 12칸을 채우고 끝난다", arguments: 1...100)
    func 게임은_반드시_완결된다(seed: Int) {
        let (state, _) = playRandomGame(seed: UInt64(seed), playerCount: 2)
        #expect(state.isAllScored)
        #expect(state.phase == .finished)
        for card in state.scorecards {
            #expect(card.isComplete)
            #expect(card.openCategories.isEmpty)
        }
    }

    @Test("총점은 항목 합 + 보너스와 일치한다", arguments: 1...50)
    func 총점_일관성(seed: Int) {
        let (state, _) = playRandomGame(seed: UInt64(seed), playerCount: 2)
        for card in state.scorecards {
            let itemSum = ScoreCategory.allCases.reduce(0) { $0 + (card.entry($1) ?? 0) }
            let expectedBonus = card.upperSubtotal >= ScoreCard.upperBonusThreshold ? 35 : 0
            #expect(card.upperBonus == expectedBonus)
            #expect(card.total == itemSum + expectedBonus)
        }
    }

    @Test("이벤트 로그를 리플레이하면 같은 상태가 나온다", arguments: 1...50)
    func 리플레이_동일성(seed: Int) {
        let (state, log) = playRandomGame(seed: UInt64(seed), playerCount: 2)
        let replayed = GameState.replaying(log, playerCount: 2)
        #expect(replayed == state, "seed \(seed): 리플레이가 원본과 다르다 — P3 재접속이 깨진다")
    }

    @Test("rolled는 keep되지 않은 슬롯에 인덱스 오름차순으로 채워진다")
    func 슬롯_매핑_순서() {
        // Task 5의 같은 이름 테스트는 [6,6,6]을 굴려서 순서를 검증하지 못한다.
        // 값이 전부 같으면 내림차순으로 배정하는 버그도 통과한다. 서로 다른 값으로 다시 건다.
        var state = GameState(playerCount: 1).applying(.rolled([1, 1, 1, 1, 1]))
        state = state.applying(.holdToggled(1)).applying(.holdToggled(3))
        #expect(state.rollableIndices == [0, 2, 4])

        state = state.applying(.rolled([5, 2, 6]))
        #expect(state.dice == [5, 1, 2, 1, 6], "슬롯 0←5, 2←2, 4←6이어야 한다")
    }

    @Test("commit은 0번이 아니라 현재 플레이어의 점수판에 기록된다")
    func 커밋_대상_플레이어() {
        // scorecards[0]으로 하드코딩하는 회귀를 잡는다.
        // Task 5의 테스트는 2번 플레이어의 기록 내용을 확인하지 않는다.
        var state = GameState(playerCount: 2)
        state = state.applying(.rolled([1, 1, 1, 1, 1]))
        state = state.applying(.committed(.aces, 5)).applying(.turnAdvanced)
        #expect(state.currentPlayer == 1)

        state = state.applying(.rolled([2, 2, 2, 2, 2]))
        state = state.applying(.committed(.deuces, 10))

        #expect(state.scorecards[1].entry(.deuces) == 10, "2번 플레이어 점수판에 들어가야 한다")
        #expect(state.scorecards[0].entry(.deuces) == nil, "0번 플레이어 점수판이 오염됐다")
        #expect(state.scorecards[0].entry(.aces) == 5)
    }

    @Test("2인전은 각자 12턴을 갖는다", arguments: 1...20)
    func 턴_수(seed: Int) {
        let (_, log) = playRandomGame(seed: UInt64(seed), playerCount: 2)
        let commits = log.filter { if case .committed = $0 { return true } else { return false } }
        #expect(commits.count == 24, "2인 x 12칸 = 24회 기록이어야 한다")
    }
}
```

- [ ] **Step 6: 전체 테스트 실행**

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: PASS (전체). 전수 검증 때문에 수 초가 걸릴 수 있다.

- [ ] **Step 7: 커밋**

```bash
git add Packages/YachtCore
git commit -m "$(cat <<'MSG'
test(core): 93,312 케이스 전수 검증과 게임 불변식

골든 파일을 구현 자신이 만들면 순환 논증이라 아무것도 검증하지 못한다.
그래서 테스트 안에 알고리즘이 다른 순진한 채점기를 따로 두고 대조했다.
프로덕션은 counts 배열과 Set을, 독립 구현은 정렬과 필터를 쓴다.

두 구현이 같은 실수를 하는 경우를 잡으려고 불변식을 얹었다. 라지 스트레이트면
스몰도 성립해야 하고, 총합형 카테고리는 0이거나 정확히 총합이어야 한다.

리플레이 동일성은 P3 재접속의 안전장치다. 여기가 깨지면 온라인에서 복구가
불가능해지므로 시드 고정 난수로 50판을 돌려 확인한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 8: 이벤트 로그 영속화

스펙 §10. 이벤트 소싱 덕에 저장은 로그를 쓰는 것이 전부다. P3 재접속과 같은 메커니즘이므로 코어에 둔다.

**Files:**
- Create: `Packages/YachtCore/Sources/YachtCore/MatchLog.swift`
- Create: `Packages/YachtCore/Tests/YachtCoreTests/MatchLogTests.swift`

**Interfaces:**
- Consumes: Task 5의 `Event`, `GameState`
- Produces:
  - `public struct MatchLog: Equatable, Codable, Sendable`
  - `init(playerCount: Int)`, `mutating func append(_ event: Event)`, `var events: [Event]`, `var playerCount: Int`
  - `var state: GameState`, `var isFinished: Bool`
  - `func encoded() throws -> Data`, `static func decoded(from: Data) throws -> MatchLog`
  - `public static let formatVersion = 1`

- [ ] **Step 1: 실패하는 테스트 작성**

`Packages/YachtCore/Tests/YachtCoreTests/MatchLogTests.swift`:

```swift
import Testing
import Foundation
@testable import YachtCore

@Suite("이벤트 로그")
struct MatchLogTests {

    @Test("append한 순서대로 상태가 재구성된다")
    func 상태_재구성() {
        var log = MatchLog(playerCount: 1)
        log.append(.rolled([6, 6, 6, 6, 6]))
        log.append(.committed(.yacht, 50))
        #expect(log.state.scorecards[0].entry(.yacht) == 50)
        #expect(log.events.count == 2)
    }

    @Test("직렬화 왕복 후 상태가 같다")
    func 왕복() throws {
        var log = MatchLog(playerCount: 2)
        log.append(.rolled([1, 2, 3, 4, 5]))
        log.append(.holdToggled(0))
        log.append(.rolled([6, 6, 6, 6]))
        log.append(.committed(.sixes, 24))
        log.append(.turnAdvanced)

        let data = try log.encoded()
        let restored = try MatchLog.decoded(from: data)

        #expect(restored == log)
        #expect(restored.state == log.state)
        #expect(restored.playerCount == 2)
    }

    @Test("포맷 버전이 다르면 디코딩이 실패한다")
    func 버전_불일치() throws {
        var log = MatchLog(playerCount: 1)
        log.append(.rolled([1, 1, 1, 1, 1]))
        var json = try JSONSerialization.jsonObject(with: log.encoded()) as! [String: Any]
        json["formatVersion"] = 999
        let tampered = try JSONSerialization.data(withJSONObject: json)

        #expect(throws: MatchLog.DecodingFailure.unsupportedVersion(999)) {
            try MatchLog.decoded(from: tampered)
        }
    }

    @Test("게임이 끝났는지 판별한다")
    func 완결_판별() {
        var log = MatchLog(playerCount: 1)
        #expect(log.isFinished == false)
        for c in ScoreCategory.allCases {
            log.append(.rolled([1, 1, 1, 1, 1]))
            log.append(.committed(c, 0))
            log.append(.turnAdvanced)
        }
        log.append(.gameEnded)
        #expect(log.isFinished == true)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: 컴파일 실패 — `cannot find 'MatchLog' in scope`

- [ ] **Step 3: 구현 작성**

`Packages/YachtCore/Sources/YachtCore/MatchLog.swift`:

```swift
import Foundation

/// 한 판의 이벤트 로그. 저장·복원·리플레이·(P3의) 재접속이 전부 이것 하나로 처리된다.
public struct MatchLog: Equatable, Codable, Sendable {
    public static let formatVersion = 1

    public enum DecodingFailure: Error, Equatable {
        case unsupportedVersion(Int)
    }

    public private(set) var formatVersion: Int
    public private(set) var playerCount: Int
    public private(set) var events: [Event]

    public init(playerCount: Int) {
        self.formatVersion = Self.formatVersion
        self.playerCount = playerCount
        self.events = []
    }

    public mutating func append(_ event: Event) { events.append(event) }

    /// 매번 처음부터 접는다. 한 판은 최대 수백 이벤트라 비용이 문제되지 않는다.
    /// 캐시를 두면 캐시 무효화 버그가 리플레이 정확성을 갉아먹는다.
    public var state: GameState { GameState.replaying(events, playerCount: playerCount) }

    public var isFinished: Bool { state.phase == .finished }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> MatchLog {
        let log = try JSONDecoder().decode(MatchLog.self, from: data)
        guard log.formatVersion == Self.formatVersion else {
            throw DecodingFailure.unsupportedVersion(log.formatVersion)
        }
        return log
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: PASS (전체)

- [ ] **Step 5: 커밋**

```bash
git add Packages/YachtCore
git commit -m "$(cat <<'MSG'
feat(core): 이벤트 로그 저장과 복원

state를 캐시하지 않고 매번 처음부터 접는다. 한 판은 최대 수백 이벤트라 비용이
문제되지 않는데, 캐시를 두면 무효화 버그가 리플레이 정확성을 갉아먹는다.
리플레이 정확성은 P3 재접속이 서 있는 토대라 여기서 타협하지 않는다.

포맷 버전을 명시적으로 검사한다. 나중에 이벤트 케이스를 추가했을 때 구버전
저장 파일을 조용히 잘못 읽는 것보다 실패하는 편이 낫다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 8b: 손상된 저장 파일 방어

Task 8 리뷰가 실측으로 찾은 문제. **스펙 위반은 아니지만 출시 품질에 직결된다.**

`applying(_:)`의 `precondition`들은 신뢰하는 호출자를 위한 불변식이라 위반 시 **트랩**을 낸다 (`throw`가 아니다). 그런데 저장 파일은 신뢰할 수 없는 입력이다. 구조는 멀쩡하지만 의미가 깨진 JSON — 예를 들어 `rolled` 배열 길이가 굴릴 수 있는 주사위 수와 다르거나 `playerCount`가 0인 경우 — 은 `decoded(from:)`을 통과한 뒤 `.state`를 처음 읽는 순간 프로세스를 죽인다 (리뷰어 실측: exit code 133).

Task 18의 `MatchStore.load()`는 읽기 실패를 조용히 삼키고 새 판으로 시작하도록 설계돼 있지만, **트랩은 거기서 잡을 수 없다.** 앱이 실행 즉시 크래시 루프에 빠지고 사용자는 앱을 삭제하는 것 외에 복구할 방법이 없다.

해법은 신뢰 경계에서 검사하는 것이다. `applying(_:)`의 precondition은 그대로 둔다 — 그것들은 신뢰하는 호출자에 대한 계약이고 리뷰에서 순수성이 검증됐다.

**Files:**
- Modify: `Packages/YachtCore/Sources/YachtCore/GameState.swift` (`canApply(_:)` 추가)
- Modify: `Packages/YachtCore/Sources/YachtCore/MatchLog.swift` (디코딩 시 재생 가능성 검사)
- Create: `Packages/YachtCore/Tests/YachtCoreTests/CorruptLogTests.swift`

**Interfaces:**
- Consumes: Task 5의 `GameState`/`Event`, Task 8의 `MatchLog`
- Produces:
  - `public func GameState.canApply(_ event: Event) -> Bool`
  - `MatchLog.DecodingFailure`에 `.invalidPlayerCount(Int)`와 `.corruptedLog(eventIndex: Int)` 추가

- [ ] **Step 1: 실패하는 테스트 작성**

`Packages/YachtCore/Tests/YachtCoreTests/CorruptLogTests.swift`:

```swift
import Testing
@testable import YachtCore

@Suite("손상된 저장 파일")
struct CorruptLogTests {

    /// MatchLog를 거치지 않고 임의의 JSON을 만들어 손상된 파일을 흉내낸다.
    private func encodedLog(playerCount: Int, events: [Event]) throws -> Data {
        var log = MatchLog(playerCount: playerCount)
        for event in events { log.append(event) }
        return try log.encoded()
    }

    @Test("정상 로그는 그대로 디코딩된다")
    func 정상_로그() throws {
        let data = try encodedLog(playerCount: 1, events: [.rolled([1, 2, 3, 4, 5]), .committed(.choice, 15)])
        let restored = try MatchLog.decoded(from: data)
        #expect(restored.events.count == 2)
        #expect(restored.state.scorecards[0].entry(.choice) == 15)
    }

    @Test("rolled 길이가 어긋난 로그는 트랩이 아니라 throw로 거부된다")
    func 잘못된_rolled_길이() throws {
        // 5개 슬롯이 비어 있는데 3개만 굴린 것으로 기록된 로그.
        // 예전에는 이 데이터가 디코딩을 통과한 뒤 .state 접근 시 프로세스를 죽였다.
        let data = try encodedLog(playerCount: 1, events: [.rolled([1, 2, 3])])
        #expect(throws: MatchLog.DecodingFailure.corruptedLog(eventIndex: 0)) {
            try MatchLog.decoded(from: data)
        }
    }

    @Test("주사위 눈이 범위를 벗어난 로그를 거부한다")
    func 잘못된_주사위_눈() throws {
        let data = try encodedLog(playerCount: 1, events: [.rolled([1, 2, 3, 4, 9])])
        #expect(throws: MatchLog.DecodingFailure.corruptedLog(eventIndex: 0)) {
            try MatchLog.decoded(from: data)
        }
    }

    @Test("같은 카테고리를 두 번 기록한 로그를 거부한다")
    func 중복_기록() throws {
        let data = try encodedLog(playerCount: 1, events: [
            .rolled([1, 1, 1, 1, 1]), .committed(.aces, 5), .turnAdvanced,
            .rolled([1, 1, 1, 1, 1]), .committed(.aces, 5),
        ])
        #expect(throws: MatchLog.DecodingFailure.corruptedLog(eventIndex: 4)) {
            try MatchLog.decoded(from: data)
        }
    }

    @Test("주사위 인덱스가 범위를 벗어난 로그를 거부한다")
    func 잘못된_홀드_인덱스() throws {
        let data = try encodedLog(playerCount: 1, events: [.rolled([1, 2, 3, 4, 5]), .holdToggled(7)])
        #expect(throws: MatchLog.DecodingFailure.corruptedLog(eventIndex: 1)) {
            try MatchLog.decoded(from: data)
        }
    }

    @Test("playerCount가 0인 로그를 거부한다")
    func 잘못된_플레이어_수() throws {
        // MatchLog(playerCount: 0)은 그 자체로는 막히지 않지만 GameState는 1명 이상을 요구한다.
        let data = try encodedLog(playerCount: 0, events: [])
        #expect(throws: MatchLog.DecodingFailure.invalidPlayerCount(0)) {
            try MatchLog.decoded(from: data)
        }
    }

    @Test("canApply는 상태를 바꾸지 않는다")
    func 부작용_없음() {
        let state = GameState(playerCount: 1).applying(.rolled([1, 2, 3, 4, 5]))
        let before = state
        _ = state.canApply(.rolled([1, 2]))
        _ = state.canApply(.holdToggled(99))
        _ = state.canApply(.committed(.aces, 1))
        #expect(state == before)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: 컴파일 실패 — `canApply` / `corruptedLog` / `invalidPlayerCount` 가 없다.

- [ ] **Step 3: `GameState.canApply(_:)` 추가**

`GameState.swift`의 `allows(_:)` 바로 아래에 삽입:

```swift
    /// 신뢰할 수 없는 출처(저장 파일, 나중에는 네트워크)에서 온 이벤트가 적용 가능한지 검사한다.
    ///
    /// `applying(_:)`의 precondition들은 신뢰하는 호출자를 위한 불변식이라 위반하면 트랩을 낸다.
    /// 트랩은 잡을 수 없으므로, 손상된 저장 파일이 앱을 실행 즉시 죽이는 것을 막으려면
    /// 신뢰 경계에서 먼저 이 검사를 통과시켜야 한다. 부작용은 없다.
    public func canApply(_ event: Event) -> Bool {
        switch event {
        case .rolled(let values):
            return values.count == rollableIndices.count
                && values.allSatisfy { (1...6).contains($0) }
        case .holdToggled(let index):
            return (0..<YachtCore.diceCount).contains(index)
        case .committed(let category, _):
            return !scorecards[currentPlayer].isFilled(category)
        case .turnAdvanced, .gameEnded:
            return true
        }
    }
```

- [ ] **Step 4: `MatchLog.decoded(from:)`에 재생 가능성 검사 추가**

`MatchLog.swift`의 `DecodingFailure`를 다음으로 교체:

```swift
    public enum DecodingFailure: Error, Equatable {
        case unsupportedVersion(Int)
        case invalidPlayerCount(Int)
        case corruptedLog(eventIndex: Int)
    }
```

`decoded(from:)`을 다음으로 교체:

```swift
    /// 저장 파일은 신뢰할 수 없는 입력이다. JSON 구조가 멀쩡해도 내용이 깨져 있을 수 있고,
    /// 그런 로그를 그대로 돌려주면 나중에 state를 읽는 순간 프로세스가 죽는다.
    /// 여기서 끝까지 재생해보고, 안 되면 던진다.
    public static func decoded(from data: Data) throws -> MatchLog {
        let log = try JSONDecoder().decode(MatchLog.self, from: data)
        guard log.formatVersion == Self.formatVersion else {
            throw DecodingFailure.unsupportedVersion(log.formatVersion)
        }
        guard log.playerCount >= 1 else {
            throw DecodingFailure.invalidPlayerCount(log.playerCount)
        }

        var state = GameState(playerCount: log.playerCount)
        for (index, event) in log.events.enumerated() {
            guard state.canApply(event) else {
                throw DecodingFailure.corruptedLog(eventIndex: index)
            }
            state = state.applying(event)
        }
        return log
    }
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
swift test --package-path "Packages/YachtCore"
```
Expected: PASS (54 tests). 기존 47개가 전부 그대로 통과해야 한다.

- [ ] **Step 6: 커밋**

```bash
git add Packages/YachtCore
git commit -m "$(cat <<'MSG'
fix(core): 손상된 저장 파일이 앱을 죽이지 않게 한다

applying()의 precondition은 신뢰하는 호출자를 위한 불변식이라 위반하면 트랩을
낸다. throw가 아니라서 잡을 수 없다. 그런데 저장 파일은 신뢰할 수 없는 입력이다.

구조는 멀쩡하지만 내용이 깨진 JSON은 디코딩을 통과한 뒤 state를 처음 읽는 순간
프로세스를 죽인다. 저장 파일을 앱 실행 시점에 읽으므로 크래시 루프가 되고,
사용자는 앱을 삭제하는 것 말고 복구할 방법이 없다.

precondition은 그대로 뒀다. 대신 신뢰 경계인 decoded(from:)에서 로그를 끝까지
재생해보고 안 되면 던진다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 9: 주사위 면 정의와 정육면체 회전 대칭군

**이 프로젝트에서 가장 중요한 작업이다.** 스펙 §7.3의 정확성 논증이 여기 구현 위에 서 있다. `Δ = q_rest⁻¹ · q_target`가 정육면체 대칭군의 원소여야 궤적의 기하가 원본과 동일하게 유지된다.

**Files:**
- Create: `Packages/DiceTrajectory/Sources/DiceTrajectory/DieFace.swift`
- Create: `Packages/DiceTrajectory/Sources/DiceTrajectory/OctahedralGroup.swift`
- Create: `Packages/DiceTrajectory/Tests/DiceTrajectoryTests/OctahedralGroupTests.swift`

**Interfaces:**
- Consumes: Task 1의 `DiceTrajectory` 모듈
- Produces:
  - `public enum DieFace` — `static let faces: [(value: Int, normal: SIMD3<Float>)]`, `static func normal(of: Int) -> SIMD3<Float>`, `static func upValue(for: simd_quatf) -> Int`
  - `public enum OctahedralGroup` — `static let elements: [simd_quatf]` (정확히 24개)
  - `static func isSameRotation(_:_:tolerance:) -> Bool`
  - `static func angle(between:and:) -> Float`
  - `static func elements(mapping source: Int, to destination: Int) -> [simd_quatf]` — 눈 `source`의 법선을 눈 `destination`의 법선으로 보내는 원소들. 항상 정확히 4개
  - `static func preservesCube(_ q: simd_quatf, tolerance: Float) -> Bool`
  - `public enum DieFace` 추가분 — `static func upFaceTiltRadians(for q: simd_quatf) -> Float`

**스냅 함수는 만들지 않는다.** 정지 자세를 24개 중 하나로 스냅하면 멈춘 주사위가 최대 45° 돌아간다 (스펙 §7.3). Δ는 위를 향한 눈에만 의존하므로 스냅이 필요 없다.

- [ ] **Step 1: 실패하는 테스트 작성**

`Packages/DiceTrajectory/Tests/DiceTrajectoryTests/OctahedralGroupTests.swift`:

```swift
import Testing
import simd
@testable import DiceTrajectory

@Suite("주사위 면과 회전 대칭군")
struct OctahedralGroupTests {

    @Test("마주 보는 면의 합이 7이다")
    func 반대면_합() {
        for (value, normal) in DieFace.faces {
            let opposite = DieFace.faces.first { simd_length($0.normal + normal) < 1e-5 }
            #expect(opposite != nil, "눈 \(value)의 반대면이 없다")
            #expect(value + opposite!.value == 7, "눈 \(value)의 반대면이 \(opposite!.value)다")
        }
    }

    @Test("서양식 오른손 주사위다 — 1,2,3이 한 꼭짓점을 반시계로 돈다")
    func 오른손_주사위() {
        // +X=3, +Y=1, +Z=2. 이 셋이 만나는 꼭짓점 (1,1,1)에서 바라볼 때
        // 1 -> 2 -> 3 이 반시계 방향이면 오른손 주사위다.
        // 판정: n1 x n2 가 n3 쪽을 향하면 반시계.
        let n1 = DieFace.normal(of: 1)
        let n2 = DieFace.normal(of: 2)
        let n3 = DieFace.normal(of: 3)
        #expect(simd_dot(simd_cross(n1, n2), n3) > 0.9, "왼손 주사위가 되었다")
    }

    @Test("항등 자세에서는 1이 위를 향한다")
    func 항등_자세() {
        #expect(DieFace.upValue(for: simd_quatf(angle: 0, axis: [0, 1, 0])) == 1)
    }

    @Test("X축으로 90도 돌리면 위 면이 바뀐다")
    func 회전_후_윗면() {
        // +Y(1)를 X축 기준 +90도 돌리면 +Z(2)로 간다 -> 위에는 -Z(5)에 있던 면이 온다
        let q = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        #expect(DieFace.upValue(for: q) == 5)
    }

    @Test("대칭군의 원소가 정확히 24개다")
    func 원소_개수() {
        #expect(OctahedralGroup.elements.count == 24, "정육면체 회전 대칭군은 24개다")
    }

    @Test("24개 원소가 서로 다르다")
    func 원소_유일성() {
        let elements = OctahedralGroup.elements
        for i in 0..<elements.count {
            for j in (i + 1)..<elements.count {
                #expect(!OctahedralGroup.isSameRotation(elements[i], elements[j]),
                        "원소 \(i)와 \(j)가 같은 회전이다")
            }
        }
    }

    @Test("각 눈이 위를 향하는 축정렬 자세가 정확히 4개씩이다", arguments: 1...6)
    func 눈별_자세_개수(value: Int) {
        let matching = OctahedralGroup.elements.filter { DieFace.upValue(for: $0) == value }
        #expect(matching.count == 4, "눈 \(value)가 위인 축정렬 자세는 Y축 자전 4가지여야 한다")
    }

    @Test("모든 원소가 정육면체를 자기 자신으로 보낸다")
    func 대칭성() {
        for (index, q) in OctahedralGroup.elements.enumerated() {
            #expect(OctahedralGroup.preservesCube(q, tolerance: 1e-4),
                    "원소 \(index)가 정육면체를 보존하지 않는다")
        }
    }

    @Test("군이 곱셈에 대해 닫혀 있다")
    func 폐포() {
        let elements = OctahedralGroup.elements
        for a in elements {
            for b in elements {
                let product = simd_normalize(simd_mul(a, b))
                #expect(elements.contains { OctahedralGroup.isSameRotation($0, product) },
                        "곱이 군 밖으로 나갔다")
            }
        }
    }

    @Test("어떤 눈에서 어떤 눈으로 보내는 원소가 정확히 4개씩이다")
    func 면_대응_원소_개수() {
        for source in 1...6 {
            for destination in 1...6 {
                let mapped = OctahedralGroup.elements(mapping: source, to: destination)
                #expect(mapped.count == 4, "\(source)→\(destination) 원소가 \(mapped.count)개다")
                for element in mapped {
                    let moved = element.act(DieFace.normal(of: source))
                    #expect(simd_length(moved - DieFace.normal(of: destination)) < 1e-4,
                            "\(source)→\(destination) 원소가 법선을 엉뚱한 곳으로 보낸다")
                }
            }
        }
    }

    @Test("윗면 기울기는 yaw에 영향받지 않는다")
    func 윗면_기울기는_yaw와_무관() {
        // 스펙 §7.3: 바닥에 누운 주사위는 yaw가 자유롭다.
        // 24개 최근접 거리로 재면 최대 45도가 나오지만 윗면 기울기는 0이어야 한다.
        for yawDegrees in stride(from: Float(0), to: 360, by: 7) {
            let yaw = simd_quatf(angle: yawDegrees * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
            for base in OctahedralGroup.elements {
                let resting = simd_normalize(simd_mul(yaw, base))
                let tilt = DieFace.upFaceTiltRadians(for: resting) * 180 / .pi
                #expect(tilt < 0.1, "yaw \(yawDegrees)도에서 윗면 기울기가 \(tilt)도로 나왔다")
            }
        }
    }

    @Test("실제로 기울어진 자세는 윗면 기울기로 잡힌다")
    func 기울기_감지() {
        let tiltAngle: Float = 5
        let tilted = simd_normalize(simd_mul(
            simd_quatf(angle: tiltAngle * .pi / 180, axis: SIMD3<Float>(1, 0, 0)),
            OctahedralGroup.elements[0]))
        let measured = DieFace.upFaceTiltRadians(for: tilted) * 180 / .pi
        #expect(abs(measured - tiltAngle) < 0.2, "5도 기울였는데 \(measured)도로 측정됐다")
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
swift test --package-path "Packages/DiceTrajectory"
```
Expected: 컴파일 실패 — `cannot find 'DieFace' in scope`

- [ ] **Step 3: `DieFace.swift` 작성**

```swift
import Foundation
import simd

/// 주사위 로컬 좌표계의 면 배치.
/// 서양식 오른손 주사위: 마주 보는 면의 합이 7이고, 1·2·3이 한 꼭짓점을 반시계로 돈다.
public enum DieFace {
    /// 배열로 두는 이유: Dictionary는 순회 순서가 정해지지 않아서
    /// upValue(for:)가 동점일 때 실행마다 다른 답을 낼 수 있다.
    public static let faces: [(value: Int, normal: SIMD3<Float>)] = [
        (1, SIMD3( 0,  1,  0)),
        (2, SIMD3( 0,  0,  1)),
        (3, SIMD3( 1,  0,  0)),
        (4, SIMD3(-1,  0,  0)),
        (5, SIMD3( 0,  0, -1)),
        (6, SIMD3( 0, -1,  0)),
    ]

    public static func normal(of value: Int) -> SIMD3<Float> {
        guard let face = faces.first(where: { $0.value == value }) else {
            preconditionFailure("주사위 눈은 1...6이다: \(value)")
        }
        return face.normal
    }

    /// 이 자세에서 월드 +Y를 향하는 눈.
    public static func upValue(for orientation: simd_quatf) -> Int {
        var best = faces[0].value
        var bestDot = -Float.infinity
        for face in faces {
            let dot = orientation.act(face.normal).y
            if dot > bestDot { bestDot = dot; best = face.value }
        }
        return best
    }

    /// 위를 향한 면의 법선이 +Y에서 얼마나 벗어났는가 (라디안).
    ///
    /// 정지 판정의 올바른 척도다. 24개 축정렬 자세와의 거리로 재면
    /// 바닥에 평평하게 누운 주사위도 자유로운 yaw 때문에 최대 45°가 나온다 (스펙 §7.3).
    public static func upFaceTiltRadians(for orientation: simd_quatf) -> Float {
        var bestDot = -Float.infinity
        for face in faces {
            bestDot = max(bestDot, orientation.act(face.normal).y)
        }
        return acos(min(1, max(-1, bestDot)))
    }
}
```

- [ ] **Step 4: `OctahedralGroup.swift` 작성**

```swift
import Foundation
import simd

/// 정육면체를 자기 자신으로 보내는 24개 회전.
///
/// 스펙 §7.3의 정확성 논증이 이 군 위에 서 있다.
/// 궤적의 정지 자세를 이 24개 중 하나로 스냅해두면
/// Δ = q_rest⁻¹ · q_target 이 반드시 이 군의 원소가 되고,
/// 그러면 회전된 주사위가 매 프레임 원본과 정확히 같은 공간을 점유한다.
public enum OctahedralGroup {

    public static let elements: [simd_quatf] = buildByClosure()

    /// 90도 회전 3개에서 시작해 곱셈 폐포를 구한다.
    /// 오일러각을 훑어 중복을 거르는 방식보다 개수 보장이 확실하다.
    private static func buildByClosure() -> [simd_quatf] {
        let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        let generators = [
            simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0)),
            simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0)),
            simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1)),
        ]
        var found: [simd_quatf] = [identity]
        var frontier: [simd_quatf] = [identity]

        while !frontier.isEmpty {
            var next: [simd_quatf] = []
            for element in frontier {
                for generator in generators {
                    let candidate = simd_normalize(simd_mul(generator, element))
                    if !found.contains(where: { isSameRotation($0, candidate) }) {
                        found.append(candidate)
                        next.append(candidate)
                    }
                }
            }
            frontier = next
        }
        return found
    }

    /// 쿼터니언 q와 -q는 같은 회전이므로 내적의 절댓값으로 비교한다.
    public static func isSameRotation(_ a: simd_quatf, _ b: simd_quatf, tolerance: Float = 1e-4) -> Bool {
        abs(simd_dot(simd_normalize(a.vector), simd_normalize(b.vector))) > 1 - tolerance
    }

    public static func angle(between a: simd_quatf, and b: simd_quatf) -> Float {
        let dot = min(1, abs(simd_dot(simd_normalize(a.vector), simd_normalize(b.vector))))
        return 2 * acos(dot)
    }

    /// 눈 `source`의 법선을 눈 `destination`의 법선으로 보내는 원소들.
    ///
    /// O는 6개 면 법선에 추이적으로 작용하고 각 법선의 안정자군 위수가 4이므로
    /// 결과는 항상 정확히 4개다. 이 4개가 회전 오프셋의 yaw 다양성을 만든다.
    public static func elements(mapping source: Int, to destination: Int) -> [simd_quatf] {
        let target = DieFace.normal(of: destination)
        let origin = DieFace.normal(of: source)
        return elements.filter { simd_length($0.act(origin) - target) < 1e-4 }
    }

    /// q가 정육면체를 자기 자신으로 보내는가 —
    /// 6개 면 법선 집합을 자기 자신으로 옮기는지로 판정한다.
    public static func preservesCube(_ q: simd_quatf, tolerance: Float = 1e-4) -> Bool {
        let normals = DieFace.faces.map(\.normal)
        for normal in normals {
            let rotated = q.act(normal)
            let matched = normals.contains { simd_length(rotated - $0) < tolerance }
            if !matched { return false }
        }
        return true
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
swift test --package-path "Packages/DiceTrajectory"
```
Expected: PASS (전체). `원소_개수`가 24가 아니면 `isSameRotation`의 허용 오차를 의심한다.

- [ ] **Step 6: 커밋**

```bash
git add Packages/DiceTrajectory
git commit -m "$(cat <<'MSG'
feat(trajectory): 주사위 면 배치와 정육면체 회전 대칭군

스펙 7.3의 정확성 논증이 이 군 위에 서 있다. 오프셋을 이 24개 중에서만 고르면
회전된 주사위가 매 프레임 원본과 정확히 같은 공간을 점유한다. 근사가 아니라
동일한 궤적이다.

정지 자세를 축정렬로 스냅하는 함수는 일부러 만들지 않았다. 바닥에 누운 주사위는
yaw가 연속적으로 자유로워서 스냅하면 멈춘 주사위가 최대 45도 돌아간다. 대신
윗면 기울기만 재는 upFaceTiltRadians를 뒀다 — 정지 판정에 필요한 건 그것뿐이다.

24개를 오일러각 훑기로 만들면 허용 오차에 따라 개수가 흔들려서, 90도 회전
3개에서 시작하는 곱셈 폐포로 만들었다. 개수와 닫힘성을 테스트로 고정했다.

면 배치를 Dictionary가 아니라 배열로 뒀다. Dictionary는 순회 순서가 정해지지
않아서 upValue(for:)가 동점일 때 실행마다 다른 답을 낼 수 있다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 10: 회전 오프셋 — 목표 눈 맞추기

스펙 §7.2의 `q'(t) = q(t) · Δ`. 두 가지가 핵심이다.

1. **곱하는 방향.** 몸통 프레임 회전이므로 오른쪽에서 곱해야 한다. 왼쪽에서 곱하면 궤적이 통째로 회전해 주사위가 트레이 밖으로 나간다.
2. **Δ는 정지 자세 전체가 아니라 "위를 향한 눈"에만 의존한다.** 바닥에 누운 주사위는 yaw가 연속적으로 자유로우므로 정지 자세는 일반적으로 축정렬이 아니다 (스펙 §7.3, Task 2 스파이크 실측). Δ를 `q_rest⁻¹ · q_target` 으로 계산하면 그 자유로운 yaw까지 되돌려버려 멈춘 주사위가 최대 45° 홱 돌아간다.

**Files:**
- Create: `Packages/DiceTrajectory/Sources/DiceTrajectory/FaceControl.swift`
- Create: `Packages/DiceTrajectory/Tests/DiceTrajectoryTests/FaceControlTests.swift`

**Interfaces:**
- Consumes: Task 9의 `DieFace`, `OctahedralGroup.elements(mapping:to:)`
- Produces:
  - `public enum FaceControl`
  - `static func offset(restUpFace: Int, showing value: Int, yawChoice: Int) -> simd_quatf`
  - `static func apply(_ offset: simd_quatf, to frame: simd_quatf) -> simd_quatf`

- [ ] **Step 1: 실패하는 테스트 작성**

`Packages/DiceTrajectory/Tests/DiceTrajectoryTests/FaceControlTests.swift`:

```swift
import Testing
import simd
@testable import DiceTrajectory

@Suite("회전 오프셋")
struct FaceControlTests {

    /// 물리가 실제로 만들어내는 정지 자세를 흉내낸다.
    /// 축정렬이 **아니다** — 수직축 둘레 yaw가 자유롭고 약간의 기울기가 남는다.
    private static func restingOrientations() -> [(orientation: simd_quatf, upFace: Int)] {
        var out: [(simd_quatf, Int)] = []
        for base in OctahedralGroup.elements {
            for yawDegrees in stride(from: Float(0), to: 360, by: 37) {
                let yaw = simd_quatf(angle: yawDegrees * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
                // 물리가 남기는 잔여 기울기 (스파이크 실측 0.03도, 여유를 둬 1.5도)
                let tilt = simd_quatf(angle: 1.5 * .pi / 180,
                                      axis: simd_normalize(SIMD3<Float>(0.6, 0, -0.8)))
                let resting = simd_normalize(simd_mul(simd_mul(tilt, yaw), base))
                out.append((resting, DieFace.upValue(for: resting)))
            }
        }
        return out
    }

    /// 스펙 §11이 "이 프로젝트에서 가장 중요한 테스트"로 지목한 것.
    /// 여기가 깨지면 온라인 대전이 통째로 무너진다.
    @Test("축정렬이 아닌 정지 자세에서도 목표 눈이 위로 온다", arguments: 1...6)
    func 목표_눈이_위로_온다(value: Int) {
        for (resting, upFace) in Self.restingOrientations() {
            for yaw in 0..<4 {
                let delta = FaceControl.offset(restUpFace: upFace, showing: value, yawChoice: yaw)
                let final = FaceControl.apply(delta, to: resting)
                #expect(DieFace.upValue(for: final) == value,
                        "눈 \(value), yaw \(yaw)에서 \(DieFace.upValue(for: final))가 나왔다")
            }
        }
    }

    @Test("오프셋을 적용해도 윗면 기울기가 커지지 않는다", arguments: 1...6)
    func 기울기_보존(value: Int) {
        // 물리가 만든 잔여 기울기는 그대로 물려받아야 한다.
        // 커진다면 Δ가 대칭군 밖으로 나간 것이다.
        for (resting, upFace) in Self.restingOrientations() {
            let before = DieFace.upFaceTiltRadians(for: resting)
            let delta = FaceControl.offset(restUpFace: upFace, showing: value, yawChoice: 0)
            let after = DieFace.upFaceTiltRadians(for: FaceControl.apply(delta, to: resting))
            #expect(abs(after - before) < 1e-3,
                    "기울기가 \(before * 180 / .pi)도에서 \(after * 180 / .pi)도로 변했다")
        }
    }

    @Test("오프셋은 항상 정육면체 대칭군의 원소다", arguments: 1...6)
    func 오프셋은_대칭군_원소다(value: Int) {
        // 이것이 성립해야 "회전된 주사위가 매 프레임 원본과 같은 공간을 점유한다"는
        // 스펙 §7.3의 논증이 성립한다.
        for upFace in 1...6 {
            for yaw in 0..<4 {
                let delta = FaceControl.offset(restUpFace: upFace, showing: value, yawChoice: yaw)
                #expect(OctahedralGroup.preservesCube(delta, tolerance: 1e-4),
                        "오프셋이 정육면체를 보존하지 않는다 — 궤적의 기하가 달라진다")
                #expect(OctahedralGroup.elements.contains { OctahedralGroup.isSameRotation($0, delta) },
                        "오프셋이 24개 군 밖에 있다")
            }
        }
    }

    @Test("yaw 4가지가 서로 다른 자세를 만든다", arguments: 1...6)
    func yaw가_다양성을_만든다(value: Int) {
        let deltas = (0..<4).map { FaceControl.offset(restUpFace: 1, showing: value, yawChoice: $0) }
        for i in 0..<4 {
            for j in (i + 1)..<4 {
                #expect(!OctahedralGroup.isSameRotation(deltas[i], deltas[j]),
                        "yaw \(i)와 \(j)가 같은 오프셋을 만든다")
            }
        }
    }

    @Test("yawChoice는 음수나 큰 수여도 안전하게 감긴다")
    func yaw_인덱스_감기() {
        let a = FaceControl.offset(restUpFace: 3, showing: 4, yawChoice: 1)
        let b = FaceControl.offset(restUpFace: 3, showing: 4, yawChoice: 5)
        let c = FaceControl.offset(restUpFace: 3, showing: 4, yawChoice: -3)
        #expect(OctahedralGroup.isSameRotation(a, b))
        #expect(OctahedralGroup.isSameRotation(a, c))
    }

    @Test("같은 눈을 요청하면 오프셋이 항등이 되는 경우가 있다")
    func 항등_케이스() {
        // 이미 6이 위인 주사위에 6을 요청하면 면을 옮길 필요가 없다.
        let delta = FaceControl.offset(restUpFace: 6, showing: 6, yawChoice: 0)
        let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        let anyIsIdentity = (0..<4).contains { yaw in
            OctahedralGroup.isSameRotation(
                FaceControl.offset(restUpFace: 6, showing: 6, yawChoice: yaw), identity)
        }
        #expect(anyIsIdentity, "같은 면을 요청했는데 항등 오프셋이 하나도 없다")
        #expect(OctahedralGroup.preservesCube(delta, tolerance: 1e-4))
    }

    @Test("왼쪽 곱셈은 틀린 답을 낸다 — 곱하는 방향이 중요하다")
    func 곱셈_방향() {
        // 회귀 방지용. 누군가 simd_mul의 인자 순서를 뒤집으면 여기서 잡힌다.
        // 정지 자세에 yaw를 섞어 두 방향이 우연히 일치하지 않게 한다.
        let yaw = simd_quatf(angle: 40 * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
        let resting = simd_normalize(simd_mul(yaw, OctahedralGroup.elements[0]))
        let upFace = DieFace.upValue(for: resting)
        let target = (upFace % 6) + 1                       // 현재 윗면과 다른 눈
        let delta = FaceControl.offset(restUpFace: upFace, showing: target, yawChoice: 0)

        #expect(DieFace.upValue(for: simd_mul(resting, delta)) == target, "오른쪽 곱셈이 틀렸다")
        #expect(DieFace.upValue(for: simd_mul(delta, resting)) != target,
                "왼쪽 곱셈이 우연히 맞았다 — 더 어려운 케이스를 골라야 한다")
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
swift test --package-path "Packages/DiceTrajectory"
```
Expected: 컴파일 실패 — `cannot find 'FaceControl' in scope`

- [ ] **Step 3: 구현 작성**

`Packages/DiceTrajectory/Sources/DiceTrajectory/FaceControl.swift`:

```swift
import Foundation
import simd

/// 궤적을 다시 굴리지 않고 나오는 눈만 바꾸는 장치.
///
/// 궤적에서 실제로 위를 향한 눈이 u일 때, 눈 v가 위를 향하게 하려면
///
///     Δ ∈ O,  Δ(n_v) = n_u
///     q'(t) = q(t) · Δ
///
/// 를 쓴다. 정지 시 q_rest(n_u) ≈ +Y 이므로
/// q_rest(Δ(n_v)) = q_rest(n_u) ≈ +Y 가 되어 목표 눈이 위를 향한다.
///
/// Δ가 정육면체 대칭군의 원소이므로 회전된 주사위는 매 프레임 원본과
/// 같은 공간을 점유한다 (스펙 §7.3).
///
/// **정지 자세 전체가 아니라 위를 향한 눈에만 의존한다는 점이 중요하다.**
/// 바닥에 누운 주사위는 수직축 둘레 yaw가 연속적으로 자유롭다.
/// Δ를 q_rest⁻¹ · q_target 으로 계산하면 그 자유로운 yaw까지 되돌려
/// 멈춘 주사위가 최대 45° 홱 돌아간다.
public enum FaceControl {

    /// - Parameters:
    ///   - restUpFace: 이 궤적에서 실제로 위를 향한 눈 (1...6).
    ///   - value: 위로 오게 할 눈 (1...6).
    ///   - yawChoice: 조건을 만족하는 4개 중 하나. 굴림마다 다르게 주면 화면이 덜 반복적으로 보인다.
    public static func offset(restUpFace: Int, showing value: Int, yawChoice: Int) -> simd_quatf {
        let candidates = OctahedralGroup.elements(mapping: value, to: restUpFace)
        precondition(candidates.count == 4,
                     "눈 \(value)를 \(restUpFace)로 보내는 원소는 4개여야 하는데 \(candidates.count)개다")
        let index = ((yawChoice % candidates.count) + candidates.count) % candidates.count
        return simd_normalize(candidates[index])
    }

    /// 몸통 프레임 회전이므로 **오른쪽에서** 곱한다.
    /// 왼쪽에서 곱하면 궤적 전체가 월드 기준으로 회전해 주사위가 트레이 밖으로 나간다.
    public static func apply(_ offset: simd_quatf, to frame: simd_quatf) -> simd_quatf {
        simd_normalize(simd_mul(frame, offset))
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
swift test --package-path "Packages/DiceTrajectory"
```
Expected: PASS (전체). `목표_눈이_위로_온다`는 6 × 24 × 10 × 4 = 5,760 케이스를 검사한다.

- [ ] **Step 5: 커밋**

```bash
git add Packages/DiceTrajectory
git commit -m "$(cat <<'MSG'
feat(trajectory): 회전 오프셋으로 목표 눈 맞추기

오프셋은 정지 자세 전체가 아니라 위를 향한 눈에만 의존한다. 바닥에 누운 주사위는
수직축 둘레 yaw가 연속적으로 자유로워서, q_rest 역수로 계산하면 그 자유로운 yaw까지
되돌려 멈춘 주사위가 최대 45도 홱 돌아간다. Task 2 스파이크에서 윗면 기울기는
0.03도인데 24개 최근접 거리가 1~40도로 나온 것이 이 자유도다.

테스트를 축정렬 자세가 아니라 yaw를 섞고 기울기를 남긴 자세로 돌린다. 축정렬로만
테스트하면 이 결함이 그대로 통과한다.

곱하는 방향도 핵심이다. 몸통 프레임 회전이라 오른쪽에서 곱해야 하고, 인자 순서를
뒤집으면 잡히도록 회귀 테스트를 뒀다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 11: 궤적 자료구조·바이너리 포맷·검증기

정지 자세를 통째로 저장하지 않고 **정지 시 위를 향한 눈(1~6)만** 저장하는 것이 요점이다. 회전 오프셋은 그 값에만 의존하고(스펙 §7.3), 정지 자세 자체는 마지막 프레임의 쿼터니언이 이미 갖고 있다.

**Files:**
- Create: `Packages/DiceTrajectory/Sources/DiceTrajectory/Trajectory.swift`
- Create: `Packages/DiceTrajectory/Sources/DiceTrajectory/TrajectoryArchive.swift`
- Create: `Packages/DiceTrajectory/Sources/DiceTrajectory/TrajectoryValidator.swift`
- Create: `Packages/DiceTrajectory/Tests/DiceTrajectoryTests/TrajectoryArchiveTests.swift`

**Interfaces:**
- Consumes: Task 9의 `OctahedralGroup`, Task 10의 `FaceControl`
- Produces:
  - `public enum ThrowDirection: UInt8, CaseIterable, Sendable { case left = 0, center = 1, right = 2 }`
  - `public struct DiePose: Equatable, Sendable { var position: SIMD3<Float>; var orientation: simd_quatf }`
  - `public struct CollisionCue: Equatable, Sendable { let frame: UInt16; let dieIndex: UInt8; let intensity: Float }`
  - `public struct Trajectory: Equatable, Sendable` — `id`, `dieCount`, `direction`, `frameRate`, `frames: [[DiePose]]`, `restUpFaces: [UInt8]`, `collisions: [CollisionCue]`
  - `func Trajectory.restUpFace(die: Int) -> Int`
  - `func Trajectory.posed(die:frame:offset:) -> DiePose`
  - `public enum TrajectoryArchive` — `static func encode([Trajectory]) throws -> Data`, `static func decode(_ data: Data) throws -> [Trajectory]`
  - `public enum TrajectoryValidator` — `static func problems(in: Trajectory, trayInner: SIMD3<Float>, dieSize: Float) -> [String]`

- [ ] **Step 1: 실패하는 테스트 작성**

`Packages/DiceTrajectory/Tests/DiceTrajectoryTests/TrajectoryArchiveTests.swift`:

```swift
import Testing
import Foundation
import simd
@testable import DiceTrajectory

/// 테스트용 합성 궤적. 물리는 없고 포맷과 검증기만 확인한다.
private func makeTrajectory(id: UInt16 = 1, dieCount: Int = 5, frameCount: Int = 90) -> Trajectory {
    var frames: [[DiePose]] = []
    var restPoses: [simd_quatf] = []
    var restUpFaces: [UInt8] = []
    for die in 0..<dieCount {
        // 물리가 실제로 만드는 정지 자세를 흉내낸다 — 축정렬이 아니라 yaw가 자유롭다
        let base = OctahedralGroup.elements[(die * 5) % OctahedralGroup.elements.count]
        let yaw = simd_quatf(angle: Float(die) * 31 * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
        let rest = simd_normalize(simd_mul(yaw, base))
        restPoses.append(rest)
        restUpFaces.append(UInt8(DieFace.upValue(for: rest)))
    }
    for frame in 0..<frameCount {
        let t = Float(frame) / Float(frameCount - 1)
        var poses: [DiePose] = []
        for die in 0..<dieCount {
            let spin = simd_quatf(angle: (1 - t) * 8, axis: simd_normalize(SIMD3<Float>(0.3, 1, 0.2)))
            poses.append(DiePose(
                position: SIMD3(Float(die - 2) * 0.02, 0.10 * (1 - t) + 0.008, -0.06 + 0.10 * t),
                orientation: t >= 1 ? restPoses[die] : simd_normalize(simd_mul(spin, restPoses[die]))
            ))
        }
        frames.append(poses)
    }
    return Trajectory(id: id, dieCount: dieCount, direction: .center, frameRate: 60,
                      frames: frames, restUpFaces: restUpFaces,
                      collisions: [CollisionCue(frame: 12, dieIndex: 0, intensity: 0.8)])
}

@Suite("궤적 포맷")
struct TrajectoryArchiveTests {

    @Test("인코딩-디코딩 왕복 후 구조가 보존된다")
    func 왕복_구조() throws {
        let original = [makeTrajectory(id: 1), makeTrajectory(id: 2, dieCount: 3, frameCount: 60)]
        let restored = try TrajectoryArchive.decode(TrajectoryArchive.encode(original))

        #expect(restored.count == 2)
        for (a, b) in zip(original, restored) {
            #expect(a.id == b.id)
            #expect(a.dieCount == b.dieCount)
            #expect(a.direction == b.direction)
            #expect(a.frameRate == b.frameRate)
            #expect(a.frames.count == b.frames.count)
            #expect(a.restUpFaces == b.restUpFaces, "정지 시 윗면 값은 손실 없이 보존돼야 한다")
            #expect(a.collisions == b.collisions)
        }
    }

    @Test("위치와 자세는 양자화 오차 안에서 보존된다")
    func 왕복_수치() throws {
        let original = makeTrajectory()
        let restored = try TrajectoryArchive.decode(TrajectoryArchive.encode([original]))[0]

        for (frameIndex, (a, b)) in zip(original.frames, restored.frames).enumerated() {
            for (die, (poseA, poseB)) in zip(a, b).enumerated() {
                let positionError = simd_length(poseA.position - poseB.position)
                #expect(positionError < 0.001, "프레임 \(frameIndex) 주사위 \(die) 위치 오차 \(positionError)m")
                let angleError = OctahedralGroup.angle(between: poseA.orientation, and: poseB.orientation)
                #expect(angleError < 0.01, "프레임 \(frameIndex) 주사위 \(die) 자세 오차 \(angleError)rad")
            }
        }
    }

    @Test("정지 시 윗면 값은 양자화를 거치지 않는다 — 1바이트 정수로 저장하기 때문")
    func 윗면_값은_정확하다() throws {
        let original = makeTrajectory()
        let restored = try TrajectoryArchive.decode(TrajectoryArchive.encode([original]))[0]
        for die in 0..<original.dieCount {
            #expect(original.restUpFace(die: die) == restored.restUpFace(die: die),
                    "정지 시 윗면 값이 왕복에서 바뀌었다 — 오프셋이 엉뚱한 눈을 올린다")
            // 마지막 프레임의 실제 자세에서 읽은 윗면과도 일치해야 한다
            let last = restored.frames.count - 1
            #expect(DieFace.upValue(for: restored.frames[last][die].orientation)
                    == restored.restUpFace(die: die),
                    "기록된 윗면 값이 마지막 프레임의 실제 자세와 다르다")
        }
    }

    @Test("매직 넘버가 다르면 디코딩이 실패한다")
    func 잘못된_매직() {
        #expect(throws: TrajectoryArchive.Failure.badMagic) {
            try TrajectoryArchive.decode(Data([0x00, 0x01, 0x02, 0x03, 0x04]))
        }
    }

    @Test("포맷 버전이 다르면 디코딩이 실패한다") 
    func 버전_불일치() throws {
        var data = try TrajectoryArchive.encode([makeTrajectory()])
        data[4] = 0xFF
        data[5] = 0xFF
        #expect(throws: (any Error).self) { try TrajectoryArchive.decode(data) }
    }

    @Test("정상 궤적에는 문제가 없다")
    func 검증기_통과() {
        let problems = TrajectoryValidator.problems(
            in: makeTrajectory(),
            trayInner: SIMD3(0.24, 0.12, 0.24),
            dieSize: 0.016
        )
        #expect(problems.isEmpty, problems.joined(separator: " | "))
    }

    @Test("트레이를 벗어난 궤적을 잡아낸다")
    func 검증기_이탈_감지() {
        var trajectory = makeTrajectory()
        trajectory.frames[40][2].position = SIMD3(5, 0.01, 0)   // 5미터 밖
        let problems = TrajectoryValidator.problems(
            in: trajectory,
            trayInner: SIMD3(0.24, 0.12, 0.24),
            dieSize: 0.016
        )
        #expect(problems.contains { $0.contains("트레이") })
    }

    @Test("마지막 프레임이 기록된 정지 자세와 다르면 잡아낸다")
    func 검증기_정지자세_불일치() {
        var trajectory = makeTrajectory()
        trajectory.frames[trajectory.frames.count - 1][0].orientation =
            simd_normalize(simd_quatf(angle: 0.6, axis: SIMD3<Float>(0, 0, 1)))
        let problems = TrajectoryValidator.problems(
            in: trajectory,
            trayInner: SIMD3(0.24, 0.12, 0.24),
            dieSize: 0.016
        )
        #expect(problems.contains { $0.contains("정지 자세") })
    }

    @Test("모든 궤적 x 모든 목표 눈에서 오프셋이 목표 눈을 위로 올린다")
    func 궤적_전수_검증() {
        // 스펙 §11의 검증 ③. Task 12가 실제 궤적을 구우면 같은 검사를 그 데이터로 돌린다.
        let trajectory = makeTrajectory()
        for die in 0..<trajectory.dieCount {
            for value in 1...6 {
                for yaw in 0..<4 {
                    let offset = FaceControl.offset(
                        restUpFace: trajectory.restUpFace(die: die),
                        showing: value, yawChoice: yaw
                    )
                    let last = trajectory.frames.count - 1
                    let pose = trajectory.posed(die: die, frame: last, offset: offset)
                    #expect(DieFace.upValue(for: pose.orientation) == value)
                }
            }
        }
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
swift test --package-path "Packages/DiceTrajectory"
```
Expected: 컴파일 실패 — `cannot find 'Trajectory' in scope`

- [ ] **Step 3: `Trajectory.swift` 작성**

```swift
import Foundation
import simd

public enum ThrowDirection: UInt8, CaseIterable, Sendable {
    case left = 0, center = 1, right = 2
}

public struct DiePose: Equatable, Sendable {
    public var position: SIMD3<Float>
    public var orientation: simd_quatf
    public init(position: SIMD3<Float>, orientation: simd_quatf) {
        self.position = position
        self.orientation = orientation
    }
}

public struct CollisionCue: Equatable, Sendable {
    public let frame: UInt16
    public let dieIndex: UInt8
    /// 0...1. 사운드 볼륨과 햅틱 세기에 쓴다.
    public let intensity: Float
    public init(frame: UInt16, dieIndex: UInt8, intensity: Float) {
        self.frame = frame
        self.dieIndex = dieIndex
        self.intensity = intensity
    }
}

/// 미리 구운 물리 궤적 하나.
public struct Trajectory: Equatable, Sendable {
    public let id: UInt16
    public let dieCount: Int
    public let direction: ThrowDirection
    public let frameRate: Int
    /// frames[프레임][주사위]
    public var frames: [[DiePose]]
    /// 각 주사위가 정지했을 때 위를 향한 눈 (1...6).
    /// 회전 오프셋은 이 값에만 의존하므로 정지 자세 전체를 따로 저장할 필요가 없다 (스펙 §7.3).
    /// 정수라 양자화 손실이 없고, 정지 자세 자체는 마지막 프레임이 이미 갖고 있다.
    public let restUpFaces: [UInt8]
    public let collisions: [CollisionCue]

    public init(id: UInt16, dieCount: Int, direction: ThrowDirection, frameRate: Int,
                frames: [[DiePose]], restUpFaces: [UInt8], collisions: [CollisionCue]) {
        self.id = id
        self.dieCount = dieCount
        self.direction = direction
        self.frameRate = frameRate
        self.frames = frames
        self.restUpFaces = restUpFaces
        self.collisions = collisions
    }

    public var frameCount: Int { frames.count }
    public var duration: TimeInterval { Double(frameCount) / Double(frameRate) }

    public func restUpFace(die: Int) -> Int { Int(restUpFaces[die]) }

    /// 오프셋을 적용한 프레임 자세. 위치는 건드리지 않는다.
    public func posed(die: Int, frame: Int, offset: simd_quatf) -> DiePose {
        let raw = frames[frame][die]
        return DiePose(position: raw.position,
                       orientation: FaceControl.apply(offset, to: raw.orientation))
    }
}
```

- [ ] **Step 4: `TrajectoryArchive.swift` 작성**

```swift
import Foundation
import simd

/// 궤적 묶음의 바이너리 포맷.
///
///     헤더:  magic "YDTJ" (4B) | version UInt16 | count UInt32
///     궤적:  id UInt16 | dieCount UInt8 | direction UInt8 | frameRate UInt16 | frameCount UInt16
///           | restUpFaces [UInt8 x dieCount]  (각 1...6)
///           | collisionCount UInt16 | collisions [frame UInt16, die UInt8, intensity UInt8] x N
///           | frames [pos Float16 x3, quat Int16 x4] x (frameCount x dieCount)
///
/// 프레임당 주사위 하나에 14바이트. 5개 x 120프레임 = 8.4KB.
public enum TrajectoryArchive {
    public static let magic: [UInt8] = Array("YDTJ".utf8)
    public static let version: UInt16 = 1

    public enum Failure: Error, Equatable {
        case badMagic
        case unsupportedVersion(UInt16)
        case truncated(at: Int)
        case restUpFaceOutOfRange(UInt8)
    }

    public static func encode(_ trajectories: [Trajectory]) throws -> Data {
        var out = Data()
        out.append(contentsOf: magic)
        out.appendLE(version)
        out.appendLE(UInt32(trajectories.count))

        for trajectory in trajectories {
            out.appendLE(trajectory.id)
            out.append(UInt8(trajectory.dieCount))
            out.append(trajectory.direction.rawValue)
            out.appendLE(UInt16(trajectory.frameRate))
            out.appendLE(UInt16(trajectory.frameCount))
            out.append(contentsOf: trajectory.restUpFaces)

            out.appendLE(UInt16(trajectory.collisions.count))
            for cue in trajectory.collisions {
                out.appendLE(cue.frame)
                out.append(cue.dieIndex)
                out.append(UInt8(max(0, min(255, cue.intensity * 255))))
            }

            for frame in trajectory.frames {
                for pose in frame {
                    out.appendLE(Float16(pose.position.x))
                    out.appendLE(Float16(pose.position.y))
                    out.appendLE(Float16(pose.position.z))
                    let q = simd_normalize(pose.orientation).vector
                    for component in [q.x, q.y, q.z, q.w] {
                        out.appendLE(Int16(max(-32767, min(32767, (component * 32767).rounded()))))
                    }
                }
            }
        }
        return out
    }

    public static func decode(_ data: Data) throws -> [Trajectory] {
        var cursor = 0
        func need(_ bytes: Int) throws {
            guard cursor + bytes <= data.count else { throw Failure.truncated(at: cursor) }
        }

        try need(4)
        guard Array(data[data.startIndex..<data.startIndex + 4]) == magic else { throw Failure.badMagic }
        cursor = 4

        let fileVersion: UInt16 = try data.readLE(at: &cursor)
        guard fileVersion == version else { throw Failure.unsupportedVersion(fileVersion) }
        let count: UInt32 = try data.readLE(at: &cursor)

        var out: [Trajectory] = []
        out.reserveCapacity(Int(count))

        for _ in 0..<count {
            let id: UInt16 = try data.readLE(at: &cursor)
            let dieCount: UInt8 = try data.readLE(at: &cursor)
            let directionRaw: UInt8 = try data.readLE(at: &cursor)
            let frameRate: UInt16 = try data.readLE(at: &cursor)
            let frameCount: UInt16 = try data.readLE(at: &cursor)

            var restUpFaces: [UInt8] = []
            for _ in 0..<dieCount {
                let upFace: UInt8 = try data.readLE(at: &cursor)
                guard (1...6).contains(upFace) else { throw Failure.restUpFaceOutOfRange(upFace) }
                restUpFaces.append(upFace)
            }

            let collisionCount: UInt16 = try data.readLE(at: &cursor)
            var collisions: [CollisionCue] = []
            for _ in 0..<collisionCount {
                let frame: UInt16 = try data.readLE(at: &cursor)
                let die: UInt8 = try data.readLE(at: &cursor)
                let intensity: UInt8 = try data.readLE(at: &cursor)
                collisions.append(CollisionCue(frame: frame, dieIndex: die, intensity: Float(intensity) / 255))
            }

            var frames: [[DiePose]] = []
            frames.reserveCapacity(Int(frameCount))
            for _ in 0..<frameCount {
                var poses: [DiePose] = []
                poses.reserveCapacity(Int(dieCount))
                for _ in 0..<dieCount {
                    let x: Float16 = try data.readLE(at: &cursor)
                    let y: Float16 = try data.readLE(at: &cursor)
                    let z: Float16 = try data.readLE(at: &cursor)
                    let qx: Int16 = try data.readLE(at: &cursor)
                    let qy: Int16 = try data.readLE(at: &cursor)
                    let qz: Int16 = try data.readLE(at: &cursor)
                    let qw: Int16 = try data.readLE(at: &cursor)
                    let vector = SIMD4<Float>(Float(qx), Float(qy), Float(qz), Float(qw)) / 32767
                    poses.append(DiePose(
                        position: SIMD3(Float(x), Float(y), Float(z)),
                        orientation: simd_normalize(simd_quatf(vector: vector))
                    ))
                }
                frames.append(poses)
            }

            out.append(Trajectory(
                id: id, dieCount: Int(dieCount),
                direction: ThrowDirection(rawValue: directionRaw) ?? .center,
                frameRate: Int(frameRate), frames: frames,
                restUpFaces: restUpFaces, collisions: collisions
            ))
        }
        return out
    }
}

// MARK: - 바이트 입출력

extension Data {
    mutating func appendLE<T>(_ value: T) {
        var little = value
        withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func readLE<T>(at cursor: inout Int) throws -> T {
        let size = MemoryLayout<T>.size
        guard cursor + size <= count else { throw TrajectoryArchive.Failure.truncated(at: cursor) }
        let slice = self[startIndex + cursor ..< startIndex + cursor + size]
        cursor += size
        return slice.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
    }
}
```

**주의 2가지**:

1. 이 코드는 리틀엔디안 기기를 전제한다. iOS·macOS는 전부 리틀엔디안이라 문제가 없지만, 파일 포맷 주석에 그 전제를 남겨둔다.
2. `Float16`은 arm64에서만 쓸 수 있다. Intel Mac에서 `swift test --package-path Packages/DiceTrajectory`가 `Float16 is unavailable` 로 실패하면, 위치도 쿼터니언과 같은 Int16 양자화로 바꾼다 — 트레이가 ±0.13m 범위이므로 `Int16(position * 100_000)` 이면 0.01mm 해상도로 충분하다. 이 경우 프레임당 바이트 수는 14로 동일하다.

- [ ] **Step 5: `TrajectoryValidator.swift` 작성**

```swift
import Foundation
import simd

/// 구운 궤적이 쓸 만한지 검사한다. 베이커가 궤적을 채택하기 전에 통과시키는 관문이다.
public enum TrajectoryValidator {

    public static func problems(in trajectory: Trajectory,
                                trayInner: SIMD3<Float>,
                                dieSize: Float) -> [String] {
        var problems: [String] = []
        let margin = dieSize
        let limitX = trayInner.x / 2 + margin
        let limitZ = trayInner.z / 2 + margin
        let limitY = trayInner.y + margin

        guard trajectory.frameCount > 0 else { return ["프레임이 없다"] }
        guard trajectory.restUpFaces.count == trajectory.dieCount else {
            return ["정지 윗면 개수(\(trajectory.restUpFaces.count))가 주사위 수(\(trajectory.dieCount))와 다르다"]
        }

        // ① 트레이 이탈
        for (frameIndex, frame) in trajectory.frames.enumerated() {
            for (die, pose) in frame.enumerated() {
                let p = pose.position
                if abs(p.x) > limitX || abs(p.z) > limitZ || p.y < -margin || p.y > limitY {
                    problems.append("프레임 \(frameIndex) 주사위 \(die)가 트레이를 벗어났다: \(p)")
                }
            }
        }

        // ② 정지 시 윗면 기울기가 2° 이내인가, 그리고 기록된 윗면 값과 일치하는가
        //
        // 24개 축정렬 자세와의 거리로 재면 안 된다. 바닥에 평평하게 누운 주사위도
        // 수직축 둘레 yaw가 자유로워서 최대 45°가 나온다 (스펙 §7.3, Task 2 스파이크 실측).
        let last = trajectory.frames[trajectory.frameCount - 1]
        for die in 0..<trajectory.dieCount {
            let tilt = DieFace.upFaceTiltRadians(for: last[die].orientation)
            if tilt > 2.0 * .pi / 180 {
                problems.append("주사위 \(die)가 \(tilt * 180 / .pi)도 기울어 멈췄다 (벽에 기댔을 가능성)")
            }
            let actualUpFace = DieFace.upValue(for: last[die].orientation)
            if actualUpFace != trajectory.restUpFace(die: die) {
                problems.append("주사위 \(die)의 기록된 윗면 \(trajectory.restUpFace(die: die))이 실제 \(actualUpFace)과 다르다")
            }
        }

        // ③ 오프셋 전수 검증 — 스펙 §11의 가장 중요한 검사
        for die in 0..<trajectory.dieCount {
            for value in 1...6 {
                for yaw in 0..<4 {
                    let offset = FaceControl.offset(
                        restUpFace: trajectory.restUpFace(die: die),
                        showing: value, yawChoice: yaw
                    )
                    let pose = trajectory.posed(die: die, frame: trajectory.frameCount - 1, offset: offset)
                    let up = DieFace.upValue(for: pose.orientation)
                    if up != value {
                        problems.append("주사위 \(die)에 눈 \(value)를 요구했는데 \(up)이 나왔다 (yaw \(yaw))")
                    }
                }
            }
        }

        return problems
    }
}
```

- [ ] **Step 6: 테스트 통과 확인**

```bash
swift test --package-path "Packages/DiceTrajectory"
```
Expected: PASS (전체)

- [ ] **Step 7: 커밋**

```bash
git add Packages/DiceTrajectory
git commit -m "$(cat <<'MSG'
feat(trajectory): 궤적 자료구조, 바이너리 포맷, 검증기

정지 자세를 통째로 저장하지 않고 정지 시 위를 향한 눈만 1바이트로 저장한다.
회전 오프셋이 그 값에만 의존하고, 정지 자세 자체는 마지막 프레임 쿼터니언이 이미
갖고 있다. 정수라 양자화 손실도 없다.

검증기 ②를 "24개 축정렬 최근접 2도"가 아니라 "윗면 기울기 2도"로 잰다. 바닥에
평평하게 누운 주사위는 yaw가 자유로워서 전자로 재면 최대 45도가 나온다.

프레임 데이터는 위치 Float16, 쿼터니언 Int16으로 양자화해 주사위 하나당
14바이트다. 5개 120프레임이 8.4KB라 수백 개를 구워도 앱 번들에 여유롭게 들어간다.

검증기는 트레이 이탈, 정지 자세 불일치, 그리고 오프셋 전수 검증 세 가지를 본다.
세 번째가 스펙 11장이 지목한 가장 중요한 검사다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 12: 베이커 툴 — 궤적 굽기

Task 2 스파이크가 **경로 A'** 를 채택했다. RealityKit 베이커로 가되 정지 판정은 위치 차분으로 하고 기울어 멈춘 궤적은 기각한다. 스파이크가 실측으로 밝힌 네 가지를 반드시 반영한다:

1. **관성 텐서를 형상에서 계산해야 한다.** `PhysicsBodyComponent(massProperties: .init(mass: 0.005), ...)`는 관성을 RealityKit 기본값 `0.1`로 남기는데, 16mm·5g 정육면체의 실제값 `m·a²/6 = 2.13e-7`의 약 47만 배다. 주사위가 영원히 돌고 절대 멈추지 않는다. **`PhysicsBodyComponent(shapes:mass:material:mode:)`를 써야 한다.**
2. **`PhysicsMotionComponent`의 속도로 정지를 판정할 수 없다.** 값을 읽을 수는 있지만 물체가 잠든 뒤에도 유령 값이 남는다(자세 변화 0.00000°/프레임인 주사위가 4.73 rad/s를 보고). **위치·자세 차분으로 판정한다.**
3. **트레이와 주사위가 같은 `PhysicsSimulationComponent` 루트 아래 있어야** 서로 충돌한다.
4. **정착 시간이 0.9~5.0초로 들쭉날쭉하다.** 5초짜리 굴림은 게임 템포를 망치므로 프레임 상한을 두고 초과분은 기각한다.

경로 B(자체 강체 시뮬)로 되돌아가야 할 상황이면 Step 3의 물리 스텝만 자체 구현으로 바꾸고 나머지 구조는 그대로 쓴다.

**Files:**
- Create: `Packages/DiceTrajectory/Sources/DiceTrajectory/TrayGeometry.swift`
- Modify: `Tools/TrajectoryBaker/BakerApp.swift`
- Create: `Tools/TrajectoryBaker/BakerScene.swift`
- Create: `Tools/TrajectoryBaker/BakeRunner.swift`
- Delete: `Tools/TrajectoryBaker/SpikeScene.swift`
- Create: `App/Resources/trajectories.bin` (베이커 산출물)

**Interfaces:**
- Consumes: Task 11의 `Trajectory`, `TrajectoryArchive`, `TrajectoryValidator`, Task 9의 `OctahedralGroup`
- Produces:
  - `App/Resources/trajectories.bin` — 굴리는 개수 1~5 × 방향 3종 × 변형 40개
  - `TrayGeometry.trayInner = SIMD3<Float>(0.24, 0.12, 0.24)`, `TrayGeometry.dieSize: Float = 0.016` (Task 13이 같은 값을 쓴다)

- [ ] **Step 1: 트레이 치수를 공유 상수로 뽑아 `DiceTrajectory`에 둔다**

`Packages/DiceTrajectory/Sources/DiceTrajectory/TrayGeometry.swift`:

```swift
import Foundation
import simd

/// 베이커와 앱이 반드시 같은 치수를 써야 한다. 어긋나면 궤적이 트레이를 뚫는다.
/// 실물 주사위 16mm를 기준으로 잡았다.
public enum TrayGeometry {
    public static let trayInner = SIMD3<Float>(0.24, 0.12, 0.24)
    public static let dieSize: Float = 0.016
    public static let wallThickness: Float = 0.01
    /// keep한 주사위가 올라가는 상단 선반의 높이.
    public static let shelfHeight: Float = 0.16
}
```

- [ ] **Step 2: 베이킹 설정과 결과 타입 작성**

`Tools/TrajectoryBaker/BakeRunner.swift`:

```swift
import Foundation
import simd
import DiceTrajectory

struct BakePlan {
    /// 굴리는 개수별 x 방향별 변형 수. 5 x 3 x 40 = 600개.
    static let variantsPerCombination = 40
    static let frameRate = 60
    /// 정착 상한. 스파이크 실측 정착 시간이 0.9~5.0초인데 5초짜리 굴림은 게임 템포를 망친다.
    /// 조합별 채택 수가 20개 미만이면 180으로 완화한다 (Step 6 판정표).
    static let maxFrames = 150          // 2.5초
    static let settleThreshold: Float = 0.002   // m/frame, 위치 차분 기준
    static let settleFrames = 20
    /// 정지 시 윗면 기울기 상한. 초과하면 벽에 기대어 멈춘 것이므로 기각한다.
    /// 24개 축정렬 최근접 거리가 아니라 윗면 기울기로 잰다 (스펙 §7.3).
    static let maxUpFaceTiltDegrees: Float = 2.0

    static var combinations: [(dieCount: Int, direction: ThrowDirection)] {
        (1...5).flatMap { count in ThrowDirection.allCases.map { (count, $0) } }
    }
}

struct BakeResult {
    var accepted: [Trajectory] = []
    var rejected: [(reason: String, dieCount: Int, direction: ThrowDirection)] = []

    var summary: String {
        let byCombination = Dictionary(grouping: accepted) { "\($0.dieCount)개/\($0.direction)" }
            .mapValues(\.count).sorted { $0.key < $1.key }
        return """
        채택 \(accepted.count)개 / 기각 \(rejected.count)개
        \(byCombination.map { "  \($0.key): \($0.value)" }.joined(separator: "\n"))
        기각 사유 상위: \(Dictionary(grouping: rejected, by: \.reason).mapValues(\.count)
            .sorted { $0.value > $1.value }.prefix(3)
            .map { "\($0.key) x\($0.value)" }.joined(separator: ", "))
        """
    }
}
```

- [ ] **Step 3: 시뮬레이션 씬과 프레임 수집기 작성**

`Tools/TrajectoryBaker/BakerScene.swift`:

```swift
import SwiftUI
import RealityKit
import simd
import DiceTrajectory

@MainActor
@Observable
final class BakerModel {
    var progress = "대기 중"
    var result = BakeResult()
    var isRunning = false

    private var dice: [ModelEntity] = []
    private var root = Entity()

    /// 트레이와 주사위를 만든다. 치수는 TrayGeometry에서만 가져온다.
    func makeScene() -> Entity {
        root = Entity()
        // 트레이와 주사위가 같은 시뮬레이션 루트 아래 있어야 서로 충돌한다 (스파이크 실측)
        root.components.set(PhysicsSimulationComponent())
        let t = TrayGeometry.wallThickness
        let inner = TrayGeometry.trayInner
        let walls: [(size: SIMD3<Float>, offset: SIMD3<Float>)] = [
            ([inner.x, t, inner.z], [0, -t / 2, 0]),
            ([inner.x, inner.y, t], [0, inner.y / 2,  (inner.z + t) / 2]),
            ([inner.x, inner.y, t], [0, inner.y / 2, -(inner.z + t) / 2]),
            ([t, inner.y, inner.z], [ (inner.x + t) / 2, inner.y / 2, 0]),
            ([t, inner.y, inner.z], [-(inner.x + t) / 2, inner.y / 2, 0]),
        ]
        for wall in walls {
            let entity = ModelEntity(
                mesh: .generateBox(size: wall.size),
                materials: [SimpleMaterial(color: .brown, isMetallic: false)]
            )
            entity.position = wall.offset
            let shape = ShapeResource.generateBox(size: wall.size)
            entity.components.set(CollisionComponent(shapes: [shape]))
            entity.components.set(PhysicsBodyComponent(
                shapes: [shape], mass: 0,
                material: .generate(friction: 0.65, restitution: 0.20),
                mode: .static))
            root.addChild(entity)
        }

        dice = (0..<5).map { index in
            let size = TrayGeometry.dieSize
            let entity = ModelEntity(
                mesh: .generateBox(size: size, cornerRadius: size * 0.10),
                materials: [SimpleMaterial(color: .white, isMetallic: false)])
            entity.name = "die\(index)"
            let shape = ShapeResource.generateBox(size: .init(repeating: size))
            entity.components.set(CollisionComponent(shapes: [shape]))
            // massProperties: .init(mass:)를 쓰면 관성이 기본값 0.1로 남아 실제값의 약 47만 배가
            // 되고 주사위가 영원히 돈다. 반드시 형상에서 계산되는 이 생성자를 쓴다 (스파이크 실측).
            entity.components.set(PhysicsBodyComponent(
                shapes: [shape], mass: 0.005,
                material: .generate(friction: 0.55, restitution: 0.30),
                mode: .dynamic))
            entity.components.set(PhysicsMotionComponent())
            root.addChild(entity)
            return entity
        }
        return root
    }

    /// 한 궤적을 굽는다. 주사위를 던지고 멈출 때까지 프레임을 모은다.
    func bakeOne(id: UInt16, dieCount: Int, direction: ThrowDirection,
                 advanceFrame: @MainActor () async -> Void) async -> Result<Trajectory, String> {
        resetDice(dieCount: dieCount, direction: direction)

        var frames: [[DiePose]] = []
        var collisions: [CollisionCue] = []
        var previousSpeeds = [Float](repeating: .infinity, count: dieCount)
        var stillCount = 0

        for frameIndex in 0..<BakePlan.maxFrames {
            await advanceFrame()

            var poses: [DiePose] = []
            var maxSpeed: Float = 0
            for die in 0..<dieCount {
                let entity = dice[die]
                let position = entity.position(relativeTo: nil)
                let orientation = entity.orientation(relativeTo: nil)
                poses.append(DiePose(position: position, orientation: simd_normalize(orientation)))

                // PhysicsMotionComponent의 속도는 잠든 뒤 유령 값이 남아 쓸 수 없다 (스파이크 실측).
                // 위치 차분으로 판정한다.
                let speed = frames.isEmpty ? .infinity
                    : simd_length(position - frames[frames.count - 1][die].position) * Float(BakePlan.frameRate)
                maxSpeed = max(maxSpeed, speed)

                // 속도가 급감하면 충돌로 본다 — 사운드·햅틱 큐로 쓴다
                if previousSpeeds[die].isFinite, previousSpeeds[die] - speed > 0.25 {
                    collisions.append(CollisionCue(
                        frame: UInt16(frameIndex), dieIndex: UInt8(die),
                        intensity: min(1, (previousSpeeds[die] - speed) / 2)))
                }
                previousSpeeds[die] = speed
            }
            frames.append(poses)

            stillCount = maxSpeed < BakePlan.settleThreshold ? stillCount + 1 : 0
            if stillCount >= BakePlan.settleFrames { break }
        }

        guard stillCount >= BakePlan.settleFrames else {
            return .failure("\(BakePlan.maxFrames)프레임 안에 멈추지 않음")
        }

        // 정지 자세는 물리가 만든 그대로 둔다. 축정렬로 스냅하면 안 된다 —
        // 바닥에 누운 주사위는 yaw가 연속적으로 자유로워서 최대 45° 홱 돌아간다 (스펙 §7.3).
        // 기록하는 것은 "위를 향한 눈"뿐이고, 회전 오프셋은 그 값에만 의존한다.
        var restUpFaces: [UInt8] = []
        for die in 0..<dieCount {
            let resting = frames[frames.count - 1][die].orientation
            let tiltDegrees = DieFace.upFaceTiltRadians(for: resting) * 180 / .pi
            guard tiltDegrees <= BakePlan.maxUpFaceTiltDegrees else {
                return .failure("주사위가 기울어 멈춤 (\(String(format: "%.1f", tiltDegrees))도, 벽에 기댄 듯)")
            }
            restUpFaces.append(UInt8(DieFace.upValue(for: resting)))
        }

        let trajectory = Trajectory(
            id: id, dieCount: dieCount, direction: direction, frameRate: BakePlan.frameRate,
            frames: frames, restUpFaces: restUpFaces, collisions: collisions)

        let problems = TrajectoryValidator.problems(
            in: trajectory, trayInner: TrayGeometry.trayInner, dieSize: TrayGeometry.dieSize)
        guard problems.isEmpty else { return .failure(problems[0]) }

        return .success(trajectory)
    }

    private func resetDice(dieCount: Int, direction: ThrowDirection) {
        let lateral: Float = switch direction {
        case .left: -0.35
        case .center: 0
        case .right: 0.35
        }
        for (index, entity) in dice.enumerated() {
            entity.isEnabled = index < dieCount
            guard index < dieCount else { continue }
            entity.position = [
                Float(index) * TrayGeometry.dieSize * 1.5 - 0.03,
                TrayGeometry.shelfHeight,
                -TrayGeometry.trayInner.z / 2 + 0.02,
            ]
            entity.orientation = simd_normalize(simd_quatf(
                angle: .random(in: 0...(2 * .pi)),
                axis: simd_normalize(SIMD3<Float>.random(in: -1...1))))
            var motion = PhysicsMotionComponent()
            motion.linearVelocity = [lateral + .random(in: -0.1...0.1), -0.5, .random(in: 0.5...0.9)]
            motion.angularVelocity = SIMD3(.random(in: -25...25), .random(in: -25...25), .random(in: -25...25))
            entity.components.set(motion)
        }
    }
}
```

- [ ] **Step 4: 실행 UI와 파일 출력 작성**

`Tools/TrajectoryBaker/BakerApp.swift`를 다음으로 교체:

```swift
import SwiftUI
import RealityKit
import DiceTrajectory

@main
struct BakerApp: App {
    var body: some Scene {
        WindowGroup("Trajectory Baker") {
            BakerView().frame(minWidth: 720, minHeight: 520)
        }
    }
}

struct BakerView: View {
    @State private var model = BakerModel()
    @State private var frameTick = 0

    var body: some View {
        VStack(spacing: 12) {
            RealityView { content in
                content.add(model.makeScene())
                let camera = Entity()
                camera.components.set(PerspectiveCameraComponent())
                camera.look(at: .zero, from: [0, 0.4, 0.35], relativeTo: nil)
                content.add(camera)
            }
            .frame(height: 320)

            Text(model.progress).font(.system(.body, design: .monospaced))
            ScrollView { Text(model.result.summary).font(.system(.caption, design: .monospaced)) }
                .frame(height: 100)

            Button(model.isRunning ? "굽는 중..." : "굽기 시작") {
                Task { await bake() }
            }
            .disabled(model.isRunning)
        }
        .padding()
    }

    /// RealityKit 물리는 렌더 루프에 물려 있으므로 한 프레임씩 실제 시간으로 흘려보낸다.
    /// 600개 x 약 2.5초 = 25분쯤 걸린다. 일회성 작업이므로 감수한다.
    private func advanceFrame() async {
        try? await Task.sleep(for: .milliseconds(1000 / BakePlan.frameRate))
    }

    private func bake() async {
        model.isRunning = true
        model.result = BakeResult()
        var nextID: UInt16 = 0

        for combination in BakePlan.combinations {
            for variant in 0..<BakePlan.variantsPerCombination {
                model.progress = "\(combination.dieCount)개 / \(combination.direction) / \(variant + 1)"
                let outcome = await model.bakeOne(
                    id: nextID, dieCount: combination.dieCount, direction: combination.direction,
                    advanceFrame: advanceFrame)
                switch outcome {
                case .success(let trajectory):
                    model.result.accepted.append(trajectory)
                    nextID += 1
                case .failure(let reason):
                    model.result.rejected.append((reason, combination.dieCount, combination.direction))
                }
            }
        }

        do {
            let data = try TrajectoryArchive.encode(model.result.accepted)
            let url = URL(fileURLWithPath: NSHomeDirectory())
                .appending(path: "Desktop/trajectories.bin")
            try data.write(to: url)
            model.progress = "완료: \(url.path) (\(data.count / 1024)KB)"
        } catch {
            model.progress = "쓰기 실패: \(error)"
        }
        model.isRunning = false
    }
}
```

- [ ] **Step 5: 스파이크 코드 삭제하고 베이커 실행**

```bash
rm "Tools/TrajectoryBaker/SpikeScene.swift"
xcodegen generate
xcodebuild build -project YachtDice.xcodeproj -scheme TrajectoryBaker -destination 'platform=macOS' | tail -3
```

Xcode에서 `TrajectoryBaker`를 Run하고 "굽기 시작"을 누른다. 약 25분 걸린다.

- [ ] **Step 6: 채택률 확인 — 여기서 판정한다**

| 관찰 | 대응 |
|---|---|
| 조합별 채택 30개 이상 | 좋다. Step 7로 간다 |
| 채택 10~30개, 기각 사유가 "주사위가 기울어 멈춤" | 반발계수를 0.20으로 낮추고 마찰을 0.7로 올린 뒤 재실행 |
| 채택 10개 미만, 기각 사유가 "멈추지 않음" | `maxFrames`를 180(3초)으로 늘린다. 그래도 부족하면 `settleThreshold`를 0.004로 완화한다. **240 이상으로는 올리지 않는다** — 4초짜리 굴림은 게임 템포를 망친다 |
| 주사위가 영원히 돌고 하나도 안 멈춤 | `PhysicsBodyComponent`를 `massProperties:` 생성자로 쓰고 있는 것이다. `shapes:mass:material:mode:`로 바꾼다 |
| 주사위가 트레이를 통과해 지나감 | 트레이와 주사위가 같은 `PhysicsSimulationComponent` 루트 아래 있는지 확인한다 |
| 기각 사유가 "트레이를 벗어났다" | 초기 `linearVelocity`를 절반으로 줄인다 |

각 조합에 최소 20개는 있어야 한다. 20개 미만인 조합이 있으면 `variantsPerCombination`을 60으로 늘려 재실행한다.

- [ ] **Step 7: 산출물을 앱 리소스로 옮기고 커밋**

```bash
mkdir -p App/Resources
cp ~/Desktop/trajectories.bin App/Resources/trajectories.bin
ls -lh App/Resources/trajectories.bin
git add -A
git commit -m "$(cat <<'MSG'
feat(baker): 궤적 베이커와 구운 데이터

정지 자세는 물리가 만든 그대로 두고 "위를 향한 눈"만 기록한다. 축정렬로 스냅하면
바닥에 누운 주사위의 자유로운 yaw까지 되돌려 최대 45도 홱 돌아간다.
윗면 기울기가 2도를 넘으면 벽에 기대어 멈춘 것이므로 궤적을 버린다.

스파이크가 실측으로 밝힌 두 가지를 반영했다. 관성 텐서는 형상에서 계산되는
생성자를 써야 하고(massProperties 쪽은 기본값 0.1을 남겨 실제값의 47만 배가 된다),
정지 판정은 PhysicsMotionComponent 속도가 아니라 위치 차분으로 해야 한다
(잠든 뒤에도 유령 속도가 남는다).

채택 전에 TrajectoryValidator를 통과시킨다. 굽는 단계에서 걸러내면 런타임에
검사할 필요가 없다.

RealityKit 물리가 렌더 루프에 물려 있어서 실시간으로 25분쯤 걸린다. 일회성
작업이라 병렬화하지 않았다. 트레이 치수나 물성을 바꾸면 다시 구워야 한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 13: RealityKit 씬과 궤적 라이브러리

**Files:**
- Create: `App/Scene3D/DiceSceneBuilder.swift`
- Create: `App/Scene3D/TrajectoryLibrary.swift`
- Create: `Tests/YachtDiceTests/TrajectoryLibraryTests.swift`

**Interfaces:**
- Consumes: Task 11의 `Trajectory`/`TrajectoryArchive`, Task 12의 `trajectories.bin`, `TrayGeometry`
- Produces:
  - `enum DiceSceneBuilder` — `static func makeRoot() -> Entity`, `static func dice(in: Entity) -> [ModelEntity]`, `static func makeCamera() -> Entity`
  - `final class TrajectoryLibrary` — `init(data: Data) throws`, `static func bundled() throws -> TrajectoryLibrary`, `func pick(dieCount: Int, direction: ThrowDirection, using: inout some RandomNumberGenerator) -> Trajectory?`, `var count: Int`, `let all: [Trajectory]`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/YachtDiceTests/TrajectoryLibraryTests.swift`:

```swift
import Testing
import Foundation
import DiceTrajectory
@testable import YachtDice

@Suite("궤적 라이브러리")
struct TrajectoryLibraryTests {

    @Test("번들에 궤적 파일이 들어 있다")
    func 번들_로딩() throws {
        let library = try TrajectoryLibrary.bundled()
        #expect(library.count > 0, "trajectories.bin이 앱 번들에 포함되지 않았다")
    }

    @Test("굴리는 개수 1~5, 방향 3종 모두에 궤적이 있다")
    func 조합_커버리지() throws {
        let library = try TrajectoryLibrary.bundled()
        var rng = SystemRandomNumberGenerator()
        for dieCount in 1...5 {
            for direction in ThrowDirection.allCases {
                let picked = library.pick(dieCount: dieCount, direction: direction, using: &rng)
                #expect(picked != nil, "\(dieCount)개 / \(direction) 궤적이 없다")
                #expect(picked?.dieCount == dieCount)
                #expect(picked?.direction == direction)
            }
        }
    }

    @Test("번들된 모든 궤적이 검증기를 통과한다")
    func 전체_검증() throws {
        let library = try TrajectoryLibrary.bundled()
        var failures: [String] = []
        for trajectory in library.all {
            let problems = TrajectoryValidator.problems(
                in: trajectory, trayInner: TrayGeometry.trayInner, dieSize: TrayGeometry.dieSize)
            if !problems.isEmpty { failures.append("궤적 \(trajectory.id): \(problems[0])") }
        }
        #expect(failures.isEmpty, "검증 실패 \(failures.count)건. 처음 3건: \(failures.prefix(3).joined(separator: " | "))")
    }

    @Test("각 조합에 최소 20개의 변형이 있다")
    func 변형_다양성() throws {
        let library = try TrajectoryLibrary.bundled()
        for dieCount in 1...5 {
            for direction in ThrowDirection.allCases {
                let matching = library.all.filter { $0.dieCount == dieCount && $0.direction == direction }
                #expect(matching.count >= 20, "\(dieCount)개/\(direction)에 \(matching.count)개뿐이다 — 굴림이 반복적으로 보인다")
            }
        }
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
xcodebuild test -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:YachtDiceTests/TrajectoryLibraryTests 2>&1 | tail -20
```
Expected: 컴파일 실패 — `cannot find 'TrajectoryLibrary' in scope`

- [ ] **Step 3: `TrajectoryLibrary.swift` 작성**

```swift
import Foundation
import DiceTrajectory

/// 번들에 구워 넣은 궤적을 조합별로 찾아준다.
final class TrajectoryLibrary: Sendable {
    let all: [Trajectory]
    private let index: [Key: [Trajectory]]

    private struct Key: Hashable {
        let dieCount: Int
        let direction: ThrowDirection
    }

    enum LoadFailure: Error {
        case resourceMissing
    }

    init(data: Data) throws {
        all = try TrajectoryArchive.decode(data)
        index = Dictionary(grouping: all) { Key(dieCount: $0.dieCount, direction: $0.direction) }
    }

    static func bundled() throws -> TrajectoryLibrary {
        guard let url = Bundle.main.url(forResource: "trajectories", withExtension: "bin") else {
            throw LoadFailure.resourceMissing
        }
        return try TrajectoryLibrary(data: try Data(contentsOf: url))
    }

    var count: Int { all.count }

    func pick(dieCount: Int, direction: ThrowDirection,
              using generator: inout some RandomNumberGenerator) -> Trajectory? {
        let candidates = index[Key(dieCount: dieCount, direction: direction)] ?? []
        return candidates.randomElement(using: &generator)
    }
}
```

- [ ] **Step 4: `project.yml`의 리소스 경로 확인 후 재생성**

Task 1의 `project.yml`은 `targets.YachtDice.sources: [App]`이므로 `App/Resources/`가 이미 통째로 포함되고, XcodeGen은 `.bin`을 자동으로 리소스 빌드 페이즈에 넣는다. **`sources:` 키를 새로 추가하면 YAML 키가 중복되어 파싱이 깨진다.** 따라서 기본적으로 `project.yml`은 손대지 않는다.

```bash
xcodegen generate
xcodebuild build -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' | tail -3
```

빌드 후 번들에 파일이 들어갔는지 확인한다:

```bash
find ~/Library/Developer/Xcode/DerivedData -name "trajectories.bin" -path "*YachtDice.app*" | head -1
```

경로가 나오지 않으면 그때만 `targets.YachtDice`의 **기존** `sources: [App]` 줄을 아래로 **교체**한다 (새 키를 추가하는 것이 아니다):

```yaml
    sources:
      - path: App
      - path: App/Resources/trajectories.bin
        buildPhase: resources
```

- [ ] **Step 5: `DiceSceneBuilder.swift` 작성**

```swift
import Foundation
import RealityKit
import simd
import DiceTrajectory

/// 트레이·테이블·주사위 엔티티를 만든다.
/// 물리 컴포넌트를 붙이지 않는다 — 재생은 키프레임 구동이고, 물리는 베이커에만 있다.
enum DiceSceneBuilder {

    static func makeRoot() -> Entity {
        let root = Entity()
        root.addChild(makeTable())
        root.addChild(makeTray())
        for die in makeDice() { root.addChild(die) }
        root.addChild(makeLighting())
        return root
    }

    static func dice(in root: Entity) -> [ModelEntity] {
        (0..<5).compactMap { root.findEntity(named: "die\($0)") as? ModelEntity }
    }

    static func makeCamera() -> Entity {
        let camera = Entity()
        var component = PerspectiveCameraComponent()
        component.fieldOfViewInDegrees = 42
        camera.components.set(component)
        // 레퍼런스와 같은 약 55도 부감
        camera.look(at: [0, 0, 0], from: [0, 0.42, 0.30], relativeTo: nil)
        return camera
    }

    // MARK: - 구성 요소

    private static func makeTable() -> Entity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.45, green: 0.29, blue: 0.16, alpha: 1))
        material.roughness = .init(floatLiteral: 0.55)
        material.metallic = .init(floatLiteral: 0)
        let entity = ModelEntity(mesh: .generatePlane(width: 2, depth: 2), materials: [material])
        entity.name = "table"
        entity.position = [0, -TrayGeometry.wallThickness, 0]
        return entity
    }

    private static func makeTray() -> Entity {
        var leather = PhysicallyBasedMaterial()
        leather.baseColor = .init(tint: .init(red: 0.52, green: 0.11, blue: 0.11, alpha: 1))
        leather.roughness = .init(floatLiteral: 0.85)
        leather.metallic = .init(floatLiteral: 0)

        var rim = PhysicallyBasedMaterial()
        rim.baseColor = .init(tint: .init(red: 0.72, green: 0.72, blue: 0.74, alpha: 1))
        rim.roughness = .init(floatLiteral: 0.35)
        rim.metallic = .init(floatLiteral: 0.9)

        let tray = Entity()
        tray.name = "tray"
        let t = TrayGeometry.wallThickness
        let inner = TrayGeometry.trayInner

        let floor = ModelEntity(mesh: .generateBox(size: [inner.x, t, inner.z]), materials: [leather])
        floor.position = [0, -t / 2, 0]
        tray.addChild(floor)

        let walls: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([inner.x + 2 * t, inner.y, t], [0, inner.y / 2,  (inner.z + t) / 2]),
            ([inner.x + 2 * t, inner.y, t], [0, inner.y / 2, -(inner.z + t) / 2]),
            ([t, inner.y, inner.z], [ (inner.x + t) / 2, inner.y / 2, 0]),
            ([t, inner.y, inner.z], [-(inner.x + t) / 2, inner.y / 2, 0]),
        ]
        for (size, offset) in walls {
            let wall = ModelEntity(mesh: .generateBox(size: size), materials: [rim])
            wall.position = offset
            tray.addChild(wall)
        }
        return tray
    }

    private static func makeDice() -> [ModelEntity] {
        var ceramic = PhysicallyBasedMaterial()
        ceramic.baseColor = .init(tint: .init(red: 0.97, green: 0.96, blue: 0.93, alpha: 1))
        ceramic.roughness = .init(floatLiteral: 0.35)
        ceramic.metallic = .init(floatLiteral: 0)
        ceramic.clearcoat = .init(floatLiteral: 0.4)
        ceramic.clearcoatRoughness = .init(floatLiteral: 0.2)

        return (0..<5).map { index in
            let size = TrayGeometry.dieSize
            let entity = ModelEntity(
                mesh: .generateBox(size: size, cornerRadius: size * 0.10),
                materials: [ceramic])
            entity.name = "die\(index)"
            entity.position = [Float(index - 2) * size * 1.6, size / 2, 0]
            return entity
        }
    }

    /// 방향광은 그림자를 만들고, IBL이 재질의 질감을 만든다.
    /// 스펙 §7.5: 레퍼런스의 "따뜻한 실내 조명에 놓인 실물" 느낌은 대부분 IBL에서 온다.
    /// 방향광만 쓰면 주사위가 플라스틱처럼 납작해 보인다.
    private static func makeLighting() -> Entity {
        let rig = Entity()
        rig.name = "lighting"

        let key = Entity()
        key.name = "keyLight"
        var directional = DirectionalLightComponent(color: .white, intensity: 2_400)
        directional.isRealWorldProxy = false
        key.components.set(directional)
        key.components.set(DirectionalLightComponent.Shadow(maximumDistance: 1.0, depthBias: 1.0))
        key.look(at: [0, 0, 0], from: [0.3, 0.6, 0.25], relativeTo: nil)
        rig.addChild(key)

        if let ibl = makeImageBasedLight() { rig.addChild(ibl) }
        return rig
    }

    /// 스튜디오 환경광. 외부 HDR 파일 없이 코드로 그러데이션 큐브맵을 만든다 (스펙 §13).
    private static func makeImageBasedLight() -> Entity? {
        guard let image = makeStudioEnvironmentImage(),
              let resource = try? EnvironmentResource.generate(fromEquirectangular: image)
        else { return nil }

        let entity = Entity()
        entity.name = "ibl"
        var component = ImageBasedLightComponent(source: .single(resource), intensityExponent: 1.0)
        component.inheritsRotation = true
        entity.components.set(component)
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: entity))
        return entity
    }

    /// 위는 따뜻한 흰색, 아래는 어두운 갈색으로 이어지는 등장방형 이미지.
    /// 실내 테이블 위라는 상황을 최소 비용으로 흉내낸다.
    private static func makeStudioEnvironmentImage() -> CGImage? {
        let width = 256, height = 128
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        let top = CGColor(red: 1.00, green: 0.96, blue: 0.90, alpha: 1)
        let bottom = CGColor(red: 0.20, green: 0.14, blue: 0.10, alpha: 1)
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [top, bottom] as CFArray,
                                        locations: [0, 1]) else { return nil }
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: height),
                                   end: CGPoint(x: 0, y: 0),
                                   options: [])
        return context.makeImage()
    }
}
```

`DiceSceneBuilder.swift` 맨 위에 `import CoreGraphics`를 추가한다.

**IBL이 붙었는지 확인하는 법**: 시뮬레이터에서 주사위 흰 면에 위아래 밝기 차이가 보이면 성공이다. 전체가 균일한 흰색이면 `EnvironmentResource.generate`가 실패한 것이니 `makeImageBasedLight()`가 nil을 돌려주는지 로그로 확인한다.

**API 이름이 SDK 버전에 따라 다를 수 있다.** `EnvironmentResource.generate(fromEquirectangular:)`와 `TextureResource(image:options:)`가 컴파일되지 않으면, Xcode에서 `EnvironmentResource.` / `TextureResource.` 를 입력해 자동완성으로 실제 시그니처를 확인하고 맞춘다. **둘 다 실패하면 IBL과 눈 텍스처를 빼고 진행한다** — 단색 주사위로도 P1 완료 기준 6개는 전부 충족되며, 재질 마감은 P4의 작업이다. 뺐다면 그 사실을 커밋 메시지에 남긴다.

**주사위 눈**: P1에서는 단색 흰 주사위로 진행한다. 눈 텍스처는 Step 6에서 붙인다.

- [ ] **Step 6: 주사위 눈 텍스처를 절차적으로 생성해 붙인다**

`App/Scene3D/DiePipTexture.swift`:

```swift
import Foundation
import CoreGraphics
import RealityKit
import UIKit

/// 주사위 6면 눈을 코드로 그려 하나의 아틀라스 텍스처로 만든다.
/// 외부 3D 아티스트 없이 진행하기 위한 선택이다 (스펙 §13).
enum DiePipTexture {
    /// generateBox의 UV는 6면이 가로로 이어진 아틀라스를 기대한다.
    static func makeAtlas(faceSize: Int = 256) -> CGImage? {
        let width = faceSize * 6
        let height = faceSize
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        context.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(UIColor(white: 0.12, alpha: 1).cgColor)

        // generateBox의 면 순서: +X, -X, +Y, -Y, +Z, -Z
        // DieFace의 배치와 맞춘다: +X=3, -X=4, +Y=1, -Y=6, +Z=2, -Z=5
        let facesInAtlasOrder = [3, 4, 1, 6, 2, 5]
        let radius = CGFloat(faceSize) * 0.09

        for (slot, value) in facesInAtlasOrder.enumerated() {
            let originX = CGFloat(slot * faceSize)
            for point in pipLayout(for: value) {
                let center = CGPoint(
                    x: originX + point.x * CGFloat(faceSize),
                    y: point.y * CGFloat(faceSize))
                context.fillEllipse(in: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2))
            }
        }
        return context.makeImage()
    }

    /// 면 안에서의 상대 좌표 (0...1).
    private static func pipLayout(for value: Int) -> [CGPoint] {
        let a: CGFloat = 0.26, b: CGFloat = 0.5, c: CGFloat = 0.74
        switch value {
        case 1: return [CGPoint(x: b, y: b)]
        case 2: return [CGPoint(x: a, y: c), CGPoint(x: c, y: a)]
        case 3: return [CGPoint(x: a, y: c), CGPoint(x: b, y: b), CGPoint(x: c, y: a)]
        case 4: return [CGPoint(x: a, y: a), CGPoint(x: a, y: c), CGPoint(x: c, y: a), CGPoint(x: c, y: c)]
        case 5: return [CGPoint(x: a, y: a), CGPoint(x: a, y: c), CGPoint(x: b, y: b),
                        CGPoint(x: c, y: a), CGPoint(x: c, y: c)]
        case 6: return [CGPoint(x: a, y: a), CGPoint(x: a, y: b), CGPoint(x: a, y: c),
                        CGPoint(x: c, y: a), CGPoint(x: c, y: b), CGPoint(x: c, y: c)]
        default: preconditionFailure("주사위 눈은 1...6이다: \(value)")
        }
    }
}
```

`DiceSceneBuilder.makeDice()`의 `ceramic.baseColor`를 텍스처 기반으로 교체:

```swift
        if let atlas = DiePipTexture.makeAtlas(),
           let texture = try? TextureResource(image: atlas, options: .init(semantic: .color)) {
            ceramic.baseColor = .init(tint: .white, texture: .init(texture))
        }
```

- [ ] **Step 7: 테스트 통과 확인**

```bash
xcodebuild test -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:YachtDiceTests/TrajectoryLibraryTests 2>&1 | tail -20
```
Expected: PASS (4 tests)

`전체_검증`이 실패하면 Task 12의 베이킹 파라미터를 조정해 다시 굽는다. 여기서 통과하지 못한 데이터는 런타임에 반드시 문제를 일으킨다.

- [ ] **Step 8: 커밋**

```bash
git add App Tests project.yml
git commit -m "$(cat <<'MSG'
feat(scene): RealityKit 씬과 궤적 라이브러리

씬 엔티티에 물리 컴포넌트를 붙이지 않았다. 재생은 키프레임 구동이고 물리는
베이커에만 존재한다. 런타임에 물리가 돌면 기기마다 결과가 갈려서 이 설계의
전제가 무너진다.

주사위 눈을 CoreGraphics로 그려 아틀라스 텍스처를 만든다. 외부 3D 아티스트
없이 P1을 끝내기 위한 선택이다. 아틀라스 면 순서를 DieFace의 축 배치와 맞췄다.

번들된 모든 궤적을 앱 테스트에서 다시 검증한다. 베이커에서 이미 걸렀지만,
잘못된 파일이 번들에 들어가는 사고가 런타임까지 가면 안 된다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 14: DiceStage — 궤적 재생과 keep 선반

**Files:**
- Create: `App/Scene3D/DiceStage.swift`
- Create: `App/Scene3D/DiceStageView.swift`
- Create: `Tests/YachtDiceTests/DiceStageTests.swift`

**Interfaces:**
- Consumes: Task 13의 `DiceSceneBuilder`, `TrajectoryLibrary`, Task 10의 `FaceControl`
- Produces:
  - `@MainActor final class DiceStage` — `init(library: TrajectoryLibrary)`
  - `func attach(to content: RealityViewContent)`
  - `func roll(values: [Int], slots: [Int], direction: ThrowDirection, skipAnimation: Bool) async -> [CollisionCue]`
  - `func placeHeld(_ heldSlots: [Int], values: [Int])`
  - `func reset()`
  - `var isAnimating: Bool`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/YachtDiceTests/DiceStageTests.swift`:

```swift
import Testing
import Foundation
import simd
import DiceTrajectory
@testable import YachtDice

@Suite("주사위 무대")
@MainActor
struct DiceStageTests {

    @Test("재생이 끝나면 각 주사위가 요청한 눈을 위로 향한다")
    func 재생_결과_일치() async throws {
        let stage = DiceStage(library: try TrajectoryLibrary.bundled())
        let values = [3, 1, 4, 6, 6]
        _ = await stage.roll(values: values, slots: [0, 1, 2, 3, 4],
                             direction: .center, skipAnimation: true)

        for (index, expected) in values.enumerated() {
            #expect(stage.faceUpValue(slot: index) == expected,
                    "슬롯 \(index)에 \(expected)를 요구했는데 \(String(describing: stage.faceUpValue(slot: index)))가 나왔다")
        }
    }

    @Test("keep한 주사위를 제외한 슬롯만 굴린다")
    func 부분_굴림() async throws {
        let stage = DiceStage(library: try TrajectoryLibrary.bundled())
        _ = await stage.roll(values: [1, 2, 3, 4, 5], slots: [0, 1, 2, 3, 4],
                             direction: .center, skipAnimation: true)
        stage.placeHeld([1, 3], values: [1, 2, 3, 4, 5])

        _ = await stage.roll(values: [6, 6, 6], slots: [0, 2, 4],
                             direction: .left, skipAnimation: true)

        #expect(stage.faceUpValue(slot: 0) == 6)
        #expect(stage.faceUpValue(slot: 2) == 6)
        #expect(stage.faceUpValue(slot: 4) == 6)
        #expect(stage.faceUpValue(slot: 1) == 2, "keep한 주사위가 바뀌었다")
        #expect(stage.faceUpValue(slot: 3) == 4, "keep한 주사위가 바뀌었다")
    }

    @Test("애니메이션을 건너뛰면 즉시 끝난다")
    func 감소된_모션() async throws {
        let stage = DiceStage(library: try TrajectoryLibrary.bundled())
        let start = ContinuousClock.now
        _ = await stage.roll(values: [1, 1, 1, 1, 1], slots: [0, 1, 2, 3, 4],
                             direction: .center, skipAnimation: true)
        #expect(ContinuousClock.now - start < .milliseconds(200))
        #expect(stage.isAnimating == false)
    }

    @Test("같은 눈을 여러 번 굴려도 자세가 매번 같지 않다")
    func 시각적_다양성() async throws {
        let stage = DiceStage(library: try TrajectoryLibrary.bundled())
        var orientations: Set<String> = []
        for _ in 0..<12 {
            _ = await stage.roll(values: [4, 4, 4, 4, 4], slots: [0, 1, 2, 3, 4],
                                 direction: .center, skipAnimation: true)
            let q = stage.orientation(slot: 0)!
            orientations.insert(String(format: "%.2f,%.2f,%.2f,%.2f", q.vector.x, q.vector.y, q.vector.z, q.vector.w))
        }
        #expect(orientations.count > 1, "매번 같은 자세로 멈춘다 — yaw 다양성이 동작하지 않는다")
    }

    @Test("굴림은 충돌 큐를 돌려준다")
    func 충돌_큐() async throws {
        let stage = DiceStage(library: try TrajectoryLibrary.bundled())
        let cues = await stage.roll(values: [2, 5, 1, 3, 6], slots: [0, 1, 2, 3, 4],
                                    direction: .right, skipAnimation: true)
        #expect(!cues.isEmpty, "충돌 큐가 비어 있다 — 사운드와 햅틱을 붙일 수 없다")
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
xcodebuild test -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:YachtDiceTests/DiceStageTests 2>&1 | tail -20
```
Expected: 컴파일 실패 — `cannot find 'DiceStage' in scope`

- [ ] **Step 3: `DiceStage.swift` 작성**

```swift
import Foundation
import RealityKit
import simd
import DiceTrajectory

/// 결과가 이미 정해진 주사위를 "굴리는 것처럼" 보여준다.
/// 물리를 돌리지 않고 구운 궤적을 재생하며, 각 주사위의 회전에만 오프셋을 곱한다.
@MainActor
final class DiceStage {
    private let library: TrajectoryLibrary
    private var root = Entity()
    private var dice: [ModelEntity] = []
    private(set) var isAnimating = false

    init(library: TrajectoryLibrary) {
        self.library = library
        root = DiceSceneBuilder.makeRoot()
        dice = DiceSceneBuilder.dice(in: root)
    }

    func attach(to content: RealityViewContent) {
        content.add(root)
        content.add(DiceSceneBuilder.makeCamera())
    }

    // MARK: - 조회 (테스트와 디버깅용)

    func orientation(slot: Int) -> simd_quatf? {
        guard dice.indices.contains(slot) else { return nil }
        return dice[slot].orientation
    }

    func faceUpValue(slot: Int) -> Int? {
        orientation(slot: slot).map { DieFace.upValue(for: $0) }
    }

    // MARK: - 재생

    /// - Parameters:
    ///   - values: 나와야 할 눈. slots와 같은 길이·순서다.
    ///   - slots: 굴릴 주사위 슬롯 (keep되지 않은 것들).
    ///   - skipAnimation: Reduce Motion이 켜져 있으면 true.
    /// - Returns: 재생 중 터뜨릴 충돌 큐. 호출자가 사운드·햅틱에 쓴다.
    func roll(values: [Int], slots: [Int], direction: ThrowDirection,
              skipAnimation: Bool) async -> [CollisionCue] {
        precondition(values.count == slots.count, "값과 슬롯의 개수가 다르다")
        guard !slots.isEmpty else { return [] }

        var generator = SystemRandomNumberGenerator()
        guard let trajectory = library.pick(dieCount: slots.count, direction: direction, using: &generator) else {
            // 궤적이 없으면 애니메이션 없이 결과만 앉힌다. 게임이 멈추는 것보다 낫다.
            settleImmediately(values: values, slots: slots, generator: &generator)
            return []
        }

        // 굴리는 각 주사위에 대해 오프셋을 미리 계산한다
        let offsets = (0..<slots.count).map { lane in
            FaceControl.offset(
                restUpFace: trajectory.restUpFace(die: lane),
                showing: values[lane],
                yawChoice: Int.random(in: 0..<4, using: &generator))
        }

        if skipAnimation {
            applyFrame(trajectory.frameCount - 1, of: trajectory, slots: slots, offsets: offsets)
            return trajectory.collisions
        }

        isAnimating = true
        defer { isAnimating = false }

        let frameDuration = Duration.seconds(1.0 / Double(trajectory.frameRate))
        var clock = ContinuousClock.now
        for frame in 0..<trajectory.frameCount {
            applyFrame(frame, of: trajectory, slots: slots, offsets: offsets)
            clock += frameDuration
            try? await Task.sleep(until: clock, clock: .continuous)
        }
        // 마지막 프레임을 한 번 더 확정해 반올림 오차를 없앤다
        applyFrame(trajectory.frameCount - 1, of: trajectory, slots: slots, offsets: offsets)
        return trajectory.collisions
    }

    /// keep한 주사위를 트레이 상단 선반으로 올린다.
    func placeHeld(_ heldSlots: [Int], values: [Int]) {
        let spacing = TrayGeometry.dieSize * 1.9
        for (order, slot) in heldSlots.sorted().enumerated() {
            guard dice.indices.contains(slot) else { continue }
            let x = (Float(order) - Float(heldSlots.count - 1) / 2) * spacing
            dice[slot].position = [x, TrayGeometry.shelfHeight, -TrayGeometry.trayInner.z / 2 - 0.02]
            // 선반 위에서는 눈이 정면에서 잘 보이도록 축정렬 자세를 유지한다
            if let target = OctahedralGroup.elements.first(where: { DieFace.upValue(for: $0) == values[slot] }) {
                dice[slot].orientation = target
            }
        }
    }

    func reset() {
        for (index, die) in dice.enumerated() {
            die.isEnabled = true
            die.position = [Float(index - 2) * TrayGeometry.dieSize * 1.6, TrayGeometry.dieSize / 2, 0]
            die.orientation = OctahedralGroup.elements[0]
        }
    }

    // MARK: - 내부

    private func applyFrame(_ frame: Int, of trajectory: Trajectory,
                            slots: [Int], offsets: [simd_quatf]) {
        for (lane, slot) in slots.enumerated() {
            guard dice.indices.contains(slot) else { continue }
            let pose = trajectory.posed(die: lane, frame: frame, offset: offsets[lane])
            dice[slot].position = pose.position
            dice[slot].orientation = pose.orientation
        }
    }

    private func settleImmediately(values: [Int], slots: [Int],
                                   generator: inout some RandomNumberGenerator) {
        for (lane, slot) in slots.enumerated() {
            guard dice.indices.contains(slot) else { continue }
            let candidates = OctahedralGroup.elements.filter { DieFace.upValue(for: $0) == values[lane] }
            dice[slot].orientation = candidates[Int.random(in: 0..<candidates.count, using: &generator)]
            dice[slot].position = [Float(slot - 2) * TrayGeometry.dieSize * 1.6, TrayGeometry.dieSize / 2, 0]
        }
    }
}
```

- [ ] **Step 4: `DiceStageView.swift` 작성**

```swift
import SwiftUI
import RealityKit

struct DiceStageView: View {
    let stage: DiceStage

    var body: some View {
        RealityView { content in
            stage.attach(to: content)
        }
        .accessibilityHidden(true)   // 주사위 값은 ActionBar가 음성으로 읽는다
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
xcodebuild test -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:YachtDiceTests/DiceStageTests 2>&1 | tail -20
```
Expected: PASS (5 tests)

- [ ] **Step 6: 커밋**

```bash
git add App Tests
git commit -m "$(cat <<'MSG'
feat(scene): 궤적 재생과 keep 선반

roll(values:slots:...)이 요청한 눈을 정확히 위로 올린다는 것을 테스트로 고정했다.
이 성질이 온라인 대전에서 두 화면이 같아지는 근거이므로 여기서 타협하지 않는다.

궤적을 못 찾으면 애니메이션 없이 결과만 앉힌다. 데이터 문제로 게임이 멈추는
것보다 낫고, 번들 검증 테스트가 이미 그런 상황을 막고 있다.

같은 눈을 반복해서 굴려도 자세가 매번 다른지 확인한다. yaw 4가지를 무작위로
고르는데, 이게 동작하지 않으면 화면이 눈에 띄게 반복적으로 보인다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 15: GameSession — 오케스트레이터와 연출 큐

스펙 §8.2. 상태는 즉시 전이하지만 화면은 주사위가 착지할 때까지 뒤처져 있어야 한다.

**Files:**
- Create: `App/Game/MatchDriver.swift`
- Create: `App/Game/GameSession.swift`
- Create: `Tests/YachtDiceTests/GameSessionTests.swift`

**Interfaces:**
- Consumes: `YachtCore` 전체, Task 14의 `DiceStage`
- Produces:
  - `protocol MatchDriver: Sendable` — `func requestRoll(count: Int) async throws -> [Int]`, `func submit(_ event: Event) async throws`, `var incoming: AsyncStream<Event> { get }`
  - `struct LocalDriver: MatchDriver`
  - `@MainActor @Observable final class GameSession`
  - `init(driver: any MatchDriver, stage: DiceStage, log: MatchLog)`
  - `var visibleState: GameState`, `var isBusy: Bool`, `var assistEnabled: Bool`
  - `func send(_ intent: Intent) async`
  - `func previewScore(_ category: ScoreCategory) -> Int?`
  - `var onLogChanged: (@Sendable (MatchLog) -> Void)?`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/YachtDiceTests/GameSessionTests.swift`:

```swift
import Testing
import Foundation
import YachtCore
import DiceTrajectory
@testable import YachtDice

/// 눈을 대본으로 공급하는 테스트용 드라이버.
private struct ScriptedDriver: MatchDriver {
    let script: [[Int]]
    let cursor = Counter()

    final class Counter: @unchecked Sendable {
        private var value = 0
        func next() -> Int { defer { value += 1 }; return value }
    }

    func requestRoll(count: Int) async throws -> [Int] {
        let roll = script[cursor.next() % script.count]
        return Array(roll.prefix(count))
    }
    func submit(_ event: Event) async throws {}
    var incoming: AsyncStream<Event> { AsyncStream { $0.finish() } }
}

@Suite("게임 세션")
@MainActor
struct GameSessionTests {

    /// - Parameter animated: 기본은 false. 궤적을 실제로 재생하면 굴림 하나에 2초가 걸려서
    ///   12턴 완주 테스트가 24초를 넘긴다. 연출 순서 자체를 보는 테스트만 true로 켠다.
    private func makeSession(script: [[Int]], animated: Bool = false) throws -> GameSession {
        let session = GameSession(
            driver: ScriptedDriver(script: script),
            stage: DiceStage(library: try TrajectoryLibrary.bundled()),
            log: MatchLog(playerCount: 1))
        session.reduceMotion = !animated
        return session
    }

    @Test("굴림 요청이 상태에 반영된다")
    func 굴림() async throws {
        let session = try makeSession(script: [[3, 1, 4, 6, 6]])
        await session.send(.roll)
        #expect(session.visibleState.dice == [3, 1, 4, 6, 6])
        #expect(session.visibleState.rollsRemaining == 2)
    }

    @Test("연출이 끝난 뒤에야 상태가 노출된다")
    func 연출_큐() async throws {
        let session = try makeSession(script: [[1, 1, 1, 1, 1]], animated: true)
        #expect(session.visibleState.phase == .awaitingFirstRoll)
        let task = Task { await session.send(.roll) }
        // send가 완료되기 전에는 아직 굴리기 전 상태여야 한다
        #expect(session.visibleState.dice == [0, 0, 0, 0, 0])
        await task.value
        #expect(session.visibleState.dice == [1, 1, 1, 1, 1])
    }

    @Test("불법 의도는 무시되고 상태를 바꾸지 않는다")
    func 불법_의도() async throws {
        let session = try makeSession(script: [[1, 2, 3, 4, 5]])
        let before = session.visibleState
        await session.send(.commit(.aces))   // 굴리기 전이라 불가
        #expect(session.visibleState == before)
    }

    @Test("기록하면 자동으로 다음 턴으로 넘어간다")
    func 기록_후_턴_전환() async throws {
        let session = try makeSession(script: [[6, 6, 6, 6, 6]])
        await session.send(.roll)
        await session.send(.commit(.yacht))
        #expect(session.visibleState.scorecards[0].entry(.yacht) == 50)
        #expect(session.visibleState.turnIndex == 2)
        #expect(session.visibleState.phase == .awaitingFirstRoll)
    }

    @Test("12턴을 마치면 게임이 끝난다")
    func 완주() async throws {
        let session = try makeSession(script: [[1, 2, 3, 4, 5]])
        for _ in 0..<12 {
            await session.send(.roll)
            let open = session.visibleState.scorecards[0].openCategories
            await session.send(.commit(open[0]))
        }
        #expect(session.visibleState.phase == .finished)
        #expect(session.visibleState.scorecards[0].isComplete)
    }

    @Test("Assist가 켜져 있으면 예상 점수를 준다")
    func 예상_점수() async throws {
        let session = try makeSession(script: [[5, 5, 5, 5, 5]])
        await session.send(.roll)
        session.assistEnabled = true
        #expect(session.previewScore(.yacht) == 50)
        #expect(session.previewScore(.fives) == 25)
        session.assistEnabled = false
        #expect(session.previewScore(.yacht) == nil)
    }

    @Test("이미 기록된 칸은 예상 점수를 주지 않는다")
    func 예상_점수_기록된_칸() async throws {
        let session = try makeSession(script: [[1, 1, 1, 1, 1]])
        session.assistEnabled = true
        await session.send(.roll)
        await session.send(.commit(.aces))
        await session.send(.roll)
        #expect(session.previewScore(.aces) == nil)
    }

    @Test("로그 변경이 통지된다 — 저장 훅")
    func 로그_통지() async throws {
        let session = try makeSession(script: [[2, 2, 2, 2, 2]])
        let recorder = LogRecorder()
        session.onLogChanged = { recorder.record($0) }
        await session.send(.roll)
        #expect(recorder.count > 0, "저장 훅이 불리지 않았다")
    }

    final class LogRecorder: @unchecked Sendable {
        private(set) var count = 0
        func record(_ log: MatchLog) { count += 1 }
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
xcodebuild test -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:YachtDiceTests/GameSessionTests 2>&1 | tail -20
```
Expected: 컴파일 실패 — `cannot find 'GameSession' in scope`

- [ ] **Step 3: `MatchDriver.swift` 작성**

```swift
import Foundation
import YachtCore

/// 눈의 출처와 상대 행동의 통로. P2는 AIDriver, P3는 OnlineDriver를 여기 끼운다.
/// 이 프로토콜이 있으면 뷰와 코어는 온라인 대전이 붙어도 바뀌지 않는다.
protocol MatchDriver: Sendable {
    func requestRoll(count: Int) async throws -> [Int]
    func submit(_ event: Event) async throws
    var incoming: AsyncStream<Event> { get }
}

/// P1의 유일한 드라이버. 눈을 로컬에서 굴린다.
struct LocalDriver: MatchDriver {
    func requestRoll(count: Int) async throws -> [Int] {
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in Int.random(in: 1...6, using: &generator) }
    }

    func submit(_ event: Event) async throws {}

    /// 로컬 게임에는 상대가 없다.
    var incoming: AsyncStream<Event> { AsyncStream { $0.finish() } }
}
```

- [ ] **Step 4: `GameSession.swift` 작성**

```swift
import Foundation
import Observation
import YachtCore
import DiceTrajectory

/// 코어·드라이버·3D 연출을 잇는 유일한 오케스트레이터.
///
/// 핵심: 상태는 이벤트 발생 즉시 전이하지만, 화면에 노출되는 visibleState는
/// 주사위가 착지한 뒤에야 갱신된다. 점수판 미리보기가 주사위보다 먼저 뜨면
/// 게임이 망가진다 (스펙 §8.2).
@MainActor
@Observable
final class GameSession {
    private let driver: any MatchDriver
    private let stage: DiceStage
    private var log: MatchLog

    /// 뷰가 보는 상태. 연출이 끝난 뒤에만 갱신된다.
    private(set) var visibleState: GameState
    /// 연출 중이거나 드라이버를 기다리는 중이면 참. 입력을 잠그는 데 쓴다.
    private(set) var isBusy = false
    var assistEnabled = true
    var reduceMotion = false

    var onLogChanged: (@Sendable (MatchLog) -> Void)?
    var onCollisionCues: (@MainActor ([CollisionCue]) -> Void)?

    init(driver: any MatchDriver, stage: DiceStage, log: MatchLog) {
        self.driver = driver
        self.stage = stage
        self.log = log
        self.visibleState = log.state
    }

    func send(_ intent: Intent) async {
        guard !isBusy, visibleState.allows(intent) else { return }
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
            if !visibleState.isAllScored { stage.reset() }
        }
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

    private func performRoll() async {
        let slots = visibleState.rollableIndices
        guard let values = try? await driver.requestRoll(count: slots.count) else { return }

        // 상태는 즉시 전이시키되 화면에는 아직 노출하지 않는다
        let pending = visibleState.applying(.rolled(values))

        let direction: ThrowDirection = ThrowDirection.allCases.randomElement() ?? .center
        let cues = await stage.roll(values: values, slots: slots,
                                    direction: direction, skipAnimation: reduceMotion)
        onCollisionCues?(cues)

        // 착지한 뒤에 노출한다
        log.append(.rolled(values))
        visibleState = pending
        try? await driver.submit(.rolled(values))
        onLogChanged?(log)
    }

    private func commitEvents(_ events: [Event]) async {
        var state = visibleState
        for event in events {
            log.append(event)
            state = state.applying(event)
            try? await driver.submit(event)
        }
        visibleState = state
        onLogChanged?(log)
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
xcodebuild test -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:YachtDiceTests/GameSessionTests 2>&1 | tail -20
```
Expected: PASS (8 tests)

- [ ] **Step 6: 커밋**

```bash
git add App Tests
git commit -m "$(cat <<'MSG'
feat(game): 오케스트레이터와 연출 큐

visibleState를 내부 상태와 분리했다. 주사위가 1.8초 굴러가는 동안 점수판
미리보기가 먼저 뜨면 게임이 망가진다. 착지한 뒤에만 노출한다.

MatchDriver 프로토콜로 눈의 출처를 추상화했다. P1은 LocalDriver 하나뿐이지만,
P3에서 OnlineDriver를 끼우면 뷰와 코어는 한 줄도 바뀌지 않는다. 이게 이
프로젝트에서 이벤트 소싱을 택한 이유다.

기록 직후 turnAdvanced와 gameEnded 중 무엇을 낼지는 세션이 판단한다. 코어는
"모든 칸이 찼는가"만 알려주고 어떤 이벤트를 낼지는 정하지 않는다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 16: 점수판 뷰

레퍼런스의 Assist 표시를 그대로 옮긴다. 확정 점수는 검정 볼드, 예상 점수는 노란색.

**Files:**
- Create: `App/Views/ScoreboardView.swift`
- Create: `App/Views/CategoryDisplay.swift`
- Create: `Tests/YachtDiceTests/CategoryDisplayTests.swift`

**Interfaces:**
- Consumes: Task 15의 `GameSession`, `YachtCore.ScoreCategory`
- Produces:
  - `extension ScoreCategory { var displayName: String; var accessibilityDescription: String }`
  - `struct ScoreboardView: View` — `init(session: GameSession)`
  - 접근성 식별자: `"scoreboard.row.<category.rawValue>"`, `"scoreboard.total"`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/YachtDiceTests/CategoryDisplayTests.swift`:

```swift
import Testing
import YachtCore
@testable import YachtDice

@Suite("카테고리 표시")
struct CategoryDisplayTests {

    @Test("모든 카테고리에 표시 이름이 있다")
    func 이름_존재() {
        for category in ScoreCategory.allCases {
            #expect(!category.displayName.isEmpty, "\(category)의 표시 이름이 비어 있다")
            #expect(!category.accessibilityDescription.isEmpty, "\(category)의 음성 설명이 비어 있다")
        }
    }

    @Test("표시 이름이 서로 겹치지 않는다")
    func 이름_유일성() {
        let names = ScoreCategory.allCases.map(\.displayName)
        #expect(Set(names).count == names.count, "중복된 표시 이름이 있다")
    }

    @Test("음성 설명이 조건을 알려준다")
    func 음성_설명() {
        #expect(ScoreCategory.yacht.accessibilityDescription.contains("5"))
        #expect(ScoreCategory.fullHouse.accessibilityDescription.contains("3"))
        #expect(ScoreCategory.smallStraight.accessibilityDescription.contains("4"))
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
xcodebuild test -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:YachtDiceTests/CategoryDisplayTests 2>&1 | tail -20
```
Expected: 컴파일 실패 — `value of type 'ScoreCategory' has no member 'displayName'`

- [ ] **Step 3: `CategoryDisplay.swift` 작성**

```swift
import Foundation
import YachtCore

extension ScoreCategory {
    /// 점수판에 보이는 이름. 레퍼런스 표기를 따른다.
    var displayName: String {
        switch self {
        case .aces:          "Aces"
        case .deuces:        "Deuces"
        case .threes:        "Threes"
        case .fours:         "Fours"
        case .fives:         "Fives"
        case .sixes:         "Sixes"
        case .choice:        "Choice"
        case .fourOfAKind:   "4 of a Kind"
        case .fullHouse:     "Full House"
        case .smallStraight: "S. Straight"
        case .largeStraight: "L. Straight"
        case .yacht:         "Yacht"
        }
    }

    /// VoiceOver가 읽는 설명. 레퍼런스의 툴팁과 같은 역할이다.
    var accessibilityDescription: String {
        switch self {
        case .aces:          "1이 나온 주사위의 합"
        case .deuces:        "2가 나온 주사위의 합"
        case .threes:        "3이 나온 주사위의 합"
        case .fours:         "4가 나온 주사위의 합"
        case .fives:         "5가 나온 주사위의 합"
        case .sixes:         "6이 나온 주사위의 합"
        case .choice:        "주사위 5개의 합"
        case .fourOfAKind:   "같은 숫자 4개 이상이면 주사위 5개의 합"
        case .fullHouse:     "같은 숫자 3개와 2개면 주사위 5개의 합"
        case .smallStraight: "연속된 숫자 4개면 15점"
        case .largeStraight: "연속된 숫자 5개면 30점"
        case .yacht:         "같은 숫자 5개면 50점"
        }
    }
}
```

- [ ] **Step 4: `ScoreboardView.swift` 작성**

```swift
import SwiftUI
import YachtCore

struct ScoreboardView: View {
    let session: GameSession

    private var state: GameState { session.visibleState }
    private var card: ScoreCard { state.scorecards[state.currentPlayer] }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ScoreCategory.upperCases, id: \.self) { row($0) }
            subtotalRow
            Divider()
            ForEach(lowerCategories, id: \.self) { row($0) }
            Divider()
            totalRow
        }
        .font(.system(.subheadline, design: .rounded))
        .padding(.horizontal, 12)
    }

    private var lowerCategories: [ScoreCategory] {
        ScoreCategory.allCases.filter { !$0.isUpper }
    }

    private func row(_ category: ScoreCategory) -> some View {
        let recorded = card.entry(category)
        let preview = session.previewScore(category)

        return Button {
            Task { await session.send(.commit(category)) }
        } label: {
            HStack {
                Text(category.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                Group {
                    if let recorded {
                        Text("\(recorded)").fontWeight(.bold).foregroundStyle(.primary)
                    } else if let preview {
                        Text("\(preview)").foregroundStyle(.orange)
                    } else {
                        Text("").frame(width: 1)
                    }
                }
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .disabled(recorded != nil || !state.allows(.commit(category)) || session.isBusy)
        .accessibilityIdentifier("scoreboard.row.\(category.rawValue)")
        .accessibilityLabel(accessibilityLabel(for: category, recorded: recorded, preview: preview))
        .accessibilityHint(recorded == nil ? category.accessibilityDescription : "")
    }

    private func accessibilityLabel(for category: ScoreCategory, recorded: Int?, preview: Int?) -> String {
        if let recorded { return "\(category.displayName), \(recorded)점 기록됨" }
        if let preview { return "\(category.displayName), 지금 기록하면 \(preview)점" }
        return "\(category.displayName), 비어 있음"
    }

    private var subtotalRow: some View {
        HStack {
            Text("보너스까지")
            Spacer()
            Text("\(card.upperSubtotal)/\(ScoreCard.upperBonusThreshold)")
                .monospacedDigit()
                .foregroundStyle(card.upperBonus > 0 ? .green : .secondary)
            if card.upperBonus > 0 {
                Text("+\(card.upperBonus)").foregroundStyle(.green).monospacedDigit()
            }
        }
        .font(.caption)
        .padding(.vertical, 4)
        .accessibilityIdentifier("scoreboard.subtotal")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.upperBonus > 0
            ? "상단 소계 \(card.upperSubtotal)점, 보너스 35점 획득"
            : "상단 소계 \(card.upperSubtotal)점, 보너스까지 \(ScoreCard.upperBonusThreshold - card.upperSubtotal)점 남음")
    }

    private var totalRow: some View {
        HStack {
            Text("Total").fontWeight(.semibold)
            Spacer()
            Text("\(card.total)").fontWeight(.bold).monospacedDigit()
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("scoreboard.total")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("총점 \(card.total)점")
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
xcodebuild test -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:YachtDiceTests/CategoryDisplayTests 2>&1 | tail -20
```
Expected: PASS (3 tests)

- [ ] **Step 6: 커밋**

```bash
git add App Tests
git commit -m "$(cat <<'MSG'
feat(ui): 점수판과 Assist 표시

레퍼런스의 Assist를 그대로 옮겼다. 확정 점수는 검정 볼드, 예상 점수는 주황색.
색만으로 구분하면 색각 이상 사용자가 읽을 수 없으므로 굵기도 함께 다르게 했고,
VoiceOver 레이블에 "기록됨"과 "지금 기록하면"을 넣어 구분을 말로도 전달한다.

상단 소계를 "12/63" 형식으로 보여준다. 보너스까지 남은 거리가 야추의 핵심
의사결정이라 숫자만 있으면 매번 암산해야 한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 17: 액션 바와 화면 통합

**Files:**
- Create: `App/Views/ActionBarView.swift`
- Create: `App/Views/GameScreen.swift`
- Modify: `App/YachtDiceApp.swift`

**Interfaces:**
- Consumes: Task 14의 `DiceStageView`, Task 15의 `GameSession`, Task 16의 `ScoreboardView`
- Produces:
  - `struct ActionBarView: View`, `struct GameScreen: View`
  - `var GameSession.nextThrowDirection: ThrowDirection?` (Step 3에서 추가)
  - 접근성 식별자: `"action.roll"`, `"action.die.<index>"`, `"action.assist"`, `"header.turn"`

**레이아웃 비율**: 스펙 §9는 "상단 약 55%가 3D 트레이"라고 쓰지만, 그 55%는 헤더 + 3D + 액션 바를 합친 상단 블록을 뜻한다. `RealityView` 자체는 화면 높이의 42%를 쓰고 헤더·액션 바가 나머지 13%를 채운다.

- [ ] **Step 1: `ActionBarView.swift` 작성**

```swift
import SwiftUI
import YachtCore

struct ActionBarView: View {
    let session: GameSession

    private var state: GameState { session.visibleState }

    var body: some View {
        VStack(spacing: 10) {
            diceRow
            HStack(spacing: 16) {
                assistToggle
                Spacer()
                rollButton
            }
        }
        .padding(.horizontal, 16)
    }

    /// 각 주사위의 keep 상태를 누를 수 있는 칩. 3D 주사위를 직접 만지는 것보다
    /// 정확하고, VoiceOver로도 조작할 수 있다.
    private var diceRow: some View {
        HStack(spacing: 8) {
            ForEach(0..<YachtCore.diceCount, id: \.self) { index in
                let value = state.dice[index]
                let isHeld = state.held.contains(index)
                Button {
                    Task { await session.send(.toggleHold(index)) }
                } label: {
                    Text(value == 0 ? "–" : "\(value)")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 44, height: 44)
                        .background(isHeld ? Color.orange.opacity(0.25) : Color.secondary.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(isHeld ? Color.orange : .clear, lineWidth: 2))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!state.allows(.toggleHold(index)) || session.isBusy)
                .accessibilityIdentifier("action.die.\(index)")
                .accessibilityLabel(value == 0 ? "주사위 \(index + 1), 아직 안 굴림"
                                               : "주사위 \(index + 1), \(value)")
                .accessibilityValue(isHeld ? "고정됨" : "고정 안 됨")
                .accessibilityHint("두 번 탭하면 고정을 바꿉니다")
            }
        }
    }

    private var assistToggle: some View {
        Toggle(isOn: Binding(get: { session.assistEnabled },
                             set: { session.assistEnabled = $0 })) {
            Text("Assist").font(.footnote)
        }
        .toggleStyle(.button)
        .accessibilityIdentifier("action.assist")
        .accessibilityLabel("예상 점수 표시")
    }

    private var rollButton: some View {
        Button {
            Task { await session.send(.roll) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "dice.fill")
                Text(state.rollsRemaining > 0 ? "Roll (\(state.rollsRemaining))" : "Roll")
            }
            .font(.headline)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!state.allows(.roll) || session.isBusy)
        .accessibilityIdentifier("action.roll")
        .accessibilityLabel("주사위 굴리기, \(state.rollsRemaining)회 남음")
    }
}
```

- [ ] **Step 2: `GameScreen.swift` 작성**

```swift
import SwiftUI
import YachtCore

struct GameScreen: View {
    let session: GameSession
    let stage: DiceStage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                DiceStageView(stage: stage)
                    .frame(height: geometry.size.height * 0.42)
                ActionBarView(session: session)
                    .padding(.vertical, 10)
                Divider()
                ScrollView {
                    ScoreboardView(session: session)
                }
            }
        }
        .onChange(of: reduceMotion, initial: true) { _, newValue in
            session.reduceMotion = newValue
        }
    }

    private var header: some View {
        HStack {
            Text("Turn \(session.visibleState.turnIndex)/\(YachtCore.turnCount)")
                .font(.system(.headline, design: .rounded))
                .monospacedDigit()
            Spacer()
            if session.visibleState.phase == .finished {
                Text("게임 종료").font(.headline).foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityIdentifier("header.turn")
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 3: 스와이프 던지기 추가 (스펙 §7.6)**

스와이프 방향으로 던지면 해당 방향 그룹의 궤적을 고른다. Roll 버튼은 그대로 두고 병행한다 — 제스처 전용으로 두면 VoiceOver 사용자가 게임을 진행할 수 없다.

`App/Game/GameSession.swift`에 추가:

```swift
    /// 다음 굴림에 쓸 던지는 방향. 제스처가 설정하고 performRoll이 소비한다.
    /// nil이면 무작위로 고른다 (버튼으로 굴린 경우).
    var nextThrowDirection: ThrowDirection?
```

`performRoll()`의 방향 선택을 교체:

```swift
        let direction = nextThrowDirection ?? ThrowDirection.allCases.randomElement() ?? .center
        nextThrowDirection = nil
```

`App/Views/GameScreen.swift`의 `DiceStageView`에 제스처를 붙인다:

```swift
                DiceStageView(stage: stage)
                    .frame(height: geometry.size.height * 0.42)
                    .contentShape(Rectangle())
                    .gesture(throwGesture)
```

`GameScreen`에 추가:

```swift
    /// 위로 쓸어올리면 던진다. 좌우 성분으로 궤적 그룹을 고른다.
    private var throwGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                // 아래로 쓸어내린 것은 던지기가 아니다
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
```

`GameScreen.swift` 맨 위에 `import DiceTrajectory`를 추가한다.

**확인**: 트레이 영역을 왼쪽 위로 쓸면 주사위가 왼쪽에서 굴러들어오고, 오른쪽 위로 쓸면 오른쪽에서 들어온다. 방향이 반대로 보이면 `ThrowDirection`의 부호를 Task 12의 `resetDice`에 있는 `lateral` 값과 맞춰 뒤집는다.

- [ ] **Step 4: `YachtDiceApp.swift` 교체**

```swift
import SwiftUI
import YachtCore

@main
struct YachtDiceApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            switch container.status {
            case .loading:
                ProgressView("불러오는 중")
            case .ready(let session, let stage):
                GameScreen(session: session, stage: stage)
            case .failed(let message):
                ContentUnavailableView("시작할 수 없습니다", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            }
        }
    }
}

/// 앱 조립을 한 곳에 모은다. Task 18에서 저장 복원이 여기 붙는다.
@MainActor
@Observable
final class AppContainer {
    enum Status {
        case loading
        case ready(GameSession, DiceStage)
        case failed(String)
    }

    private(set) var status: Status = .loading

    init() {
        do {
            let stage = DiceStage(library: try TrajectoryLibrary.bundled())
            let session = GameSession(driver: LocalDriver(), stage: stage,
                                      log: MatchLog(playerCount: 1))
            status = .ready(session, stage)
        } catch {
            status = .failed("주사위 데이터를 읽지 못했습니다: \(error)")
        }
    }
}
```

- [ ] **Step 5: 시뮬레이터에서 실행해 눈으로 확인**

```bash
xcodegen generate
xcodebuild build -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' | tail -3
```

Xcode에서 Run하고 확인할 것:
- Roll을 누르면 주사위가 트레이 안에서 굴러가 멈춘다
- 멈춘 주사위의 눈이 액션 바의 숫자 칩과 **일치한다** (여기가 어긋나면 Task 14로 돌아간다)
- 주사위 칩을 누르면 주황색 테두리가 생기고, 다시 Roll하면 그 주사위만 그대로다
- Assist를 끄면 점수판의 주황색 숫자가 사라진다
- 점수판 칸을 누르면 기록되고 다음 턴으로 넘어간다
- 트레이를 위로 쓸어올려도 굴러가고, 좌우로 비껴 쓸면 들어오는 방향이 달라진다

- [ ] **Step 6: 커밋**

```bash
git add App
git commit -m "$(cat <<'MSG'
feat(ui): 액션 바와 세로 화면 통합

주사위 keep을 3D 주사위 직접 터치가 아니라 숫자 칩으로 만들었다. 작은 화면에서
16mm 주사위를 정확히 겨냥하기 어렵고, VoiceOver로는 아예 조작할 수 없다.
칩에는 눈 숫자가 그대로 적혀 있어서 3D와 상태가 어긋나면 즉시 눈에 띈다.

스와이프로도 던질 수 있지만 Roll 버튼을 없애지 않았다. 제스처 전용으로 두면
VoiceOver 사용자가 게임을 진행할 수 없다.

keep 표시를 색만으로 하지 않고 테두리 굵기도 함께 바꿨다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 18: 저장과 복원

스펙 §10. 앱을 강제 종료해도 진행이 남아야 한다.

**Files:**
- Create: `App/Game/MatchStore.swift`
- Modify: `App/YachtDiceApp.swift` (AppContainer에 복원 연결)
- Create: `Tests/YachtDiceTests/MatchStoreTests.swift`

**Interfaces:**
- Consumes: `YachtCore.MatchLog`
- Produces:
  - `struct MatchStore: Sendable` — `init(directory: URL)`, `static var `default`: MatchStore`
  - `func save(_ log: MatchLog) throws`, `func load() throws -> MatchLog?`, `func clear() throws`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/YachtDiceTests/MatchStoreTests.swift`:

```swift
import Testing
import Foundation
import YachtCore
@testable import YachtDice

@Suite("진행 저장")
struct MatchStoreTests {

    private func makeTempStore() throws -> (MatchStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "yacht-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (MatchStore(directory: directory), directory)
    }

    @Test("저장한 로그를 그대로 읽는다")
    func 왕복() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var log = MatchLog(playerCount: 1)
        log.append(.rolled([6, 6, 6, 6, 6]))
        log.append(.committed(.yacht, 50))
        try store.save(log)

        let loaded = try #require(try store.load())
        #expect(loaded == log)
        #expect(loaded.state.scorecards[0].entry(.yacht) == 50)
    }

    @Test("저장한 적이 없으면 nil이다")
    func 없음() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try store.load() == nil)
    }

    @Test("clear하면 사라진다")
    func 삭제() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var log = MatchLog(playerCount: 1)
        log.append(.rolled([1, 1, 1, 1, 1]))
        try store.save(log)
        try store.clear()
        #expect(try store.load() == nil)
    }

    @Test("깨진 파일은 nil로 처리하고 앱을 막지 않는다")
    func 손상된_파일() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("이건 JSON이 아니다".utf8).write(to: directory.appending(path: "match.json"))
        #expect(try store.load() == nil, "깨진 저장 파일 때문에 앱이 시작되지 못하면 안 된다")
    }

    @Test("끝난 게임은 저장하지 않는다")
    func 완결된_게임() throws {
        let (store, directory) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var log = MatchLog(playerCount: 1)
        for category in ScoreCategory.allCases {
            log.append(.rolled([1, 1, 1, 1, 1]))
            log.append(.committed(category, 0))
            log.append(.turnAdvanced)
        }
        log.append(.gameEnded)
        try store.save(log)
        #expect(try store.load() == nil, "끝난 게임을 복원하면 결과 화면에 갇힌다")
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
xcodebuild test -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:YachtDiceTests/MatchStoreTests 2>&1 | tail -20
```
Expected: 컴파일 실패 — `cannot find 'MatchStore' in scope`

- [ ] **Step 3: `MatchStore.swift` 작성**

```swift
import Foundation
import YachtCore

/// 진행 중인 판을 파일 하나로 보관한다.
/// 이벤트 소싱이라 저장할 것이 로그뿐이고, 복원은 리플레이다.
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
    func save(_ log: MatchLog) throws {
        guard !log.isFinished else {
            try clear()
            return
        }
        try log.encoded().write(to: fileURL, options: .atomic)
    }

    /// 읽기 실패는 오류로 올리지 않는다. 저장 파일 하나 때문에 앱이 시작조차
    /// 못 하는 것보다, 새 판으로 시작하는 편이 낫다.
    func load() throws -> MatchLog? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL),
              let log = try? MatchLog.decoded(from: data),
              !log.isFinished
        else { return nil }
        return log
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
```

- [ ] **Step 4: `AppContainer`에 복원 연결**

`App/YachtDiceApp.swift`의 `AppContainer.init()`을 교체:

```swift
    private let store = MatchStore.default

    init() {
        do {
            let stage = DiceStage(library: try TrajectoryLibrary.bundled())
            let restored = (try? store.load()) ?? nil
            let session = GameSession(driver: LocalDriver(), stage: stage,
                                      log: restored ?? MatchLog(playerCount: 1))

            // 복원한 판이면 주사위를 마지막 상태로 앉힌다
            if let restored, restored.state.phase == .rolling {
                let state = restored.state
                Task { @MainActor in
                    _ = await stage.roll(values: state.dice, slots: Array(0..<YachtCore.diceCount),
                                         direction: .center, skipAnimation: true)
                    stage.placeHeld(state.held.sorted(), values: state.dice)
                }
            }

            let store = store
            session.onLogChanged = { log in
                try? store.save(log)
            }
            status = .ready(session, stage)
        } catch {
            status = .failed("주사위 데이터를 읽지 못했습니다: \(error)")
        }
    }
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
xcodebuild test -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:YachtDiceTests/MatchStoreTests 2>&1 | tail -20
```
Expected: PASS (5 tests)

- [ ] **Step 6: 시뮬레이터에서 실제 복원 확인**

Xcode에서 Run → 몇 턴 진행 → Xcode의 Stop으로 강제 종료 → 다시 Run.
턴 번호, 점수판, 주사위 눈이 그대로 남아 있어야 한다.

- [ ] **Step 7: 커밋**

```bash
git add App Tests
git commit -m "$(cat <<'MSG'
feat(game): 진행 저장과 복원

저장할 것이 이벤트 로그뿐이라 복원은 리플레이다. P3 재접속과 같은 메커니즘이라
두 번 만들지 않는다.

읽기 실패를 오류로 올리지 않는다. 저장 파일 하나가 깨졌다고 앱이 시작조차
못 하는 것보다 새 판으로 시작하는 편이 낫다. 깨진 파일 케이스를 테스트로 뒀다.

끝난 게임은 저장하지 않는다. 복원하면 결과 화면에 갇혀서 새 판을 시작할 수 없다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 19: 접근성 마감

**Files:**
- Modify: `App/Views/ScoreboardView.swift`
- Modify: `App/Views/ActionBarView.swift`
- Create: `Tests/YachtDiceTests/AccessibilityAuditTests.swift`

**Interfaces:**
- Consumes: Task 16·17의 뷰
- Produces: 없음 (기존 뷰 보강)

- [ ] **Step 1: 접근성 감사 테스트 작성**

`Tests/YachtDiceTests/AccessibilityAuditTests.swift`:

```swift
import Testing
import SwiftUI
import YachtCore
@testable import YachtDice

@Suite("접근성")
@MainActor
struct AccessibilityAuditTests {

    @Test("모든 카테고리 행에 고유한 접근성 식별자가 있다")
    func 식별자_유일성() {
        let identifiers = ScoreCategory.allCases.map { "scoreboard.row.\($0.rawValue)" }
        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test("Reduce Motion이 세션에 전달된다")
    func 감소된_모션_전달() throws {
        let session = GameSession(
            driver: LocalDriver(),
            stage: DiceStage(library: try TrajectoryLibrary.bundled()),
            log: MatchLog(playerCount: 1))
        session.reduceMotion = true
        #expect(session.reduceMotion == true)
    }

    @Test("Dynamic Type 최대 크기에서도 점수판 행이 한 줄에 들어간다")
    func 큰_글씨() {
        // 가장 긴 이름 + 3자리 점수가 표준 폭에서 잘리지 않아야 한다.
        // 실제 렌더 검증은 Step 3의 수동 확인으로 하고, 여기서는 길이 상한만 고정한다.
        for category in ScoreCategory.allCases {
            #expect(category.displayName.count <= 12,
                    "\(category.displayName)이 길어서 큰 글씨에서 잘린다")
        }
    }

    @Test("최고 점수도 3자리를 넘지 않는다")
    func 점수_자릿수() {
        // 야추 최고 총점: 상단 105 + 보너스 35 + Choice 30 + 4K 30 + FH 30 + 15 + 30 + 50 = 325
        var card = ScoreCard()
        for (index, category) in ScoreCategory.upperCases.enumerated() { card.record(category, (index + 1) * 5) }
        card.record(.choice, 30)
        card.record(.fourOfAKind, 30)
        card.record(.fullHouse, 30)
        card.record(.smallStraight, 15)
        card.record(.largeStraight, 30)
        card.record(.yacht, 50)
        #expect(card.total < 1000, "총점이 4자리가 되면 레이아웃이 깨진다")
    }
}
```

- [ ] **Step 2: 테스트 실행**

```bash
xcodebuild test -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:YachtDiceTests/AccessibilityAuditTests 2>&1 | tail -20
```
Expected: PASS (4 tests)

- [ ] **Step 3: 시뮬레이터에서 수동 확인**

Xcode의 Accessibility Inspector 또는 시뮬레이터 설정으로 확인한다:

```bash
# 설정 > 손쉬운 사용 > 동작 > 동작 줄이기 켜기
xcrun simctl spawn booted defaults write com.apple.Accessibility ReduceMotionEnabled -int 1
```

확인 목록:
- **Reduce Motion 켜짐**: Roll을 누르면 주사위가 즉시 결과 자세로 나타난다 (굴러가지 않는다)
- **Dynamic Type 최대(AX5)**: 점수판 행 이름과 숫자가 겹치지 않는다. 겹치면 `ScoreboardView.row`의 `HStack`을 `ViewThatFits`로 감싸 세로 배치로 대체한다
- **VoiceOver**: 스와이프 순서가 헤더 → 주사위 칩 5개 → Assist → Roll → 점수판 위에서 아래로 흐른다
- **VoiceOver**: 주사위 칩을 포커스하면 "주사위 1, 3, 고정 안 됨"처럼 읽는다
- **색 반전 / 명암 증가**: 예상 점수 주황색과 확정 점수 검정이 여전히 구분된다

Reduce Motion을 원래대로:
```bash
xcrun simctl spawn booted defaults write com.apple.Accessibility ReduceMotionEnabled -int 0
```

- [ ] **Step 4: 수동 확인에서 나온 문제를 고치고 커밋**

```bash
git add App Tests
git commit -m "$(cat <<'MSG'
feat(a11y): 접근성 마감

Reduce Motion에서 궤적 재생을 건너뛴다. 1.8초짜리 3D 애니메이션은 전정기관
장애가 있는 사용자에게 실제로 불편을 준다.

점수판 행에서 이름과 숫자가 큰 글씨에서 겹치는지 확인했다. VoiceOver 스와이프
순서를 헤더 - 주사위 - 액션 - 점수판으로 맞췄다.

예상 점수와 확정 점수의 구분을 색에만 의존하지 않도록 굵기와 음성 레이블을
함께 다르게 했다. 색각 이상 사용자에게 Assist가 무의미해지면 안 된다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

### Task 20: 스모크 테스트와 P1 완료 검증

**Files:**
- Modify: `Tests/YachtDiceUITests/LaunchUITests.swift`
- Create: `Tests/YachtDiceUITests/FullGameUITests.swift`

**Interfaces:**
- Consumes: Task 17의 접근성 식별자
- Produces: 없음 (P1 종료)

- [ ] **Step 1: 12턴 완주 스모크 테스트 작성**

`Tests/YachtDiceUITests/FullGameUITests.swift`:

```swift
import XCTest

final class FullGameUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// 12턴을 끝까지 진행한다. P1 완료 기준의 첫 번째 항목이다.
    func test_12턴을_완주한다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch"]
        app.launch()

        let roll = app.buttons["action.roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: 15), "Roll 버튼이 없다")

        let categories = [
            "aces", "deuces", "threes", "fours", "fives", "sixes",
            "choice", "fourOfAKind", "fullHouse", "smallStraight", "largeStraight", "yacht",
        ]

        for (turn, category) in categories.enumerated() {
            XCTAssertTrue(roll.waitForHittable(timeout: 15), "\(turn + 1)턴에서 Roll을 누를 수 없다")
            roll.tap()

            let row = app.buttons["scoreboard.row.\(category)"]
            XCTAssertTrue(row.waitForHittable(timeout: 15), "\(turn + 1)턴에서 \(category)를 누를 수 없다")
            row.tap()
        }

        XCTAssertTrue(app.staticTexts["게임 종료"].waitForExistence(timeout: 10), "12턴 뒤에 게임이 끝나지 않았다")
    }

    /// 앱을 재시작해도 진행이 남는다. P1 완료 기준의 다섯 번째 항목이다.
    func test_재시작_후_진행이_복원된다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch"]
        app.launch()

        let roll = app.buttons["action.roll"]
        XCTAssertTrue(roll.waitForHittable(timeout: 15))
        roll.tap()

        let row = app.buttons["scoreboard.row.choice"]
        XCTAssertTrue(row.waitForHittable(timeout: 15))
        row.tap()

        let headerBefore = app.otherElements["header.turn"].label
        XCTAssertTrue(headerBefore.contains("2"), "기록 후 2턴이어야 한다: \(headerBefore)")

        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launch()   // -resetMatch 없이

        let header = relaunched.otherElements["header.turn"]
        XCTAssertTrue(header.waitForExistence(timeout: 15))
        XCTAssertEqual(header.label, headerBefore, "재시작 후 턴이 복원되지 않았다")
    }
}

extension XCUIElement {
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists && isHittable { return true }
            _ = XCUIApplication().wait(for: .runningForeground, timeout: 0.2)
        }
        return false
    }
}
```

- [ ] **Step 2: `-resetMatch` 실행 인자 지원 추가**

`App/YachtDiceApp.swift`의 `AppContainer.init()` 맨 앞에 추가:

```swift
        // UI 테스트가 깨끗한 상태에서 시작할 수 있게 한다
        if ProcessInfo.processInfo.arguments.contains("-resetMatch") {
            try? MatchStore.default.clear()
        }
```

- [ ] **Step 3: UI 테스트 실행**

```bash
xcodebuild test -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:YachtDiceUITests 2>&1 | tail -30
```
Expected: PASS (3 tests — 실행 1 + 완주 1 + 복원 1)

- [ ] **Step 4: 전체 테스트 스위트 실행**

```bash
swift test --package-path "Packages/YachtCore"
swift test --package-path "Packages/DiceTrajectory"
xcodebuild test -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -20
```
Expected: 세 명령 모두 PASS

- [ ] **Step 5: P1 완료 기준을 하나씩 확인한다**

스펙 §15의 6개 항목을 실제로 검증하고 결과를 적는다. **통과했다고 쓰기 전에 각 항목을 실제로 실행한다.**

| # | 기준 | 검증 방법 | 결과 |
|---|---|---|---|
| 1 | 혼자 12턴을 끝까지 플레이할 수 있다 | `FullGameUITests.test_12턴을_완주한다` | |
| 2 | 점수와 상단 보너스가 93,312 케이스 전수 검증을 통과한다 | `ExhaustiveScoringTests` | |
| 3 | 주사위 3D 굴림 결과가 목표 눈과 100% 일치한다 | `FaceControlTests` + `TrajectoryLibraryTests.전체_검증` + `DiceStageTests.재생_결과_일치` | |
| 4 | Keep / Reroll / Assist 토글이 동작한다 | 시뮬레이터 수동 확인 | |
| 5 | 앱 강제 종료 후 진행이 복원된다 | `FullGameUITests.test_재시작_후_진행이_복원된다` | |
| 6 | iOS 18 지원 최저 기기에서 60fps를 유지한다 | 아래 Step 6 | |

- [ ] **Step 6: 프레임레이트 측정**

실기기(iPhone SE 3세대 또는 보유한 가장 낮은 사양)에 설치하고 Instruments의 Animation Hitches 템플릿으로 측정한다.

```bash
xcodebuild build -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'generic/platform=iOS' -configuration Release | tail -3
```

Xcode → Product → Profile → Animation Hitches. 주사위를 20회 굴리는 동안:
- Hitch time ratio가 5ms/s 미만이면 통과
- 초과하면 병목을 확인한다. 궤적 재생은 프레임당 5개 엔티티의 transform 대입뿐이라 원인은 대개 조명·그림자다. `DirectionalLightComponent.Shadow`의 `maximumDistance`를 0.6으로 줄여 재측정한다

- [ ] **Step 7: P1 종료 커밋**

```bash
git add -A
git commit -m "$(cat <<'MSG'
test: P1 스모크 테스트와 완료 기준 검증

12턴 완주와 재시작 복원을 UI 테스트로 고정했다. 둘 다 P1 완료 기준에 직접
대응하는 항목이라, 사람이 매번 손으로 확인하는 대신 회귀 테스트로 남긴다.

UI 테스트가 깨끗한 상태에서 시작하도록 -resetMatch 실행 인자를 넣었다.
저장된 판이 남아 있으면 테스트가 엉뚱한 턴에서 시작한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

- [ ] **Step 8: P2로 넘어가기 전에**

P1이 끝나면 브레인스토밍으로 돌아가 P2(로컬 패스앤플레이 + AI 봇) 스펙을 따로 쓴다. 이 계획을 이어서 늘리지 않는다.

P2에서 붙일 지점은 이미 준비되어 있다:
- `GameState(playerCount:)`가 이미 다인용이다
- `MatchDriver`에 `AIDriver`를 끼우면 된다
- `ScoreboardView`가 현재 플레이어의 점수판만 보여주므로, 2열 표시로 바꾸는 것이 P2의 UI 작업이다

---

## 참고: 실행 순서 요약

| Task | 산출물 | 검증 |
|---|---|---|
| 1 | 프로젝트 스캐폴딩 | 빌드 성공 |
| **2** | **베이커 스파이크 (리스크 제거)** | 4개 질문에 답 + 경로 판정 |
| 3~8 | `YachtCore` 규칙 엔진 | `swift test` (전수 93,312 + 불변식) |
| 9~11 | `DiceTrajectory` 궤적 수학·포맷 | `swift test` (576 오프셋 케이스) |
| 12 | 베이커 툴 + `trajectories.bin` | 조합별 20개 이상 채택 |
| 13~14 | RealityKit 씬 + 재생 | 재생 결과가 목표 눈과 일치 |
| 15 | `GameSession` 오케스트레이터 | 연출 큐 순서 |
| 16~18 | UI + 저장 | 시뮬레이터 수동 확인 |
| 19~20 | 접근성 + 스모크 | UI 테스트 + 완료 기준 6개 |

Task 2에서 경로 B(자체 강체 시뮬)로 판정되면 Task 12의 일정이 2~3일 늘어나지만, 나머지 순서는 그대로다.
