# Yacht Dice P4 — 시각 디자인, 피드백, 아이콘 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 모든 화면이 3D 트레이와 같은 "보드게임 테이블" 재질 언어를 쓰고, 굴림·기록에 햅틱·사운드·애니메이션이 붙고, 아이콘이 그 분위기를 담는다.

**Architecture:** `App/Design/`에 `Theme`(환경 값), 표면 수정자, 절차적 질감 캐시를 두고 뷰는 토큰만 쓴다. 피드백은 `FeedbackCoordinator`가 `GameSession`의 콜백을 구독해 `Haptics`·`SoundPlayer`로 보낸다. `GameSession`은 UIKit·AVFoundation을 모른다. 아이콘은 생성 스크립트를 고친다.

**Tech Stack:** SwiftUI, UIKit 햅틱, AVFoundation(AVAudioEngine), CoreGraphics, Swift Testing, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-07-yacht-dice-p4-visual-design.md`

## Global Constraints

- P2 계획의 전역 제약(Swift 6 strict concurrency, xcodegen, 저장소 밖 derivedData, 커밋 규칙, 시뮬레이터 id `64A5E02A-510C-4E97-AFF0-5BB8AFA368EB`)을 그대로 따른다.
- 접근성 식별자·라벨은 전부 유지한다: `menu.*`, `action.roll`, `action.die.<i>`, `action.assist`, `scoreboard.row.<raw>`, `scoreboard.subtotal`, `scoreboard.total`, `header.turn`, `header.menu`, `header.status`, `players.seat.<i>`, `handoff.start`, `result.total`, `result.rank.<i>`, `result.menu`, `action.newGame`, `online.status`. AccessibilityUITests가 라벨 문구까지 검사한다.
- 글자 대비: `ink`/`paper`, `inkSecondary`/`paper`, `brassInk`/`brass`, `ink`/`ivory`는 4.5:1 이상 (라이트·다크).
- 고정 폰트 크기를 쓰지 않는다. Reduce Motion이면 애니메이션을 끈다.
- 질감·사운드는 외부 파일 없이 코드로 만든다.

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `App/Design/Theme.swift` | 색 토큰, 라이트/다크, 환경 키, 대비 계산 (Task 1) |
| `App/Design/SurfaceTextures.swift` | 종이·가죽·나무 질감 `Image` 캐시 (Task 2) |
| `App/Design/Surfaces.swift` | `.paperCard()`, `.leatherPanel()`, `.brassButton(prominent:)`, `WoodBackground` (Task 2) |
| `App/Design/DieFaceView.swift` | 눈이 찍힌 주사위 면 (Task 3) |
| `App/Views/ActionBarView.swift` | 주사위 면 칩, 황동 Roll (Task 3) |
| `App/Views/ScoreboardView.swift` | 종이 점수표 (Task 4) |
| `App/Views/GameScreen.swift`, `PlayerStrip.swift`, `GameOverBar.swift`, `HandoffOverlay.swift` | 헤더·명패·결과·핸드오프 (Task 5) |
| `App/Views/MenuScreen.swift`, `OnlineMenu.swift`, `App/Views/SettingsSheet.swift` | 메뉴 카드, 설정 (Task 6) |
| `App/Feedback/Haptics.swift`, `SoundSynth.swift`, `SoundPlayer.swift`, `FeedbackCoordinator.swift` | 피드백 (Task 7, 8) |
| `Tools/AppIcon/GenerateAppIcon.swift` | 아이콘 (Task 9) |

---

### Task 1: Theme 토큰과 대비 테스트

**Files:**
- Create: `App/Design/Theme.swift`
- Create: `Tests/YachtDiceTests/ThemeTests.swift`
- Modify: `App/YachtDiceApp.swift` (환경 주입)

**Interfaces:**
```swift
struct Theme: Sendable, Equatable {
    let table, paper, paperLine, leather, ink, inkSecondary, brass, brassInk, success, ivory: Color
    static let light: Theme
    static let dark: Theme
    static func forScheme(_ scheme: ColorScheme) -> Theme
}
extension EnvironmentValues { var theme: Theme }
/// sRGB 0...1 성분. 대비 계산과 테스트에 쓴다.
struct RGB: Equatable, Sendable { let r, g, b: Double; init(hex: UInt32); var color: Color; var luminance: Double }
func contrastRatio(_ a: RGB, _ b: RGB) -> Double
struct ThemePalette { let table, paper, ... : RGB }   // Theme의 원본. Theme.light = Theme(palette: .light)
```

- [ ] **Step 1: 실패하는 테스트**

```swift
import Testing
@testable import YachtDice

