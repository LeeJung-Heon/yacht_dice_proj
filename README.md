# 요트 다이스 (Yacht Dice)

닌텐도 『세계의 게임 대전 51』의 Yacht Dice를 레퍼런스로 삼은 iOS 네이티브 야추 다이스 게임에서 출발해 지금은 시작 화면이 요트 다이스·오목·컵퐁·알까기 네 게임의 허브가 되어 넷 다 실제로 눌리며, RealityKit 3D 주사위와 이벤트 소싱 규칙 엔진 위에 세로 화면 전용으로 만들었으며 요트는 혼자 연습·컴퓨터 대전(3단계)·같은 기기 2~4인을, 오목·컵퐁·알까기는 같은 기기 2인을 지원하고 네 게임 모두 Supabase 방 코드 온라인 대전과 선택적인 Game Center 로그인·전적·리더보드를 지원한다.

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
swift test --package-path Packages/GameCore
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
| `App/Online` | `TurnTransport` 프로토콜, 테스트용 메모리 전송, Supabase 서비스·전송·행 모델, 그리고 Game Center 신원·리더보드 서비스와 전적 저장소로, Supabase SDK와 GameKit은 여기서만 import한다. |
| `App/AppContainer.swift` | 앱 조립, 메뉴 상태, 저장된 판 복원, 온라인 매치 열기. |
| `Tools/TrajectoryBaker` | 물리 시뮬로 궤적을 굽는 macOS 앱으로, 결과는 `App/Resources/trajectories.bin`에 들어간다. |
| `docs/superpowers` | 설계 스펙과 구현 계획. |

### 주사위는 물리를 돌리지 않는다

결과(눈)를 먼저 정하고 물리는 연출만 하도록, 베이커가 미리 구운 궤적을 재생하되 각 주사위의 회전에 정육면체 대칭군의 원소를 곱해 원하는 눈이 위를 향하게 하며, 회전 대칭이라 매 프레임 주사위가 점유하는 공간이 원본과 완전히 같으므로 이것은 눈속임이 아니라 동일한 궤적이다. 이 덕분에 온라인 대전에서 두 화면이 프레임 단위로 같고 기기에서 물리를 돌리지 않으며, 근거는 `docs/superpowers/specs/2026-08-28-yacht-dice-p1-core-3d-design.md` §7에 있다.

### 화면도 테이블 위에 있다

메뉴·점수판·버튼은 3D 트레이와 같은 재질 언어(호두나무·버건디 가죽·상아색 종이·황동)를 쓰며, 색은 `App/Design/Theme.swift`의 토큰뿐이고 글자 조합의 대비는 테스트가 4.5:1 이상으로 강제한다. 나무·가죽 배경은 3D 트레이의 알베도 생성기를 그대로 2x로 깐 것이고, 앱 아이콘은 `swift Tools/AppIcon/GenerateAppIcon.swift <출력.png>`로 다시 그린다.

### 3D 에셋은 전부 코드다

가죽·호두나무·주사위 눈은 `App/Scene3D/ProceduralTexture.swift`의 결정적 노이즈로 앱 시작 시 그리므로 외부 텍스처와 모델 파일이 없으며, 트레이의 보이는 모양(모서리 라운드, 선반 패드)은 자유롭게 바꿔도 되지만 주사위가 닿는 면의 위치(`TrayGeometry`)는 구운 궤적과 맞물려 있어 바꾸면 다시 구워야 한다.

## 게임 허브

