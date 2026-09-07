# 요트 다이스 (Yacht Dice)

닌텐도 『세계의 게임 대전 51』의 Yacht Dice를 레퍼런스로 삼은 iOS 네이티브 야추 다이스 게임으로, RealityKit 3D 주사위와 이벤트 소싱 규칙 엔진 위에 세로 화면 전용으로 만들었으며 혼자 연습, 컴퓨터 대전(3단계), 같은 기기 2~4인, Game Center 턴제 온라인 대전을 지원한다.

## 빌드

Xcode 프로젝트는 저장소에 두지 않고 [XcodeGen](https://github.com/yonaskolb/XcodeGen)이 `project.yml`에서 만들며, Xcode 26과 iOS 18 이상, Swift 6 strict concurrency를 요구한다.

```sh
brew install xcodegen
xcodegen generate
open YachtDice.xcodeproj
```

스킴 `YachtDice`는 iOS 앱과 단위·UI 테스트를, 스킴 `TrajectoryBaker`는 궤적을 굽는 macOS 툴을 빌드하며, 앱 테스트는 시뮬레이터에서 돌리고 패키지 테스트는 Xcode 없이도 돈다.

```sh
xcodebuild -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

swift test --package-path Packages/YachtCore
swift test --package-path Packages/DiceTrajectory
swift test --package-path Packages/YachtBot
```

## 구조

```
SwiftUI Views ──관찰──▶ GameSession  (@Observable, @MainActor)
                          ├─▶ YachtCore.GameState   (순수 규칙, 의존성 0)
                          ├─▶ MatchDriver           (눈의 출처)
                          ├─▶ TurnTransport         (온라인 로그 전송)
                          └─▶ DiceStage             (RealityKit 연출)
```

| 경로 | 역할 |
|---|---|
| `Packages/YachtCore` | `Intent`(하고 싶은 것)와 `Event`(확정된 사실)를 분리한 이벤트 소싱 규칙 엔진으로, UI와 3D를 모른다. |
| `Packages/DiceTrajectory` | 구운 궤적 자료구조, 바이너리 포맷, 정육면체 대칭군 회전 오프셋, 트레이 치수, 궤적 검증기. |
| `Packages/YachtBot` | 난이도 3단계의 컴퓨터 상대로, 손패 기대값을 전수 계산하며 YachtCore만 의존한다. |
| `App/Game` | 유일한 오케스트레이터 `GameSession`, `MatchDriver`, 진행 저장 `MatchStore`. |
| `App/Scene3D` | RealityKit 씬으로, `DiceSceneBuilder`가 지오메트리를, `SceneMaterials`가 절차적 PBR 텍스처를, `SceneLighting`이 조명과 IBL을, `DiceStage`가 궤적 재생을 맡는다. |
| `App/Views` | 시작 메뉴, 참가자 띠, 점수판, 액션 바, 결과 카드 등 세로 화면 UI. |
| `App/Design` | 라이트/다크 테마 토큰과 대비 검사, 종이·가죽·나무 표면, 주사위 면 뷰, 메뉴 카드. |
| `App/Feedback` | 햅틱 매핑, 외부 파일 없는 합성 효과음, 세션 콜백을 잇는 `FeedbackCoordinator`, 설정 키. |
| `App/Online` | `TurnTransport` 프로토콜, 테스트용 메모리 전송, Game Center 어댑터, 매치메이커로, GameKit은 여기서만 import한다. |
| `App/AppContainer.swift` | 앱 조립, 메뉴 상태, 저장된 판 복원, 온라인 매치 열기. |
| `Tools/TrajectoryBaker` | 물리 시뮬로 궤적을 굽는 macOS 앱으로, 결과는 `App/Resources/trajectories.bin`에 들어간다. |
| `docs/superpowers` | 설계 스펙과 구현 계획. |

### 주사위는 물리를 돌리지 않는다

결과(눈)를 먼저 정하고 물리는 연출만 하도록, 베이커가 미리 구운 궤적을 재생하되 각 주사위의 회전에 정육면체 대칭군의 원소를 곱해 원하는 눈이 위를 향하게 하며, 회전 대칭이라 매 프레임 주사위가 점유하는 공간이 원본과 완전히 같으므로 이것은 눈속임이 아니라 동일한 궤적이다. 이 덕분에 온라인 대전에서 두 화면이 프레임 단위로 같고 기기에서 물리를 돌리지 않으며, 근거는 `docs/superpowers/specs/2026-08-28-yacht-dice-p1-core-3d-design.md` §7에 있다.

### 화면도 테이블 위에 있다

메뉴·점수판·버튼은 3D 트레이와 같은 재질 언어(호두나무·버건디 가죽·상아색 종이·황동)를 쓰며, 색은 `App/Design/Theme.swift`의 토큰뿐이고 글자 조합의 대비는 테스트가 4.5:1 이상으로 강제한다. 나무·가죽 배경은 3D 트레이의 알베도 생성기를 그대로 2x로 깐 것이고, 앱 아이콘은 `swift Tools/AppIcon/GenerateAppIcon.swift <출력.png>`로 다시 그린다.

### 3D 에셋은 전부 코드다

가죽·호두나무·주사위 눈은 `App/Scene3D/ProceduralTexture.swift`의 결정적 노이즈로 앱 시작 시 그리므로 외부 텍스처와 모델 파일이 없으며, 트레이의 보이는 모양(모서리 라운드, 선반 패드)은 자유롭게 바꿔도 되지만 주사위가 닿는 면의 위치(`TrayGeometry`)는 구운 궤적과 맞물려 있어 바꾸면 다시 구워야 한다.

## 온라인 대전을 실기기에서 확인하려면

매치 데이터는 `MatchLog` JSON 그대로이고 상대가 보낸 로그는 `GameState.canApply`로 검증한 뒤 재생하며, 주사위는 각 클라이언트가 굴리므로 조작된 클라이언트의 "운 좋은 눈"은 막지 못한다(스펙 P2/P3 §7.4). 자동화된 테스트는 메모리 전송으로 두 세션이 12턴을 완주하는 것, 조작 로그 거부, 매치 열기(새 매치·이어하기·상대 차례·손상 데이터·중복 열기)까지 다루고, Game Center 자체(인증, 매치메이커, 턴 이벤트 전달)는 실기기에서만 확인할 수 있다.

실제 매치는 Apple Developer 포털에서 앱 ID `com.leejungheon.yachtdice.YachtDice`에 Game Center 기능을 켜고, App Store Connect의 앱 레코드에서 Game Center를 활성화하고, 실기기 두 대(A·B)에 서로 다른 Apple ID(샌드박스 테스터 가능)로 Game Center에 로그인해야 동작하며, 그 뒤 다음 순서로 확인한다.

1. A에서 메뉴 → 온라인 대전을 열어 상태가 "…으로 로그인됨"인지 보고, 아니면 설정 앱에서 Game Center에 로그인한다.
2. A에서 새 매치 찾기로 자동 매칭하거나 B를 초대하면 게임 화면이 열리고 상대 명패에 "상대"(자동 매칭) 또는 B의 이름이 보여야 한다.
3. A가 굴리고 기록하면 헤더가 "상대 차례"로 바뀌고 Roll이 잠겨야 한다.
4. B가 알림을 탭하거나 온라인 대전의 진행 중인 매치에서 열면 A의 주사위 눈과 점수가 그대로 보이고 B의 차례가 열려야 한다.
5. B가 한 턴을 두면 A의 화면에 B의 굴림이 3D로 재생되고 A의 차례가 열려야 한다.
6. 앱을 완전히 종료한 뒤 다시 열어 진행 중인 매치를 열면 같은 상태여야 한다.
7. 12턴을 끝내면 양쪽 결과 카드의 순위가 같고 Game Center 매치 목록에서 사라져야 한다.
8. 기내 모드로 상대 턴을 기다리다 해제하면 턴 이벤트가 도착해야 한다.

## 궤적 다시 굽기

`TrayGeometry`나 주사위 물성을 바꿨을 때만 필요하며, 스킴 `TrajectoryBaker`를 빌드한 뒤 반드시 Finder나 `open -a`로 앱을 띄워야 하는데 셸에서 바이너리를 직접 실행하거나 샌드박스 안에서 `open`하면 창이 생기지 않아 RealityKit 물리가 돌지 않고 CPU 0%로 영원히 대기한다. 진행 로그는 `open --stdout 파일 -a TrajectoryBaker.app`으로 받고 900회 시도에 약 15분이 걸리며, `--args -variants 30`으로 시도 수를 줄여 파라미터를 맞춰 보고, `--args -dice 5`로 그 개수만 굽거나 `--args -merge 기존.bin`으로 기존 아카이브 뒤에 이어 붙여 채택률이 낮은 조합만 보충할 수 있다. 굽기가 끝나면 `/private/tmp/trajectories.bin`을 `App/Resources/`에 덮어쓰고 `TrajectoryLibraryTests`와 `StageProjectionTests`로 개수·다양성·화면 안 배치를 확인한다.

## 저장소가 iCloud 안에 있다

iCloud Drive는 동기화 충돌 시 `Info 2.plist`처럼 " 2." 접미사 사본을 만드는데, `.gitignore`가 소스·설정 확장자에 대해서는 이를 무시하지만 `YachtDice 2.xcodeproj` 같은 디렉터리는 직접 지워야 하며, 프로젝트는 언제든 `xcodegen generate`로 다시 만들 수 있다.