@Suite("테마 대비")
struct ThemeTests {
    @Test("본문·보조·황동·상아 조합이 4.5:1 이상이다", arguments: [ThemePalette.light, ThemePalette.dark])
    func 대비(palette: ThemePalette) {
        let pairs: [(String, RGB, RGB)] = [
            ("ink/paper", palette.ink, palette.paper),
            ("inkSecondary/paper", palette.inkSecondary, palette.paper),
            ("brassInk/brass", palette.brassInk, palette.brass),
            ("ink/ivory", palette.ink, palette.ivory),
            ("paper/leather", palette.paper, palette.leather),
        ]
        for (name, a, b) in pairs {
            #expect(contrastRatio(a, b) >= 4.5, "\(name) 대비 \(contrastRatio(a, b))")
        }
    }

    @Test("대비 계산: 흑백은 21, 같은 색은 1")
    func 대비_공식() {
        #expect(abs(contrastRatio(RGB(hex: 0x000000), RGB(hex: 0xFFFFFF)) - 21) < 0.01)
        #expect(abs(contrastRatio(RGB(hex: 0x808080), RGB(hex: 0x808080)) - 1) < 0.001)
    }
}
```

- [ ] **Step 2: 실패 확인** — 컴파일 에러.

- [ ] **Step 3: 구현**

```swift
import SwiftUI

/// sRGB 성분. 테마의 원본이며 대비 계산에 쓴다.
struct RGB: Equatable, Sendable {
    let r: Double, g: Double, b: Double
    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
    /// WCAG 상대 휘도
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}

func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
    let (l1, l2) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
    return (l1 + 0.05) / (l2 + 0.05)
}

struct ThemePalette: Sendable {
    let table, paper, paperLine, leather, ink, inkSecondary, brass, brassInk, success, ivory: RGB

    static let light = ThemePalette(
        table: RGB(hex: 0x5A3A22), paper: RGB(hex: 0xF4EDDC), paperLine: RGB(hex: 0xD8CDB4),
        leather: RGB(hex: 0x6B1E22), ink: RGB(hex: 0x1E1A17), inkSecondary: RGB(hex: 0x6E6255),
        brass: RGB(hex: 0xB8862B), brassInk: RGB(hex: 0x4A3408), success: RGB(hex: 0x2E6B3F),
        ivory: RGB(hex: 0xF7F3EA))
    static let dark = ThemePalette(
        table: RGB(hex: 0x1E140D), paper: RGB(hex: 0x2A211A), paperLine: RGB(hex: 0x3F332A),
        leather: RGB(hex: 0x4A1418), ink: RGB(hex: 0xF1E9D6), inkSecondary: RGB(hex: 0xB8AC98),
        brass: RGB(hex: 0xD3A24A), brassInk: RGB(hex: 0x1E1608), success: RGB(hex: 0x7CC28F),
        ivory: RGB(hex: 0xF7F3EA))
}

struct Theme: Sendable {
    let palette: ThemePalette
    let isDark: Bool
    var table: Color { palette.table.color }
    var paper: Color { palette.paper.color }
    var paperLine: Color { palette.paperLine.color }
    var leather: Color { palette.leather.color }
    var ink: Color { palette.ink.color }
    var inkSecondary: Color { palette.inkSecondary.color }
    var brass: Color { palette.brass.color }
    var brassInk: Color { palette.brassInk.color }
    var success: Color { palette.success.color }
    var ivory: Color { palette.ivory.color }

    static let light = Theme(palette: .light, isDark: false)
    static let dark = Theme(palette: .dark, isDark: true)
    static func forScheme(_ scheme: ColorScheme) -> Theme { scheme == .dark ? .dark : .light }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme.light }
extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// 루트에서 한 번 건다. 시스템 색 구성표를 따라 테마를 고른다.
struct ThemedRoot<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { content.environment(\.theme, Theme.forScheme(scheme)) }
}
```

`YachtDiceApp.body`의 `WindowGroup` 내용을 `ThemedRoot { switch ... }`로 감싼다.

`paper/leather` 조합이 4.5 미만이면(라이트 상아색 vs 버건디는 약 7:1이라 통과, 다크 `#2A211A` vs `#4A1418`은 낮다) 이 조합은 **글자 조합이 아니므로** 테스트에서 뺀다 — 테스트의 `pairs`에서 `paper/leather` 줄을 삭제한다. 나머지 네 조합은 통과해야 하며, 실패하면 팔레트의 해당 색을 어둡게/밝게 조정하고 스펙 §3.1 표도 같이 고친다.

- [ ] **Step 4: 통과 확인** — `-only-testing:YachtDiceTests/ThemeTests`.
- [ ] **Step 5: 커밋** — `feat(design): 테마 토큰과 대비 검사`

---

### Task 2: 질감과 표면 수정자

**Files:**
- Create: `App/Design/SurfaceTextures.swift`
- Create: `App/Design/Surfaces.swift`
- Test: `Tests/YachtDiceTests/SurfaceTexturesTests.swift`