시작 화면은 `AppContainer.Status.hub`로, 요트 다이스·오목·컵퐁·알까기 네 타일을 모두 누를 수 있다. 요트가 아닌 게임의 규칙은 `Packages/GameCore`의 `Game` 프로토콜(초기 상태·수를 둘 수 있는지·다음 좌석·승부 결과를 순수 함수로만 정의)과 `MoveLog<G>`(수 목록이 곧 판이고 서버 `log` 열의 JSON과 그대로 왕복)로 게임마다 갈라지며, 전송·검증·재생·Presence·연결 상태·끝남 알림은 게임에 무관한 `OnlineMatch<G>`(`App/Game/OnlineMatch.swift`) 하나가 맡아 요트 전용 `GameSession`과 `TurnTransport`를 함께 쓴다. 전적은 서버 `records` 뷰를 `RecordsStore`가 읽어 허브 카드와 최근 매치 목록에 보여 주며, Game Center 로그인은 선택이라 로그인하면 표시 이름이 닉네임이 되고 `gamePlayerID`로 전적이 앱을 지웠다 깔아도 이어지고, 로그인하지 않으면 그 기기의 익명 계정 uid로 전적이 남는다. 앱을 지우면 익명 계정이 사라져 새 uid를 받으므로 좌석 uid만 보는 정책으로는 예전 판이 통째로 안 보이는데, 로그인할 때마다 `link_profile`이 `gamePlayerID`를 지금 uid에 다시 이어 두고 `matches`에 그 연결을 지나는 두 번째 SELECT 정책(`matches_select_linked_player`)을 두어 내 `gamePlayerID`가 좌석에 적힌 행이면 uid가 달라도 읽히며, 갱신·삭제 정책은 uid 그대로라 예전 uid의 판은 전적으로만 남고 손댈 수는 없다. 좌석의 플레이어 문자열은 클라이언트가 보내는 값이라 그대로 믿으면 남의 `gamePlayerID`를 적어 남의 전적을 늘릴 수 있으므로, 방을 만들 때(`matches_guard_players` INSERT 트리거)와 들어갈 때(`join_match`), 그리고 나중에 값이 새로 적힐 때(`matches_guard_seats`) 모두 `profiles`에 그 uid로 이어진 플레이어인지를 서버가 확인하고 아니면 거절한다. 로그인한 사용자의 게임별 승수는 값이 바뀔 때만 리더보드 `wins.yacht`·`wins.omok`·`wins.cuppong`·`wins.alkkagi`에 오르며, UI 테스트는 GameKit 로그인 창을 넘길 수 없어 `AppContainer`에 launchArguments `-noGameCenter`를 주어 인증을 건너뛴다.

컵퐁은 `Packages/GameCore`의 `CupPong`이 규칙을 맡는데, 양쪽이 컵 열 개씩을 놓고 좌석 0이 먼저 던지며 상대 컵을 맞히면 그 컵이 사라지고 같은 사람이 한 번 더 던지고 빗나가면 차례가 넘어가며 상대 컵 열 개를 먼저 비운 쪽이 이기고 무승부는 없다. 수는 던진 힘 하나만 담는 `Shot { dx, power }`뿐이고 `landing`이 `L = 1200 + power * 2 + power * power / 400`, `X = dx * L / 1500` 같은 정수 사칙연산만으로 착지점과 맞힌 컵을 정해(사인·코사인·제곱근·난수를 쓰지 않는다) 같은 수를 받은 두 화면이 항상 같은 결과를 보므로 서버는 이 힘 하나만 검증하면 된다. 화면(`App/Games/CupPong`)은 늘 던지는 사람의 시점이라 먼 쪽 삼각형이 지금 맞혀야 할 상대 컵이고 상대가 던지면 같은 시점에서 상대의 수를 그대로 재생하되 그동안은 저 삼각형이 내 컵이므로 "상대가 내 컵 N개를 노린다"고 한 줄로 알리며, 손가락으로 아래에서 위로 끄는 스와이프를 `CupPongGeometry.shot`이 좌우·세기(`dx`·`power`)로 바꾸는 동안 그 힘으로 계산한 `CupPong.landing`까지 흰 점선을 그려 보여 주고 손을 떼면 그 힘 그대로 공이 날아가 넣으면 컵이 옅어지며 사라지고 퐁 소리와 진동이 붙는다. 세기는 끈 길이가 정하고 놓기 직전 구간에서 잰 손 속도가 거기에 최대 15%만 얹으므로 가운데를 향해 끈 공이 테이블을 넘기지 않으며, 조준선과 놓기가 같은 속도 값을 쓰기 때문에 점선으로 미리 본 자리에 공이 그대로 떨어진다.

