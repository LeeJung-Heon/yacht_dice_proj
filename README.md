# 요트 다이스 (Yacht Dice)

닌텐도 『세계의 게임 대전 51』의 Yacht Dice를 레퍼런스로 삼은 iOS 네이티브 야추 다이스 게임.
RealityKit 3D 주사위, 이벤트 소싱 규칙 엔진, 세로 화면 전용.
혼자 연습, 컴퓨터 대전(3단계), 같은 기기 2~4인, Game Center 턴제 온라인 대전까지 된다.

## 빌드

Xcode 프로젝트는 저장소에 없다. [XcodeGen](https://github.com/yonaskolb/XcodeGen)이 `project.yml`에서 만든다.

```sh
brew install xcodegen
xcodegen generate
open YachtDice.xcodeproj
```

- 스킴 `YachtDice`: iOS 앱 + 단위 테스트 + UI 테스트
- 스킴 `TrajectoryBaker`: 궤적을 굽는 macOS 툴 (아래 참고)
- 요구 사항: Xcode 26, iOS 18 이상, Swift 6 strict concurrency

테스트는 시뮬레이터에서 돌린다.

```sh
xcodebuild -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

패키지 단위 테스트는 Xcode 없이도 돈다.

```sh
swift test --package-path Packages/YachtCore
swift test --package-path Packages/DiceTrajectory
```

## 구조

```
SwiftUI Views ──관찰──▶ GameSession  (@Observable, @MainActor)
                          ├─▶ YachtCore.GameState   (순수 규칙, 의존성 0)
                          ├─▶ MatchDriver           (P1: Local / P2: AI / P3: Online)
                          └─▶ DiceStage             (RealityKit 연출)
```

| 경로 | 역할 |
|---|---|
| `Packages/YachtCore` | 규칙 엔진. `Intent`(하고 싶은 것)와 `Event`(확정된 사실)를 분리한 이벤트 소싱. UI·3D를 모른다. |
| `Packages/DiceTrajectory` | 구운 궤적 자료구조, 바이너리 포맷, 회전 오프셋(정육면체 대칭군), 트레이 치수, 궤적 검증기. |
| `App/Game` | `GameSession`(유일한 오케스트레이터), `MatchDriver`, 진행 저장(`MatchStore`). |
| `App/Scene3D` | RealityKit 씬. `DiceSceneBuilder`(지오메트리), `SceneMaterials`(절차적 PBR 텍스처), `SceneLighting`(조명·IBL), `DiceStage`(궤적 재생). |
| `Packages/YachtBot` | 컴퓨터 상대. 난이도 3단계, 손패 기대값 전수 계산. YachtCore만 의존. |
| `App/Views` | 세로 화면 UI. 시작 메뉴(`MenuScreen`), 참가자 띠, 점수판, 액션 바, 결과 바. |
| `App/Design` | 테마 토큰(라이트/다크, 대비 검사), 종이·가죽·나무 표면, 주사위 면 뷰, 메뉴 카드. |
| `App/Feedback` | 햅틱 매핑, 합성 효과음(외부 파일 없음), 세션 콜백을 잇는 FeedbackCoordinator, 설정 키. |
| `App/Online` | Game Center 턴제 매치. `TurnTransport` 프로토콜, 메모리 전송(테스트), Game Center 어댑터, 매치메이커. GameKit은 여기서만 import한다. |
| `App/AppContainer.swift` | 앱 조립과 저장된 판 복원. |
| `Tools/TrajectoryBaker` | 물리 시뮬로 궤적을 굽는 macOS 앱. 결과는 `App/Resources/trajectories.bin`. |
| `docs/superpowers` | 설계 스펙과 구현 계획. |

### 주사위는 물리를 돌리지 않는다

결과(눈)가 먼저 정해지고, 물리는 연출만 한다. 베이커가 미리 구운 궤적을 재생하되
각 주사위의 회전에 정육면체 대칭군의 원소를 곱해 원하는 눈이 위를 향하게 한다.
회전 대칭이라 매 프레임 주사위가 점유하는 공간은 원본과 완전히 같다 — 눈속임이 아니라 동일한 궤적이다.
이 덕분에 온라인 대전(P3)에서 두 화면이 프레임 단위로 같고, 기기에서 물리를 돌리지 않는다.
자세한 근거는 `docs/superpowers/specs/2026-08-28-yacht-dice-p1-core-3d-design.md` §7.

### 화면도 테이블 위에 있다

메뉴·점수판·버튼은 3D 트레이와 같은 재질 언어(호두나무·버건디 가죽·상아색 종이·황동)를 쓴다.
색은 `App/Design/Theme.swift`의 토큰뿐이고, 글자 조합의 대비는 테스트가 4.5:1 이상으로 강제한다.
나무·가죽 배경은 3D 트레이의 알베도 생성기를 그대로 2x로 깐 것이다.
앱 아이콘은 `swift Tools/AppIcon/GenerateAppIcon.swift <출력.png>`로 다시 그린다.

### 3D 에셋은 전부 코드다

가죽·호두나무·주사위 눈은 `App/Scene3D/ProceduralTexture.swift`의 결정적 노이즈로 앱 시작 시 그린다.
외부 텍스처·모델 파일이 없다. 트레이의 **보이는 모양**(모서리 라운드, 선반 패드)은 자유롭게 바꿔도 되지만,
주사위가 닿는 면의 위치(`TrayGeometry`)는 구운 궤적과 맞물려 있으니 바꾸면 다시 구워야 한다.

## 온라인 대전을 실기기에서 확인하려면

코드는 시뮬레이터에서 컴파일되고 메모리 전송으로 두 세션이 한 판을 완주하는 것까지 테스트한다.
실제 Game Center 매치는 다음이 갖춰져야 동작한다.

1. Apple Developer 포털에서 앱 ID `com.leejungheon.yachtdice.YachtDice`에 **Game Center** 기능을 켠다.
2. App Store Connect에서 앱에 Game Center를 활성화한다 (앱 레코드가 있어야 한다).
3. 실기기 두 대에 서로 다른 Apple ID(샌드박스 테스터 가능)로 Game Center에 로그인한다.
4. 메뉴 → 온라인 대전 → 새 매치 찾기. 친구 초대 또는 자동 매칭.

매치 데이터는 `MatchLog` JSON 그대로다. 상대가 보낸 로그는 `GameState.canApply`로 검증한 뒤 재생한다.
주사위는 각 클라이언트가 굴리므로 조작된 클라이언트의 "운 좋은 눈"은 막지 못한다 (스펙 P2/P3 §7.4).

자동화된 검증 범위: 메모리 전송으로 두 세션이 12턴 완주, 조작 로그 거부, 매치 열기(새 매치·이어하기·상대 차례·
손상 데이터·중복 열기). Game Center 자체(인증, 매치메이커, 턴 이벤트 전달)는 자동화할 수 없다.

**실기기 검증 체크리스트** (기기 A·B, 서로 다른 Apple ID):

1. A: 메뉴 → 온라인 대전 → 상태가 "…으로 로그인됨"인지. 아니면 설정 앱 → Game Center 로그인.
2. A: 새 매치 찾기 → 자동 매칭(또는 B 초대). 게임 화면이 열리고 상대 명패가 "상대"(자동 매칭) 또는 B 이름인지.
3. A: 굴리고 기록한다. 헤더가 "상대 차례"로 바뀌고 Roll이 잠기는지.
4. B: 알림을 탭하거나 온라인 대전 → 진행 중인 매치에서 연다. A의 주사위 눈과 점수가 그대로 보이고 B의 차례가 열리는지.
5. B: 한 턴을 둔다. A의 화면에 B의 굴림이 3D로 재생되고 A의 차례가 열리는지.
6. 앱을 완전히 종료한 뒤 다시 열어 진행 중인 매치를 열면 같은 상태인지 (이어하기).
7. 12턴을 끝낸다. 양쪽 결과 카드의 순위가 같고, Game Center 매치 목록에서 사라지는지.
8. 기내 모드로 상대 턴을 기다리다 해제했을 때 턴 이벤트가 도착하는지.

## 궤적 다시 굽기

`TrayGeometry`나 주사위 물성을 바꿨을 때만 필요하다.

1. 스킴 `TrajectoryBaker`를 빌드한 뒤 **Finder나 `open -a`로 앱을 띄운다.** 셸에서 바이너리를 직접 실행하거나
   샌드박스 안에서 `open`하면 창이 생기지 않아 RealityKit 물리가 돌지 않는다 (CPU 0%로 영원히 대기).
   진행 로그는 `open --stdout 파일 -a TrajectoryBaker.app`으로 받는다. 1200회 시도에 약 25분.
   - `--args -dice 5`: 그 개수만 굽는다. `--args -merge 기존.bin`: 기존 아카이브 뒤에 이어 붙인다.
     채택률이 낮은 조합(5개짜리)만 보충할 때 둘을 같이 쓴다.
2. 굽기가 끝나면 `/private/tmp/trajectories.bin`을 `App/Resources/`에 덮어쓴다.
3. `TrajectoryLibraryTests`와 `StageProjectionTests`를 돌려 개수·다양성·화면 안 배치를 확인한다.

## 저장소가 iCloud 안에 있다

iCloud Drive가 동기화 충돌 시 `Info 2.plist`처럼 " 2." 접미사 사본을 만든다.
`.gitignore`가 소스·설정 확장자에 대해 이를 무시하지만, `YachtDice 2.xcodeproj` 같은 디렉터리는
직접 지워야 한다. 프로젝트는 언제든 `xcodegen generate`로 다시 만들 수 있다.