**Interfaces:**
```swift
@MainActor enum SurfaceTextures {
    static var paper: Image { get }     // 512², 회색 결, 투명 배경 (오버레이용)
    static var leather: Image { get }
    static var wood: Image { get }
    nonisolated static func makeGrain(kind: Kind, size: Int) -> CGImage?   // 테스트용
    enum Kind { case paper, leather, wood }
}
extension View {
    func paperCard(padding: CGFloat = 16) -> some View
    func leatherPanel() -> some View
    func brassButton(prominent: Bool = true) -> some View   // 버튼 라벨에 건다
}
struct WoodBackground: View
```

- [ ] **Step 1: 실패하는 테스트**

```swift
import Testing
import CoreGraphics
@testable import YachtDice

@Suite("표면 질감")
struct SurfaceTexturesTests {
    @Test("세 질감이 만들어지고 정사각이며, 알파가 전부 같지 않다(결이 있다)", arguments: [SurfaceTextures.Kind.paper, .leather, .wood])
    func 질감(kind: SurfaceTextures.Kind) throws {
        let image = try #require(SurfaceTextures.makeGrain(kind: kind, size: 64))
        #expect(image.width == 64 && image.height == 64)
        let data = try #require(image.dataProvider?.data as Data?)
        let alphas = Set(stride(from: 3, to: data.count, by: 4).map { data[$0] })
        #expect(alphas.count > 4, "\(kind) 결이 평평하다")
    }
}
```

- [ ] **Step 2: 실패 확인** — 컴파일 에러.

- [ ] **Step 3: 구현**

`SurfaceTextures.swift` — 결은 **알파에** 넣는다. RGB는 중립 회색이고 알파가 노이즈라 어떤 배경 위에 얹어도 그 색의 밝기만 흔든다.

```swift
import SwiftUI
import CoreGraphics

/// 종이·가죽·나무 결. 회색 픽셀의 알파에 노이즈를 넣어 배경색 위에 얹는다.
@MainActor
enum SurfaceTextures {
    enum Kind: CaseIterable { case paper, leather, wood }

    private static var cache: [Kind: Image] = [:]

    static var paper: Image { image(.paper) }
    static var leather: Image { image(.leather) }
    static var wood: Image { image(.wood) }

    private static func image(_ kind: Kind) -> Image {
        if let hit = cache[kind] { return hit }
        let made = makeGrain(kind: kind, size: 512).map { Image(decorative: $0, scale: 1) } ?? Image(systemName: "square")
        cache[kind] = made
        return made
    }

    nonisolated static func makeGrain(kind: Kind, size: Int) -> CGImage? {
        var canvas = PixelCanvas(width: size, height: size)
        canvas.fill { u, v in
            let n: Float
            switch kind {
            case .paper:
                n = Noise.fbm(u * 64, v * 64, period: 64, octaves: 3, seed: 101)
            case .leather:
                n = Noise.fbm(u * 24, v * 24, period: 24, octaves: 3, seed: 103) * 0.7
                    + Noise.value(u * 160, v * 160, period: 160, seed: 107) * 0.3
            case .wood:
                let wobble = Noise.fbm(u * 2, v * 2, period: 2, octaves: 3, seed: 109) * 2.4
                let rings = (v * 7 + wobble).truncatingRemainder(dividingBy: 1)
                n = smoothstep(0, 0.45, rings) * (1 - smoothstep(0.55, 1, rings)) * 0.7
                    + Noise.value(u * 40, v * 400, period: 400, seed: 113) * 0.3
            }
            // 밝은 점은 흰색, 어두운 점은 검정으로 — 알파는 결의 세기
            let bright = n > 0.5
            return SIMD4(bright ? 1 : 0, bright ? 1 : 0, bright ? 1 : 0, abs(n - 0.5) * 2)
        }
        return canvas.makeImage()
    }
}
```

`Surfaces.swift`:

```swift
import SwiftUI

struct PaperCard: ViewModifier {
    @Environment(\.theme) private var theme
    let padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(theme.paper)
                    SurfaceTextures.paper.resizable(resizingMode: .tile)
                        .opacity(theme.isDark ? 0.05 : 0.08)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    RoundedRectangle(cornerRadius: 14).strokeBorder(theme.paperLine, lineWidth: 1)
                }
                .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.18), radius: 8, y: 3)
            }
    }
}

struct LeatherPanel: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content.background {
            ZStack {
                theme.leather
                SurfaceTextures.leather.resizable(resizingMode: .tile).opacity(0.12)
                RadialGradient(colors: [.clear, .black.opacity(0.35)], center: .center, startRadius: 40, endRadius: 400)
            }
        }
    }
}

struct BrassButton: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let prominent: Bool
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(prominent ? theme.brassInk : theme.brass)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                if prominent {
                    Capsule().fill(LinearGradient(colors: [theme.brass.opacity(1), theme.brass.opacity(0.78)],
                                                  startPoint: .top, endPoint: .bottom))
                    Capsule().strokeBorder(theme.brassInk.opacity(0.35), lineWidth: 1)
                } else {
                    Capsule().strokeBorder(theme.brass, lineWidth: 1.5)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

extension View {
    func paperCard(padding: CGFloat = 16) -> some View { modifier(PaperCard(padding: padding)) }
    func leatherPanel() -> some View { modifier(LeatherPanel()) }
    func brassButton(prominent: Bool = true) -> some View { modifier(BrassButton(prominent: prominent)) }
}

/// 화면 바탕. 호두나무 테이블.
struct WoodBackground: View {
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack {
            theme.table
            SurfaceTextures.wood.resizable(resizingMode: .tile).opacity(theme.isDark ? 0.22 : 0.3)
            RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 120, endRadius: 700)
        }
        .ignoresSafeArea()
    }
}
```