알까기는 `Packages/GameCore`의 `Alkkagi`가 규칙을 맡는데, 13줄 판 위에 좌석마다 돌 다섯 개를 두고 좌석 0부터 번갈아 한 번씩 튕기며 상대 돌 다섯을 먼저 판 밖으로 다 밀어내면 이기고 한 튕김에 양쪽의 마지막 돌이 함께 떨어지면 무승부다. 판은 돌 하나 없이 열려 좌석 0부터 차례로 제 진영(좌석 0은 `y ∈ 0…5000`, 좌석 1은 `y ∈ 7000…12000`)의 교차점으로 돌 다섯을 끌어 놓고 "배치 완료"로 한 수를 두는 배치 단계를 거치는데, 진영을 벗어나거나 돌끼리 닿는 자리에 놓으면 그 돌만 있던 자리로 되돌아가고 둘 다 놓아야 좌석 0부터 튕기기가 시작된다. 수는 배치 한 번과 어느 돌을 얼마나 세게 어느 방향으로 튕겼는지만 담는 `Move { setup([Point]) | flick(Flick) }`이라 힘 말고는 아무것도 보내지 않으며, `simulate`가 1/120초 간격 고정 스텝 위에서 정수 사칙연산만으로 최대 600스텝 동안 이동·마찰·충돌·낙하를 그대로 정하고 제곱근도 부동소수점으로 잡은 어림값을 정수 루프로 보정해 어디서나 똑같이 정확한 정수를 내놓으므로(사인·코사인·부동소수점 좌표는 쓰지 않는다) 같은 수를 받은 두 기기가 프레임까지 비트로 같은 결과를 재생한다. 화면(`App/Games/Alkkagi`)은 내 돌을 누른 채 끄는 새총식 입력이라 당길수록 당김 선이 늘어나되 최대 당김(돌 지름의 네 배)에서 멈추고 황동색으로 바뀌며, 그 순간의 `Flick`으로 실제 `simulate`를 돌려 앞 40프레임을 흰 점선으로 미리 그려 주며, 손을 떼면 점선으로 본 그대로 돌이 날아가 충돌·낙하마다 소리와 진동이 따라온다. 온라인 대전의 게스트 쪽 화면은 판을 180도 돌려 내 돌이 늘 아래에 오게 보여 주되 입력과 튕김 계산은 격자 좌표 그대로 지나가므로 방향이 뒤집히지 않는다.

새 게임을 붙이는 데는 세 조각이면 된다: `Packages/GameCore`에 `Game`을 구현한 규칙 파일 하나(오목의 `Omok.swift`처럼 상태·수·승부 판정을 외부 의존성 없이 순수 함수로만 적는다), 그 게임의 화면(오목은 `App/Games/Omok/OmokScreen.swift`와 `OmokBoardView.swift`), 그리고 `AppContainer`에 그 게임을 여는 갈래 하나(`Status`에 케이스를 더하고 `resumeSavedGame`·`openSupabaseMatch`의 `GameID` 분기에 `OnlineMatch(game:mode:participants:log:transport:)`로 세션을 만들어 끼우는 함수를 오목의 `launchOmok`처럼 둔다) — 허브 타일, 전송, 전적 읽기·리더보드 제출은 그대로 재사용된다.

## 실기기에 설치하기

유료 개발자 계정 없이 무료 Apple ID의 개인 팀으로 설치할 수 있으며, 프로필이 7일마다 만료되고 기기는 팀당 3대까지라 테스트 용도에 맞고, 아이폰은 iOS 18 이상이어야 한다.

1. Xcode → Settings → Accounts에서 Apple ID를 추가하면 "Personal Team"이 생기고, 그 팀을 선택했을 때 오른쪽에 보이는 Team ID(영숫자 10자리)를 적어 둔다.
2. 프로젝트를 팀 ID와 함께 생성하고 연다. 팀 ID를 생략하면 Xcode의 Signing & Capabilities에서 팀을 고르면 되지만 다시 generate할 때마다 초기화된다.

   ```sh
   DEVELOPMENT_TEAM=ABCDE12345 xcodegen generate
   open YachtDice.xcodeproj
   ```

