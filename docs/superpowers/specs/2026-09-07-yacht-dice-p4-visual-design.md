# Yacht Dice — P4: 시각 디자인, 피드백, 아이콘 설계

- 작성일: 2026-09-07
- 상태: 승인됨 (2026-09-07)
- 선행: P2/P3 완료 (`2026-09-07-yacht-dice-p2-p3-design.md`)
- 범위: 디자인 시스템, 전 화면 재스타일, 모션·햅틱·사운드, 앱 아이콘. 게임 규칙·3D 씬·네트워크는 건드리지 않는다.

## 1. 목표

기능은 완성됐지만 화면은 기본 iOS 리스트와 버튼이다. 3D 트레이(호두나무·버건디 가죽·상아색 주사위)가
이미 "보드게임 테이블"의 재질 언어를 갖고 있으니, **화면 전체가 그 테이블 위에 놓인 물건처럼** 보이게 한다.
점수판은 종이 점수표, 버튼은 황동, 패널은 가죽이다.

## 2. 확정된 결정 (2026-09-07 사용자 답변)

| 항목 | 결정 |
|---|---|
| 분위기 | 보드게임 테이블. 3D 트레이와 같은 재질 언어 |
| 다크 모드 | 라이트/다크 둘 다. 시스템 설정을 따른다 |
| 피드백 | 햅틱, 점수 애니메이션, 사운드, 앱 아이콘 전부 |
| 접근성 | 기존 식별자·라벨 유지. Dynamic Type. 글자 대비 4.5:1 이상. Reduce Motion 존중 |

## 3. 디자인 시스템 (`App/Design/`)

### 3.1 색 토큰 (`Theme.swift`)

`Theme`는 `EnvironmentValues`에 들어가는 값 타입이다. 뷰는 `@Environment(\.theme)`로 읽는다.
라이트/다크는 `Theme.light` / `Theme.dark` 두 인스턴스이고, 앱 루트가 `colorScheme`에 따라 고른다.

| 토큰 | 라이트 | 다크 | 용도 |
|---|---|---|---|
| `table` | 호두나무 밝은 톤 `#5A3A22` | 짙은 호두나무 `#1E140D` | 화면 바탕 (메뉴, 게임 뒷배경) |
| `paper` | 상아색 `#F4EDDC` | 어두운 종이 `#2A211A` | 점수판, 카드 |
| `paperLine` | `#D8CDB4` | `#3F332A` | 점수표 괘선 |
| `leather` | 버건디 `#6B1E22` | `#4A1418` | 헤더 띠, 패널 |
| `ink` | 먹색 `#1E1A17` | 상아색 `#F1E9D6` | 본문 글자 |
| `inkSecondary` | `#6E6255` | `#B8AC98` | 보조 글자 |
| `brass` | `#B8862B` | `#D3A24A` | 강조(버튼, 링, 미리보기 점수) |
| `brassInk` | `#4A3408` | `#1E1608` | 황동 위 글자 |
| `success` | `#2E6B3F` | `#7CC28F` | 보너스 달성 |
| `ivory` | `#F7F3EA` | `#F7F3EA` | 주사위 면 (모드 무관) |

대비 규칙: `ink`/`paper`, `inkSecondary`/`paper`, `brassInk`/`brass`, `ink`/`ivory` 조합은 WCAG 4.5:1 이상.
`ThemeContrastTests`가 상대 휘도를 계산해 강제한다. 황동색 글자를 종이 위에 직접 쓰지 않는다 — 미리보기 점수는
`brass` 배경의 알약에 `brassInk`로 쓴다.

### 3.2 서체·간격 (`Typography.swift`)

- 제목(앱 이름, 화면 제목): `.system(.largeTitle, design: .serif, weight: .semibold)`
- 숫자(점수, 턴): `.system(_, design: .rounded)` + `.monospacedDigit()`
- 본문: 시스템 기본. 전부 Dynamic Type을 따른다. 고정 크기는 쓰지 않는다.
- 간격: 4의 배수. 카드 모서리 14, 칩 모서리 10, 버튼 알약.

### 3.3 표면 (`Surfaces.swift`)

뷰 수정자 세 개. 질감은 `ProceduralTexture`로 앱 시작 시 한 번 그려 `Image`로 캐시한다(`SurfaceTextures`).