`Image(decorative:scale:)`는 `CGImage`를 받는다. `.resizable(resizingMode: .tile)`로 반복한다.

- [ ] **Step 4: 통과 확인**, 앱 빌드.
- [ ] **Step 5: 커밋** — `feat(design): 종이·가죽·나무 표면과 바탕`

---

### Task 3: DieFaceView와 액션 바

**Files:**
- Create: `App/Design/DieFaceView.swift`
- Modify: `App/Views/ActionBarView.swift`
- Test: `Tests/YachtDiceTests/DieFaceViewTests.swift`

**Interfaces:**
```swift
/// 상아색 주사위 면. value 0이면 빈 면(굴리기 전).
struct DieFaceView: View { let value: Int; var isHeld: Bool = false; var size: CGFloat = 48 }
extension DieFaceView { static func pipPoints(for value: Int) -> [CGPoint] }   // 0 → [], 1...6 → DiePipTexture.pipLayout
```

- [ ] **Step 1: 실패하는 테스트**

```swift
import Testing
@testable import YachtDice

@Suite("주사위 면 뷰")
struct DieFaceViewTests {
    @Test("눈 개수", arguments: 0...6)
    func 눈(value: Int) {
        #expect(DieFaceView.pipPoints(for: value).count == value)
    }
}
```

- [ ] **Step 2: 실패 확인**, **Step 3: 구현**

```swift
import SwiftUI

struct DieFaceView: View {
    @Environment(\.theme) private var theme
    let value: Int
    var isHeld: Bool = false
    var size: CGFloat = 48

    static func pipPoints(for value: Int) -> [CGPoint] {
        (1...6).contains(value) ? DiePipTexture.pipLayout(for: value) : []
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(LinearGradient(colors: [theme.ivory, theme.ivory.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.25), radius: isHeld ? 5 : 2, y: isHeld ? 4 : 1)
            RoundedRectangle(cornerRadius: size * 0.2)
                .strokeBorder(isHeld ? theme.brass : Color.black.opacity(0.12), lineWidth: isHeld ? 2.5 : 1)
            GeometryReader { geo in
                ForEach(Array(Self.pipPoints(for: value).enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color(.sRGB, red: 0.09, green: 0.08, blue: 0.09))
                        .frame(width: size * 0.17, height: size * 0.17)
                        .position(x: point.x * geo.size.width, y: point.y * geo.size.height)
                }
            }
            .padding(size * 0.02)
        }
        .frame(width: size, height: size)
        .opacity(value == 0 ? 0.55 : 1)
        .offset(y: isHeld ? -3 : 0)
    }
}
```

`ActionBarView`: 칩 라벨을 `DieFaceView(value: value, isHeld: isHeld, size: 48)`로 바꾼다 (기존 `.frame/.background/.overlay/.clipShape` 제거). 접근성 수정자는 그대로. Roll 버튼 라벨을:

```swift
HStack(spacing: 8) {
    Image(systemName: "dice.fill")
    Text("Roll")
    HStack(spacing: 3) {
        ForEach(0..<YachtCore.maxRollsPerTurn, id: \.self) { i in
            Circle().fill(i < state.rollsRemaining ? theme.brassInk : theme.brassInk.opacity(0.25))
                .frame(width: 6, height: 6)
        }
    }
}
.brassButton(prominent: true)
```
로 바꾸고 `.buttonStyle(.plain)`으로 둔다(`.borderedProminent` 제거). `accessibilityLabel`은 그대로 "주사위 굴리기, N회 남음". Assist 토글은 `.toggleStyle(.button)` 대신 `Button`으로 만들어 라벨을 `.brassButton(prominent: session.assistEnabled)`로 감싼다. `accessibilityIdentifier("action.assist")`, `accessibilityLabel("예상 점수 표시")`, `accessibilityValue(session.assistEnabled ? "켜짐" : "꺼짐")`. 칩 애니메이션: `withAnimation(reduceMotion ? nil : .spring(duration: 0.25))`로 `isHeld` 변화.

- [ ] **Step 4: 통과 확인** — 단위 테스트 전체 + `AccessibilityUITests` (칩 라벨 "주사위 1, 아직 안 굴림" 유지 확인).
- [ ] **Step 5: 커밋** — `feat(ui): 상아색 주사위 면 칩과 황동 Roll 버튼`

---

### Task 4: 종이 점수표