3. 아이폰을 케이블로 연결하고 잠금을 푼 뒤 "이 컴퓨터를 신뢰"를 누르며, iOS 16 이상은 설정 → 개인정보 보호 및 보안 → 개발자 모드를 켜고 재시동해야 Xcode가 기기를 쓸 수 있다.
4. Xcode 상단의 실행 대상을 그 아이폰으로 바꾸고 `YachtDice` 스킴을 Run(⌘R)하면 빌드·서명·설치가 한 번에 되며, 처음 한 번은 아이폰의 설정 → 일반 → VPN 및 기기 관리에서 내 Apple ID 개발자 앱을 신뢰해야 아이콘을 눌러 열 수 있다.
5. 한 번 설치한 뒤에는 케이블 없이도 같은 Wi-Fi에서 Run할 수 있고(기기 창에서 "Connect via network"), 7일이 지나 앱이 열리지 않으면 Xcode에서 다시 Run하면 된다.

온라인 대전을 실기기 두 대로 해 보려면 각 기기에 위 절차로 설치하고(한 Apple ID의 개인 팀으로 두 기기 모두 가능) 한쪽이 방을 만들어 코드를 알려 주면 되며, Game Center 엔타이틀먼트(`com.apple.developer.game-center`)는 `project.yml`에 이미 걸려 있고 앱 ID의 Game Center 기능과 App Store Connect의 리더보드 `wins.yacht`·`wins.omok`·`wins.cuppong`·`wins.alkkagi`도 만들어 둔 상태라, 유료 팀으로 서명하면 로그인과 승수 제출이 그대로 된다.

## TestFlight로 배포하기

남에게 온라인으로 설치하게 하는 공식 경로는 유료 개발자 계정(연 129,000원)의 TestFlight뿐이며, 저장소 쪽 준비는 끝나 있어서 계정과 App Store Connect 레코드만 만들면 아카이브해 올릴 수 있다. 준비된 것은 UserDefaults 사용 이유와 수집 항목(익명 계정 ID, 닉네임)을 적은 `App/PrivacyInfo.xcprivacy`, 버전 설정(`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`), 업로드 스크립트 `Tools/Release/upload.sh`, 그리고 외부 테스터 정보에 넣을 개인정보처리방침 `docs/privacy-policy.md`다.

1. https://developer.apple.com/programs/enroll 에서 Apple Developer Program에 개인으로 등록하면 승인까지 하루쯤 걸리며, 승인되면 Xcode → Settings → Accounts에 그 팀이 나타나고 Team ID를 알 수 있다.
2. https://appstoreconnect.apple.com 에서 앱을 새로 만들되 번들 ID는 `com.leejungheon.yachtdice.YachtDice`, 이름은 "요트 다이스", 기본 언어는 한국어로 하며, 번들 ID가 목록에 없으면 https://developer.apple.com/account/resources/identifiers 에서 먼저 등록한다.
3. 아카이브와 업로드는 스크립트 한 줄로 되며, Xcode에 로그인된 Apple ID로 서명과 업로드가 진행된다.

   ```sh
   DEVELOPMENT_TEAM=ABCDE12345 Tools/Release/upload.sh
   ```

   스크립트는 Xcode → Settings → Accounts에 팀의 Apple ID가 로그인돼 있어야 서명하며, 로그인 없이 터미널만으로 돌리려면 App Store Connect의 Users and Access → Integrations → Team Keys에서 App Manager 역할의 API 키를 만들어 `ASC_KEY_PATH`(.p8 경로), `ASC_KEY_ID`, `ASC_ISSUER_ID`를 함께 준다. Xcode에서 직접 하려면 실행 대상을 Any iOS Device로 두고 Product → Archive 뒤 Organizer에서 Distribute App → App Store Connect → Upload를 고르면 같다.
   API 키가 있으면 TestFlight 설정도 터미널에서 할 수 있는데, `Tools/Release/asc.swift`가 ES256 JWT를 만들어 App Store Connect API를 그대로 호출하므로 `swift Tools/Release/asc.swift get /v1/apps` 처럼 앱·빌드·베타 그룹·테스터·심사 상태를 읽고 `post`/`patch`로 바꿀 수 있다.