- `.paperCard()`: `paper` 배경 + 종이 결 오버레이(불투명도 0.06) + 1pt `paperLine` 테두리 + 약한 그림자.
- `.leatherPanel()`: `leather` 배경 + 가죽 결 오버레이(0.10) + 안쪽 어두운 비네트.
- `.brassButton(prominent:)`: 황동 그러데이션 알약, `brassInk` 글자, 눌리면 살짝 어두워짐. prominent가 아니면 황동 테두리만.

`table` 바탕은 `WoodBackground` 뷰: `table` 색 + 호두나무 결 오버레이(0.35) + 가장자리 비네트.

## 4. 화면

### 4.1 메뉴 (`MenuScreen`)

- 바탕 `WoodBackground`. 상단에 제목 로크업: "요트 다이스" 세리프 + 작은 상아색 주사위 두 개(`DieFaceView`, 눈 5·2).
- 이어하기 카드(있을 때만, 맨 위): 모드 이름, "Turn n/12" 진행 바, 황동 "이어하기" 버튼.
- 모드 카드 4개(`ModeCard`): 아이콘, 제목, 한 줄 설명. 컴퓨터 대전 카드는 펼치면 난이도 칩 3개(`쉬움/보통/어려움`).
  로컬 카드는 시트로 인원·이름. 온라인 카드는 `OnlineMenu`로.
- 우상단 톱니 → 설정 시트: 사운드, 햅틱 토글 (`@AppStorage("sound.enabled")`, `"haptics.enabled"`).
- 식별자 유지: `menu.resume`, `menu.solo`, `menu.bot`, `menu.bot.<easy|normal|hard>`, `menu.local`, `menu.local.*`, `menu.online`. 추가: `menu.settings`.

### 4.2 게임 (`GameScreen`)

- 헤더: `leatherPanel` 띠. 왼쪽 메뉴 버튼, 가운데 "TURN 3 / 12"와 12칸 진행 표시(`TurnProgress`), 오른쪽 상태("컴퓨터가 생각 중" 등).
- 참가자 띠(`PlayerStrip`): 황동 테두리 명패. 현재 차례는 황동 배경. 봇은 cpu 아이콘.
- 3D 무대는 그대로. 무대 위아래에 얇은 그림자 띠로 화면과 이어 붙인다.
- 액션 바(`ActionBarView`):
  - 주사위 칩 → `DieFaceView`: 상아색 면에 눈. 굴리기 전은 빈 면(눈 없음, 흐림). 고정하면 황동 링 + 2pt 위로.
  - Roll → `brassButton(prominent: true)`, 라벨 "Roll", 오른쪽에 남은 횟수 점 3개(찬 점/빈 점).
  - Assist → 황동 테두리 토글.
- 점수판(`ScoreboardView`): `paperCard`. 행마다 이름 … 점선 리더 … 점수. 기록은 `ink` 굵게, 미리보기는 황동 알약(`brass`/`brassInk`), 빈 칸은 `inkSecondary` "–".
  상단 소계 행에 0/63 미니 진행 바, 달성하면 `success`로 바뀌고 "+35". 총점 행은 굵은 괘선 위에 큰 숫자.
- 결과(`GameOverBar`): `paperCard`에 순위. 1위 옆 트로피. "메뉴로"(테두리) / "새 게임"(황동).
- 핸드오프(`HandoffOverlay`): 흐린 `table` 위 큰 이름과 황동 "시작".
- 온라인 메뉴: 상태 카드, 매치 목록 카드. 같은 표면 스타일.

접근성 식별자·라벨은 전부 유지한다. `DieFaceView`는 `accessibilityLabel`을 칩과 같게("주사위 1, 4") 준다.

## 5. 모션과 피드백

### 5.1 애니메이션 (`Motion.swift`)

- 기록: 그 행의 점수가 0에서 목표까지 0.4초 카운트업(`contentTransition(.numericText)`).
- 총점: 바뀔 때 굴러오르기(같은 전환).
- 보너스 달성: 소계 행이 `success`로 바뀌며 0.6초 황동 반짝임(오버레이 불투명도 애니메이션).
- 고정: 칩이 스프링으로 2pt 올라가고 링이 나타남.
- Reduce Motion: `@Environment(\.accessibilityReduceMotion)`이 참이면 전환을 `.none`으로.

### 5.2 햅틱 (`Haptics.swift`)

`Haptics` 액터가 아니라 `@MainActor` 싱글턴. `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`.