**Files:**
- Modify: `App/Views/ScoreboardView.swift`

동작 (기존 식별자·라벨 유지):
- 전체를 `.paperCard(padding: 12)`로 감싼다. 폰트는 `.system(.subheadline, design: .rounded)`.
- 행: 이름(`ink`) — 점선 리더(`Rectangle().fill(theme.paperLine).frame(height: 1)`에 `.mask`로 점선 대신, 간단히 `Line`을 `StrokeStyle(dash: [2, 3])`로) — 점수.
  - 기록: `Text("\(recorded)")` `.fontWeight(.bold)` `.foregroundStyle(theme.ink)` + `.contentTransition(.numericText())` + `.animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: recorded)`.
  - 미리보기: `Text("\(preview)")` `.foregroundStyle(theme.brassInk)` `.padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(theme.brass))`.
  - 빈 칸: `Text("–").foregroundStyle(theme.inkSecondary)`.
- 소계 행: 왼쪽 "보너스까지", 가운데 미니 바(`Capsule` 배경 `paperLine`, 채움은 `min(1, subtotal/63)` 비율, 색은 달성 시 `success` 아니면 `brass`), 오른쪽 "n/63" 또는 "+35". 달성 순간 `.overlay(Capsule().fill(theme.brass).opacity(flash))`를 0.6초 애니메이션.
- 총점 행: 위에 2pt `ink` 괘선, "Total" 세리프, 숫자 `.title3.rounded.bold` + numericText 전환.
- 구분선은 `Divider` 대신 `theme.paperLine` 1pt.

- [ ] **Step 1: 구현** (뷰 변경. 접근성 라벨 로직은 손대지 않는다)
- [ ] **Step 2: 단위 테스트 + `AccessibilityUITests` 통과 확인**
- [ ] **Step 3: 커밋** — `feat(ui): 종이 점수표`

---

### Task 5: 게임 헤더, 명패, 결과, 핸드오프

**Files:**
- Modify: `App/Views/GameScreen.swift`, `App/Views/PlayerStrip.swift`, `App/Views/GameOverBar.swift`, `App/Views/HandoffOverlay.swift`
- Create: `App/Design/TurnProgress.swift`

동작:
- `GameScreen`: 바깥을 `ZStack { WoodBackground(); VStack {...} }`. 헤더 HStack에 `.leatherPanel()`, 글자 `theme.ivory`. 가운데 `VStack { Text("TURN \(turn) / 12").font(.caption.smallCaps()); TurnProgress(current: turn, total: 12) }` — 기존 `header.turn` 식별자·라벨 텍스트는 유지해야 하므로 `Text("Turn \(turnIndex)/\(turnCount)")`는 그대로 두고 `TurnProgress`만 그 아래에 붙인다(라벨이 "Turn 1/12"인지 UI 테스트가 본다).
  `TurnProgress`: 12개 `Capsule` (채운 것은 `brass`, 나머지는 `ivory.opacity(0.25)`), 높이 4.
- 점수판 `ScrollView`의 배경은 `WoodBackground`가 비친다. 점수판 카드에 `.padding(.horizontal, 12)`.
- `PlayerStrip`: 명패 = `paper` 배경, `brass` 1.5pt 테두리, 현재 차례는 `brass` 배경에 `brassInk` 글자. 아닌 좌석은 `paper`/`ink`.
- `GameOverBar`: `.paperCard()`. 순위 행 1위에 `Image(systemName: "trophy.fill").foregroundStyle(theme.brass)`. 버튼은 `.brassButton(prominent: false)`("메뉴로"), `.brassButton(prominent: true)`("새 게임"). 식별자 유지.
- `HandoffOverlay`: `ZStack { theme.table.opacity(0.92); WoodBackground().opacity(0.6); VStack {...} }`, 이름은 세리프 `.largeTitle`, "시작"은 `.brassButton()`.

- [ ] **Step 1: 구현**
- [ ] **Step 2: 단위 + 전체 UI 테스트 통과** (특히 `FullGameUITests`, `MenuUITests`)
- [ ] **Step 3: 커밋** — `feat(ui): 가죽 헤더, 황동 명패, 종이 결과 카드`

---

### Task 6: 메뉴 카드와 설정

**Files:**
- Modify: `App/Views/MenuScreen.swift`, `App/Views/OnlineMenu.swift`
- Create: `App/Views/SettingsSheet.swift`, `App/Design/ModeCard.swift`
- Create: `App/Feedback/FeedbackSettings.swift` (`@AppStorage` 키 상수)
- Test: `Tests/YachtDiceUITests/MenuUITests.swift` (설정 시트)

**Interfaces:**
```swift
enum FeedbackSettings {
    static let soundKey = "sound.enabled"
    static let hapticsKey = "haptics.enabled"
    static var soundEnabled: Bool { UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true }
    static var hapticsEnabled: Bool { ... ?? true }
}
struct ModeCard: View { let icon: String; let title: String; let subtitle: String; var accessory: AnyView? ; let action: () -> Void }
```