4. App Store Connect → TestFlight 탭에서 빌드 처리가 끝나면(보통 10분 안쪽) 외부 테스트 그룹을 만들고 Test Information에 연락처 이메일과 개인정보처리방침 URL(`docs/privacy-policy.md`를 GitHub Pages나 저장소 링크로)을 넣은 뒤 빌드를 그룹에 붙이면 첫 빌드는 간단한 Beta App Review를 거친다.
5. 그룹의 Public Link를 켜 링크를 나누면 받는 사람은 TestFlight 앱을 설치하고 링크를 눌러 받으며, 빌드는 90일 뒤 만료되고 새 빌드를 올릴 때는 `project.yml`의 `CURRENT_PROJECT_VERSION`을 1 올린다.

Game Center 엔타이틀먼트(`App/YachtDice.entitlements`)는 `project.yml`에 이미 걸려 있어 유료 팀으로 서명하면 로그인이 되며, 로그인은 선택이라 하면 표시 이름이 닉네임이 되고 게임별 승수가 리더보드 `wins.<게임>`에 오르고 안 해도 익명 계정으로 그대로 대전할 수 있다(자세한 구조는 "게임 허브" 절 참고).

## 온라인 대전

온라인 대전은 Supabase 무료 티어(프로젝트 `yacht-dice`, 서울)로 동작하며, 기기마다 익명 로그인으로 계정 하나를 받고 6자리 방 코드로 상대와 만나며, 한 판은 `public.matches` 행 하나다. 행은 어떤 게임인지를 `game` 열로, 호스트·게스트의 Game Center `gamePlayerID`(미로그인이면 null)를 `host_player`·`guest_player` 열로, 끝났을 때의 승자 좌석을 `winner_seat` 열로 갖고, 매치 데이터는 게임마다 다른 모양의 JSON을 그대로 나른다 — 요트는 `MatchLog`, 그 외는 `GameCore`의 `MoveLog<G>`다. 굴림·고정·기록 이벤트가 생길 때마다 행을 갱신하면 DB 트리거 `matches_broadcast`가 `realtime.broadcast_changes`로 비공개 채널 `match:<id>`에 행 전체를 쏘고, 상대는 그 채널을 세션 토큰으로 구독해 새 이벤트만 `GameState.canApply`(요트) 또는 게임별 `Game.canApply`(그 외)로 검증한 뒤 재생하므로 기록부터 상대의 내 차례까지 0.1초 안팎이 걸리며, 소켓이 끊긴 사이의 변경은 3초 폴링이 같은 행을 읽어 채우고 앱이 앞으로 돌아오면 한 번 더 읽는다. 굴린 쪽은 궤적 ID·방향·회전 선택을 `throws` 열에 이벤트 번호와 함께 적어 두고 받는 쪽은 같은 값으로 재생하므로 두 화면이 같은 던지기를 보며, 같은 채널의 Presence로 상대의 접속을 명패의 점으로, 채널 상태로 연결 끊김을 띠로 보여 준다. 규칙 위반은 막지만 주사위는 각 클라이언트가 굴려 조작된 클라이언트의 "운 좋은 눈"은 막지 못하고(스펙 P2/P3 §7.4), 서버 쪽 RLS는 참가자만 행을 읽고 갱신하게 하며 `realtime.messages` 정책이 참가자만 그 토픽을 받게 하고, 방 입장은 `join_match` 함수가 대기 중인 빈 자리에만 넣으며, 좌석·게임·플레이어는 한 번 정해지면 트리거가 바꾸지 못하게 막고 끝난 매치는 아예 더 못 고치며, 3일 넘게 멈춘 판은 `pg_cron`이 10분마다 `abandoned`로 바꿔 목록에 "상대가 떠남"으로 보인다.

Game Center로 로그인하면 `gamePlayerID`와 그 순간의 익명 uid를 security definer RPC `link_profile`이 `profiles` 테이블(`player`, `uid`, `name`)에 이어 두므로 앱을 지웠다 다시 깔아 uid가 바뀌어도 같은 `gamePlayerID`로 전적이 이어지고, 끝난 매치는 뷰 `records`가 `matches`에서 게임·플레이어(로그인했으면 `gamePlayerID`, 아니면 uid)별 승·패·무를 집계해 앱의 전적 카드와 Game Center 리더보드 제출의 원천이 된다.