| 이벤트 | 햅틱 |
|---|---|
| 충돌 큐 intensity < 0.35 | impact light |
| 0.35 ≤ intensity < 0.7 | impact medium |
| ≥ 0.7 | impact heavy |
| 고정 토글 | selection |
| 기록 | impact rigid |
| 야추 기록, 보너스 달성 | notification success |

큐는 프레임 번호를 갖고 있으므로 `GameSession.onCollisionCues`에서 받아 프레임 시각에 맞춰 예약한다
(굴림 시작 시각 + frame/frameRate). `hapticsFor(cue:) -> HapticKind`는 순수 함수라 테스트한다.

### 5.3 사운드 (`SoundSynth.swift`, `SoundPlayer.swift`)

외부 파일 없이 합성한다. `SoundSynth`는 PCM `Float32` 버퍼를 만든다:

- `tock(intensity:)`: 60ms, 흰 노이즈 × 지수 감쇠 + 180Hz 사인 한 주기. 세기로 진폭. 주사위 충돌.
- `tick()`: 25ms, 2kHz 클릭. 고정 토글.
- `stamp()`: 120ms, 노이즈 버스트 + 낮은 톤. 기록.
- `chime()`: 400ms, 3화음(C5-E5-G5) 감쇠. 야추·보너스.

`SoundPlayer`는 `AVAudioEngine` + `AVAudioPlayerNode` 하나로 버퍼를 `scheduleBuffer`한다.
오디오 세션은 `.ambient`(다른 앱 음악을 끊지 않는다). 설정에서 끄면 아무것도 예약하지 않는다.
`SoundSynthTests`는 버퍼 길이와 최대 진폭(≤ 1.0, > 0)을 확인한다.

### 5.4 연결점

`FeedbackCoordinator`(`@MainActor`)가 `GameSession`의 콜백과 상태 변화를 구독해 햅틱·사운드를 트리거한다.
`GameScreen`이 `.task`로 만들고 세션에 붙인다. `GameSession`은 UIKit·AVFoundation을 모른다.

## 6. 앱 아이콘

`Tools/AppIcon/GenerateAppIcon.swift`를 고친다. 1024×1024, 알파 없음.

- 바깥 테두리: 호두나무 색 띠(폭 6%)에 결 줄무늬.
- 안쪽: 버건디 가죽, 가운데 밝고 가장자리 어두운 방사 그러데이션 + 미세 노이즈.
- 주사위 두 개: 상아색, 모서리 라운드, 각각 −12°와 +9° 기울여 겹치지 않게 배치. 눈은 5와 2. 아래로 부드러운 그림자.
- 1024에서 그린 뒤 60px로 줄여 눈이 뭉치지 않는지 확인한다(스크립트가 축소본도 같이 저장).

## 7. 테스트

| 대상 | 테스트 |
|---|---|
| Theme | 위 대비 조합 4.5:1 이상 (라이트·다크 모두) |
| DieFaceView | 값 1~6에 눈 개수, 0이면 눈 없음 (뷰가 아니라 `DiePipTexture.pipLayout` 재사용을 확인) |
| Haptics | `hapticsFor(cue:)` 경계값 |
| SoundSynth | 네 소리의 길이·진폭 범위 |
| SurfaceTextures | 세 질감 이미지가 만들어지고 크기가 맞는다 |
| UI | 기존 UI 테스트 전부 통과 (식별자 유지). 메뉴 설정 시트 열림 |
| 시각 | 라이트·다크 스크린샷을 사용자에게 보낸다 |

## 8. 치르는 값

- 종이·가죽·나무 질감 생성이 앱 시작에 더해진다. 512² 세 장, 캐시. `DiceSceneBuilder`의 2초 상한 테스트와 같은 상한을 둔다.
- 사운드 합성은 첫 재생 전에 한 번. 오디오 엔진 시작 실패는 조용히 무시한다(사운드 없이 진행).
- 시뮬레이터에서는 햅틱이 없다. 실기기 확인.

## 9. 완료 기준

- 라이트·다크 모두에서 메뉴·게임·결과·핸드오프·온라인 화면이 §4대로 보인다.
- 기존 UI 테스트 8개 + 단위 테스트 전부 통과. 새 테스트 §7 통과.
- 굴림 중 충돌에 맞춰 햅틱·사운드가 나고, 설정에서 끌 수 있다.
- 새 아이콘이 60px에서도 주사위로 읽힌다.