동작:
- `MenuScreen`: `NavigationStack` 안 `ScrollView` + `WoodBackground` (List 제거). 제목 로크업: `HStack { DieFaceView(value: 5, size: 34); DieFaceView(value: 2, size: 34) }` + `Text("요트 다이스").font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(theme.ivory)`.
- 이어하기 카드(`.paperCard()`): 모드 제목, `ProgressView(value: Double(turnIndex - 1) / 12)` tint `brass`, 버튼 "이어하기" `.brassButton()` 식별자 `menu.resume`.
- 모드 카드 4개 `ModeCard`: 카드 전체가 버튼(식별자는 카드에). 컴퓨터 카드는 펼침 상태에서 카드 아래에 난이도 칩 3개(`Button` + `.brassButton(prominent: false)`, 식별자 `menu.bot.<raw>`). 로컬은 기존 시트. 온라인은 `NavigationLink`.
- 툴바 톱니(`menu.settings`) → `SettingsSheet`: `Toggle("사운드", isOn:)`(`settings.sound`), `Toggle("햅틱", isOn:)`(`settings.haptics`) — `@AppStorage(FeedbackSettings.soundKey) var soundEnabled = true`.
- `OnlineMenu`: List → ScrollView + 카드. 식별자 `online.status`, `online.newMatch` 유지.
- UI 테스트 추가:

```swift
    @MainActor
    func test_설정_시트가_열린다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch"]
        app.launch()
        let settings = app.buttons["menu.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.switches["settings.sound"].waitForExistence(timeout: 5), "사운드 토글이 없다")
        XCTAssertTrue(app.switches["settings.haptics"].exists, "햅틱 토글이 없다")
    }
```

- [ ] **Step 1: 구현**
- [ ] **Step 2: 전체 UI 테스트 통과** (`menu.solo` 등이 카드 버튼으로 찾히는지)
- [ ] **Step 3: 커밋** — `feat(ui): 테이블 위 메뉴 카드와 설정`

---

### Task 7: 햅틱과 사운드 합성

**Files:**
- Create: `App/Feedback/Haptics.swift`, `App/Feedback/SoundSynth.swift`, `App/Feedback/SoundPlayer.swift`
- Test: `Tests/YachtDiceTests/FeedbackTests.swift`

**Interfaces:**
```swift
enum HapticKind: Equatable { case impactLight, impactMedium, impactHeavy, impactRigid, selection, success }
func hapticKind(forCollisionIntensity intensity: Float) -> HapticKind   // 순수
@MainActor final class Haptics { static let shared: Haptics; func play(_ kind: HapticKind) }   // FeedbackSettings.hapticsEnabled 확인
enum SoundSynth {
    static let sampleRate: Double = 44_100
    static func tock(intensity: Float) -> [Float]
    static func tick() -> [Float]
    static func stamp() -> [Float]
    static func chime() -> [Float]
}
@MainActor final class SoundPlayer { static let shared: SoundPlayer; func play(_ samples: [Float]) }   // 설정 확인, 엔진 실패는 무시
```

- [ ] **Step 1: 실패하는 테스트**

```swift
import Testing
@testable import YachtDice

@Suite("피드백")
struct FeedbackTests {
    @Test("충돌 세기 → 햅틱 종류 경계")
    func 햅틱_매핑() {
        #expect(hapticKind(forCollisionIntensity: 0.0) == .impactLight)
        #expect(hapticKind(forCollisionIntensity: 0.34) == .impactLight)
        #expect(hapticKind(forCollisionIntensity: 0.35) == .impactMedium)
        #expect(hapticKind(forCollisionIntensity: 0.69) == .impactMedium)
        #expect(hapticKind(forCollisionIntensity: 0.7) == .impactHeavy)
        #expect(hapticKind(forCollisionIntensity: 1.0) == .impactHeavy)
    }

    @Test("합성 소리는 길이가 맞고 진폭이 0 초과 1 이하다")
    func 사운드_버퍼() {
        let cases: [(String, [Float], Double)] = [
            ("tock", SoundSynth.tock(intensity: 1), 0.06),
            ("tick", SoundSynth.tick(), 0.025),
            ("stamp", SoundSynth.stamp(), 0.12),
            ("chime", SoundSynth.chime(), 0.4),
        ]
        for (name, samples, seconds) in cases {
            #expect(samples.count == Int(seconds * SoundSynth.sampleRate), "\(name) 길이 \(samples.count)")
            let peak = samples.map(abs).max() ?? 0
            #expect(peak > 0.05 && peak <= 1.0, "\(name) 최대 진폭 \(peak)")
        }
    }

    @Test("약한 충돌은 조용하다")
    func 세기_반영() {
        let loud = SoundSynth.tock(intensity: 1).map(abs).max()!
        let soft = SoundSynth.tock(intensity: 0.2).map(abs).max()!
        #expect(soft < loud * 0.5)
    }
}
```