앱이 닫혀 있어도 차례가 오면 알림이 오는데, 온라인 메뉴에 들어올 때 알림 권한을 묻고 APNs 토큰을 `device_tokens`에 올리며, 내 턴이 끝나 `turn_seat`가 바뀌거나 게스트가 들어오면 트리거 `matches_turn_webhook`가 `pg_net`으로 Edge Function `notify-turn`을 부르고, 함수는 알릴 좌석의 토큰을 읽어 APNs(HTTP/2, ES256 JWT)로 "내 차례"를 보내며 죽은 토큰은 지우고, 알림을 탭하면 그 판이 열린다. 함수 시크릿은 `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`(.p8 본문), `APNS_BUNDLE_ID`, `WEBHOOK_SECRET`이며 `supabase secrets set --project-ref lkernselwouldtuialjh`로 넣고, `WEBHOOK_SECRET`은 Vault의 `webhook_secret`과 같은 값이어야 하며, 서버 SQL은 `supabase/migrations/`에, 함수는 `supabase/functions/notify-turn/`에 있고 JWT 생성은 `deno test supabase/functions/notify-turn/`으로 검증한다.

검증은 세 층으로 되어 있는데, 메모리 전송으로 두 세션이 12턴을 완주하고 힌트로 같은 자세에 멈추는 단위 테스트, `YACHT_SUPABASE_E2E=1`을 주면 실제 프로젝트에 익명 계정 둘로 방 만들기·입장·턴 왕복과 전달 지연(중앙값 1.5초 아래), 낯선 계정의 구독 거부, Presence, 자세 재현, 폴링만으로의 전달과, 오목 방을 만들어 다섯 수로 끝내고 `winner_seat`·`records`·끝난 매치의 불변까지 확인하는 통합 테스트(`SupabaseE2ETests`), 그리고 시뮬레이터 두 대가 화면에서 코드로 만나 턴을 주고받는 것까지 확인했다.

```sh
TEST_RUNNER_YACHT_SUPABASE_E2E=1 xcodebuild -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:YachtDiceTests/SupabaseE2ETests test
```

익명 계정은 앱을 지우면 사라지므로 진행 중인 매치도 함께 잃으며(Game Center로 로그인해 두면 전적만은 `gamePlayerID`로 이어진다), 서버 설정은 대시보드에서 Anonymous sign-ins를 켜 두어야 하고, 익명 가입은 같은 IP에서 시간당 30회로 제한되어 통합 테스트를 한 시간에 여러 번 돌리면 `notSignedIn`(HTTP 429)으로 실패하므로 한 시간 뒤에 다시 돌린다. `GameCenterService`(`App/Online`)는 GameKit 턴제 매치가 아니라 신원 인증과 리더보드 제출만 맡으며, 대전 자체는 게임과 무관하게 Supabase로 돈다.

## 궤적 다시 굽기

`TrayGeometry`나 주사위 물성을 바꿨을 때만 필요하며, 스킴 `TrajectoryBaker`를 빌드한 뒤 반드시 Finder나 `open -a`로 앱을 띄워야 하는데 셸에서 바이너리를 직접 실행하거나 샌드박스 안에서 `open`하면 창이 생기지 않아 RealityKit 물리가 돌지 않고 CPU 0%로 영원히 대기한다. 진행 로그는 `open --stdout 파일 -a TrajectoryBaker.app`으로 받고 900회 시도에 약 15분이 걸리며, `--args -variants 30`으로 시도 수를 줄여 파라미터를 맞춰 보고, `--args -dice 5`로 그 개수만 굽거나 `--args -merge 기존.bin`으로 기존 아카이브 뒤에 이어 붙여 채택률이 낮은 조합만 보충할 수 있다. 굽기가 끝나면 `/private/tmp/trajectories.bin`을 `App/Resources/`에 덮어쓰고 `TrajectoryLibraryTests`와 `StageProjectionTests`로 개수·다양성·화면 안 배치를 확인한다.

## 저장소가 iCloud 안에 있다

iCloud Drive는 동기화 충돌 시 `Info 2.plist`처럼 " 2." 접미사 사본을 만드는데, `.gitignore`가 소스·설정 확장자에 대해서는 이를 무시하지만 `YachtDice 2.xcodeproj` 같은 디렉터리는 직접 지워야 하며, 프로젝트는 언제든 `xcodegen generate`로 다시 만들 수 있다.