- [ ] **Step 2: 실패 확인**, **Step 3: 구현**

```swift
// Haptics.swift
import UIKit

enum HapticKind: Equatable { case impactLight, impactMedium, impactHeavy, impactRigid, selection, success }

func hapticKind(forCollisionIntensity intensity: Float) -> HapticKind {
    if intensity < 0.35 { return .impactLight }
    if intensity < 0.7 { return .impactMedium }
    return .impactHeavy
}

@MainActor
final class Haptics {
    static let shared = Haptics()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    func play(_ kind: HapticKind) {
        guard FeedbackSettings.hapticsEnabled else { return }
        switch kind {
        case .impactLight: light.impactOccurred()
        case .impactMedium: medium.impactOccurred()
        case .impactHeavy: heavy.impactOccurred()
        case .impactRigid: rigid.impactOccurred()
        case .selection: selection.selectionChanged()
        case .success: notification.notificationOccurred(.success)
        }
    }
}
```

```swift
// SoundSynth.swift
import Foundation

/// 외부 파일 없이 짧은 효과음을 합성한다. 결정적이라 테스트할 수 있다.
enum SoundSynth {
    static let sampleRate: Double = 44_100

    /// 주사위가 부딪히는 "톡". 노이즈 버스트 + 낮은 톤 한 주기, 지수 감쇠.
    static func tock(intensity: Float) -> [Float] {
        let n = Int(0.06 * sampleRate)
        var rng = LCG(seed: 7)
        return (0..<n).map { i in
            let t = Float(i) / Float(sampleRate)
            let env = exp(-t * 70)
            let noise = rng.nextFloat() * 2 - 1
            let tone = sin(2 * .pi * 180 * t)
            return (noise * 0.6 + tone * 0.4) * env * (0.15 + 0.85 * intensity) * 0.9
        }
    }

    /// 고정 토글 "틱". 2kHz 클릭.
    static func tick() -> [Float] {
        let n = Int(0.025 * sampleRate)
        return (0..<n).map { i in
            let t = Float(i) / Float(sampleRate)
            return sin(2 * .pi * 2000 * t) * exp(-t * 200) * 0.5
        }
    }

    /// 기록 "탁". 노이즈 버스트 + 120Hz.
    static func stamp() -> [Float] {
        let n = Int(0.12 * sampleRate)
        var rng = LCG(seed: 11)
        return (0..<n).map { i in
            let t = Float(i) / Float(sampleRate)
            let noise = rng.nextFloat() * 2 - 1
            return (noise * 0.5 * exp(-t * 90) + sin(2 * .pi * 120 * t) * 0.5 * exp(-t * 25)) * 0.8
        }
    }

    /// 야추·보너스 "딩". C5-E5-G5 감쇠.
    static func chime() -> [Float] {
        let n = Int(0.4 * sampleRate)
        let freqs: [Float] = [523.25, 659.25, 783.99]
        return (0..<n).map { i in
            let t = Float(i) / Float(sampleRate)
            let sum = freqs.enumerated().reduce(Float(0)) { acc, f in
                acc + sin(2 * .pi * f.element * t) * exp(-t * (4 + Float(f.offset)))
            }
            return sum / 3 * 0.8
        }
    }

    /// 결정적 난수. 테스트가 같은 파형을 기대할 수 있게.
    struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func nextFloat() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(state >> 40) / Float(1 << 24)
        }
    }
}
```

```swift
// SoundPlayer.swift
import AVFoundation

/// 합성한 버퍼를 재생한다. 엔진이 못 뜨면 조용히 포기한다 — 소리 없는 게임이 죽는 게임보다 낫다.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var ready = false

    private func startIfNeeded() {
        guard !ready else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.sampleRate, channels: 1)!
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            try engine.start()
            node.play()
            self.format = format
            ready = true
        } catch {
            ready = false
        }
    }

    func play(_ samples: [Float]) {
        guard FeedbackSettings.soundEnabled else { return }
        startIfNeeded()
        guard ready, let format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (i, s) in samples.enumerated() { channel[i] = s }
        node.scheduleBuffer(buffer, completionHandler: nil)
    }
}
```

`FeedbackSettings`는 Task 6에서 만들었다. Task 7을 먼저 하면 Task 6의 `FeedbackSettings.swift`를 이 태스크에서 만든다.

- [ ] **Step 4: 통과 확인**, **Step 5: 커밋** — `feat(feedback): 햅틱 매핑과 합성 효과음`

---

### Task 8: FeedbackCoordinator — 세션과 연결

**Files:**
- Create: `App/Feedback/FeedbackCoordinator.swift`
- Modify: `App/Game/GameSession.swift` (콜백 추가: `onCommitted: ((ScoreCategory, Int, Bool) -> Void)?` — 카테고리, 점수, 보너스가 이번에 달성됐는가; `onHoldToggled: (() -> Void)?`; `onRollStarted: ((Int) -> Void)?` 프레임레이트)
- Modify: `App/Views/GameScreen.swift` (`.task { coordinator.attach(session) }`)
- Test: `Tests/YachtDiceTests/GameSessionTests.swift` (콜백이 불린다)

동작:
- `GameSession.performRoll`: `stage.roll` 호출 직전에 `onRollStarted?(frameRate)`… 큐는 굴림이 끝난 뒤 돌아오므로 시각 예약이 안 된다. 대신 `DiceStage.roll`에 `onCue: ((CollisionCue) -> Void)?` 파라미터를 더해 재생 루프에서 해당 프레임에 도달할 때 부른다(리드인 뒤 프레임 인덱스 == cue.frame). `GameSession.onCollisionCue: ((CollisionCue) -> Void)?`를 `stage.roll(..., onCue: { self.onCollisionCue?($0) })`로 연결. 기존 `onCollisionCues`(끝난 뒤 전체)는 유지.
- `commitEvents` 뒤 `.commit` 케이스에서: `let bonusBefore = card.upperBonus` 저장 → 적용 후 `bonusAfter > 0 && bonusBefore == 0`이면 `bonusReached = true`. `onCommitted?(category, points, bonusReached)`.
- `.toggleHold` 뒤 `onHoldToggled?()`.
- `FeedbackCoordinator.attach(_ session:)`: 
  - `onCollisionCue` → `Haptics.shared.play(hapticKind(forCollisionIntensity:))`, `SoundPlayer.shared.play(SoundSynth.tock(intensity:))`
  - `onHoldToggled` → `.selection`, `tick()`
  - `onCommitted` → `.impactRigid`, `stamp()`; 야추(`category == .yacht && points == 50`) 또는 보너스 달성이면 `.success`, `chime()` 추가.
- 테스트:

```swift
    @Test("기록 콜백이 카테고리·점수·보너스 달성 여부를 준다")
    func 기록_콜백() async throws {
        let session = try makeSession(script: [[6, 6, 6, 6, 6]])
        let box = CommitBox()
        session.onCommitted = { box.record($0, $1, $2) }
        await session.send(.roll)
        await session.send(.commit(.yacht))
        #expect(box.last?.0 == .yacht && box.last?.1 == 50 && box.last?.2 == false)
    }
    final class CommitBox: @unchecked Sendable {
        var last: (ScoreCategory, Int, Bool)?
        func record(_ c: ScoreCategory, _ p: Int, _ b: Bool) { last = (c, p, b) }
    }
```

DiceStage 테스트: `roll(..., onCue:)`가 큐 개수만큼 불린다 (skipAnimation일 때는 한 번에 전부).

- [ ] **Step 1: 실패하는 테스트**, **Step 2: 실패 확인**, **Step 3: 구현**, **Step 4: 통과 확인**
- [ ] **Step 5: 커밋** — `feat(feedback): 굴림·고정·기록에 햅틱과 소리를 붙인다`

---

### Task 9: 앱 아이콘

**Files:**
- Modify: `Tools/AppIcon/GenerateAppIcon.swift`
- Modify: `App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (재생성)

- [ ] **Step 1: 스크립트 수정** — 스펙 §6: 호두나무 테두리(폭 6%, 결 줄무늬는 밝기 ±6% 가로 줄 40개), 안쪽 버건디 방사 그러데이션(중앙 `#8A2A2A` → 가장자리 `#4A1014`) + 미세 노이즈(각 픽셀 ±3%는 비용이 크니 200개 반투명 원으로 대체), 주사위 두 개(변 34%, 각각 중심 (0.38, 0.56)에 −12°, (0.64, 0.44)에 +9°, 눈 5와 2, 그림자 blur 4%). 60px 축소본도 `AppIcon-60-preview.png`로 저장(커밋하지 않는다).
- [ ] **Step 2: 실행** — `swift Tools/AppIcon/GenerateAppIcon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` 뒤 두 이미지를 눈으로 확인. 60px에서 주사위 두 개가 구분되어야 한다.
- [ ] **Step 3: 커밋** — `feat(icon): 호두나무 테두리와 가죽 위 주사위 두 개`

---

### Task 10: 스크린샷 검토와 문서

- [ ] **Step 1: 전체 테스트** — 앱 스킴 전체 + 패키지 3개.
- [ ] **Step 2: 라이트·다크 스크린샷** — 임시 UI 테스트로 메뉴·게임(굴린 뒤)·결과 화면을 라이트와 다크(`app.launchArguments += ["-AppleInterfaceStyle", "Dark"]`)로 캡처해 사용자에게 보낸다. 다크 인자가 안 먹으면 `xcrun simctl ui <id> appearance dark`로 바꾸고 다시 캡처한다.
- [ ] **Step 3: README** — 구조 표에 `App/Design`, `App/Feedback` 추가. 스펙 상태 갱신.
- [ ] **Step 4: 커밋** — `docs: P4 완료 반영`
