# Yacht Dice — P2/P3: 메뉴, 참가자 모델, 봇, 온라인 대전 설계

- 작성일: 2026-09-07
- 상태: 승인됨 (2026-09-07). A·B 구현 완료 (2026-09-07), C 진행 예정
- 선행: P1 완료 (`2026-08-28-yacht-dice-p1-core-3d-design.md`)
- 범위: 던지기 연출 수정(A), 시작 메뉴·참가자 모델·로컬 다인·봇(B), Game Center 온라인 대전(C)

## 1. 목표

혼자 12턴을 완주하는 P1 앱을 **상대가 있는 게임**으로 만든다.
상대는 같은 기기의 사람(패스앤플레이), 컴퓨터(3단계), 또는 Game Center로 연결된 다른 기기의 사람이다.

세 종류의 상대가 **같은 코드 경로**로 게임을 진행해야 한다. 봇이든 원격 플레이어든
`Intent`/`Event`를 만들어 `GameSession`에 넣고, 3D 연출은 사람이 굴릴 때와 똑같이 재생된다.

## 2. 확정된 결정 (2026-09-07 사용자 답변)

| 항목 | 결정 |
|---|---|
| 온라인 방식 | Game Center 턴제 매치 (`GKTurnBasedMatch`). 별도 서버 없음. 주사위는 클라이언트가 굴림 |
| 고정 UI | 3D 트레이의 주사위를 직접 탭해서 고정/해제. 숫자 칩도 유지 |
| 봇 난이도 | 3단계: 쉬움 / 보통 / 어려움 |
| 로컬 다인 | 같은 기기 2~4인 패스앤플레이 포함 |
| 순서 | A(연출) → B(메뉴·참가자·봇·로컬 다인) → C(온라인) |

스펙 P1 §3의 "Supabase 게임서버" 결정은 이 문서로 **대체**한다. 서버 권위 RNG는
포기하며, 그 대가는 §7.4에 적는다.

## 3. A — 던지기 연출

### 3.1 문제 (2026-09-07 실측)

- 구운 궤적이 뒷벽 위 공중(높이 0.08~0.10)에서 시작해 거의 수직으로 떨어진 뒤 앞벽까지 미끄러졌다.
  실제 움직임은 0.3초, 나머지는 정착 판정용 대기 프레임(중앙값 31프레임)이었다.
- 주사위가 바닥의 제자리에서 사라져 공중에 순간이동한 뒤 떨어졌다.

### 3.2 베이커 변경 (구현 완료)

- 플레이어 쪽(앞, +z) 가장자리 높이 0.045에서 트레이 안쪽(-z)으로 던진다.
  앞 속도 0.55~0.95 m/s, 위 0.2~0.5 m/s, 회전 ±45 rad/s. 첫 착지가 트레이 가운데가 되도록 잡았다.
- keep 선반을 물리 장애물로 넣는다. 없으면 주사위가 선반 띠 안에서 멈춰 나무 턱에 파묻힌다.
- 기각 조건 추가: 보이는 벽(0.03)보다 위에서 물리 벽(0.12)에 닿음, 선반 위에서 멈춤, 0.6초 미만.
- 정착 대기 프레임을 잘라내고 마지막 움직임 뒤 10프레임만 남긴다.
- 조합당 시도 60회. 1개짜리 굴림은 채택률이 30%대라 20개를 채우려면 이만큼 필요하다.

### 3.3 앱 변경

- 리드인: 굴릴 주사위를 지금 자리에서 궤적의 첫 자세까지 0.2초 동안 포물선으로 옮긴다 (구현 완료).
- 3D 탭 고정: `DiceStageView`에 `SpatialTapGesture().targetedToAnyEntity()`를 걸고, 맞은 엔티티 이름
  `die<N>`으로 슬롯을 찾아 `session.send(.toggleHold(N))`. 주사위에 `InputTargetComponent`와
  히트테스트용 `CollisionComponent`를 붙인다 (물리 아님). 내 차례가 아니거나 연출 중이면 무시한다.

## 4. B — 참가자 모델과 게임 흐름

### 4.1 Participant

```swift
/// 좌석 하나. 순서는 GameState.currentPlayer와 같다.
enum Participant: Codable, Equatable, Sendable {
    case human(name: String)              // 이 기기의 사람
    case bot(BotDifficulty)               // 컴퓨터
    case remote(playerID: String, name: String)   // 다른 기기의 사람 (C)
}

enum GameMode: Codable, Equatable, Sendable {
    case solo
    case versusBot(BotDifficulty)
    case passAndPlay(names: [String])
    case online(matchID: String)
}
```

`MatchRecord { mode, participants, log }`가 저장 단위다. `MatchStore`의 파일 형식은 버전 2로 올리고,
버전 1 파일(`MatchLog`만)은 `solo`로 읽는다.

### 4.2 GameSession 확장

- `participants: [Participant]`, `currentParticipant`, `isLocalTurn: Bool`.
- `send(_:)`는 `isLocalTurn`이 거짓이면 거부한다. 뷰의 버튼·제스처·3D 탭은 전부 이 조건으로 잠긴다.
- 턴이 넘어가면(`turnAdvanced` 적용 직후) `advanceTurnOwner()`가 다음 좌석을 본다.
  - 봇이면 `runBotTurn()`을 Task로 띄운다.
  - 원격이면 `TurnTransport`에 로그를 넘기고 상대 이벤트를 기다린다 (C).
  - 사람이면 입력을 연다. 패스앤플레이는 "다음: {이름}" 오버레이를 띄워 기기를 넘길 시간을 준다.
- `runBotTurn()`: `BotPlayer.decide(state)`가 돌려주는 `Intent`를 `send`로 넣는다.
  사람과 같은 경로라 3D 연출·점수판 지연 규칙(§8.2 P1)이 그대로 적용된다.
  Intent 사이에 0.4~0.8초 지연을 둔다. Reduce Motion이면 지연을 줄인다.

### 4.3 YachtBot 패키지

`Packages/YachtBot`. `YachtCore`만 의존한다. SwiftUI·RealityKit을 import하지 않는다.

```swift
public enum BotDifficulty: String, Codable, CaseIterable, Sendable { case easy, normal, hard }

public struct BotPlayer {
    public init(difficulty: BotDifficulty)
    /// 현재 상태에서 다음 행동. phase가 awaitingFirstRoll이면 항상 .roll.
    public func decide(_ state: GameState, using rng: inout some RandomNumberGenerator) -> Intent
}
```

봇의 결정은 "고정할 집합을 정한다 → 남은 굴림이 있으면 굴린다, 없으면 기록한다"로 단순화한다.
`decide`는 고정 상태를 목표 집합과 맞추기 위해 `toggleHold`를 하나씩 돌려주고, 맞으면 `.roll` 또는 `.commit`을 돌려준다.

| 난이도 | 고정 집합 | 기록 |
|---|---|---|
| 쉬움 | 가장 많은 눈만 고정하되 40% 확률로 무작위 집합 | 현재 굴림에서 점수가 가장 높은 빈 칸. 동점이면 무작위 |
| 보통 | 가장 많은 눈 고정. 4연속이 있으면 그것을 고정 | 현재 최고 점수. 단 상단 칸은 눈×3 미만이면 미루고 Choice/0점 칸 처리는 최후 |
| 어려움 | 32개 부분집합 각각에 대해 재굴림 결과(최대 6⁵)를 전수 열거해 "최고 빈 칸 점수"의 기대값이 최대인 집합 | 기대값 계산에 쓴 같은 평가 함수. 12턴 전체 최적화는 하지 않는다 (1-ply) |

어려움의 계산량은 32 × 7776 = 248,832회 채점이 최대이며, 마지막 굴림에서만 이만큼이다.
Release에서 수십 ms, Debug에서도 1초 미만이어야 한다. 테스트로 상한을 건다.

### 4.4 메뉴

`MenuScreen`이 첫 화면이다. `AppContainer.status`에 `.menu`를 추가하고, 모드를 고르면 `GameSession`을 만든다.

- 혼자 연습
- 컴퓨터 대전 → 난이도 3택
- 로컬 2~4인 → 인원과 이름 (기본값 "플레이어 1…")
- 온라인 대전 → C 전까지는 "준비 중" 비활성
- 이어하기 → 저장된 `MatchRecord`가 있을 때만

게임 화면은 `GameScreen`을 그대로 쓰되 상단에 `PlayerStrip`(좌석별 이름·총점, 현재 차례 강조)을 붙인다.
끝나면 `GameOverBar`가 순위를 보여주고 "메뉴로" 버튼을 준다.

## 5. C — Game Center 턴제 매치

### 5.1 구조

```
GameSession ──▶ TurnTransport (프로토콜)
                  ├─ InMemoryTurnTransport   (테스트)
                  └─ GameCenterTurnTransport (GKTurnBasedMatch)
```

```swift
protocol TurnTransport: Sendable {
    /// 내 턴이 끝났다. 전체 로그를 올리고 다음 참가자에게 넘긴다.
    func endTurn(log: MatchLog) async throws
    /// 게임이 끝났다. 결과를 올린다.
    func endMatch(log: MatchLog) async throws
    /// 상대 턴이 끝나 새 로그가 도착하면 흐른다.
    var incomingLogs: AsyncStream<MatchLog> { get }
}
```

매치 데이터는 `MatchLog` JSON 그대로다. 수신 측은 자기 로그보다 긴 부분만 새 이벤트로 보고,
`GameState.canApply`로 검증하며 하나씩 재생한다 — 굴림은 3D로, 고정·기록은 즉시.

`MatchDriver`(P1)는 남기되 온라인에서도 `LocalDriver`를 쓴다. 눈의 출처가 클라이언트이기 때문이다.
P1 스펙 §8.1이 예고한 "OnlineDriver"는 만들지 않는다. 필요한 것은 눈의 출처가 아니라 로그의 전송이다.

### 5.2 흐름

1. 메뉴 → 온라인 대전: `GKLocalPlayer.local.authenticateHandler`. 실패하면 이유를 보여주고 메뉴로.
2. `GKTurnBasedMatchmakerViewController`(2인, 친구 초대 또는 자동 매칭)를 `UIViewControllerRepresentable`로 띄운다.
3. 매치가 잡히면 `participants = [.human(나), .remote(상대)]` 순서는 `match.participants` 순서를 따른다.
4. 내 턴: 로컬과 같다. `committed` + `turnAdvanced`가 적용되면 `endTurn(log:)`.
5. 상대 턴: 입력 잠금, "상대 차례" 표시. `incomingLogs`가 오면 새 이벤트를 재생하고 내 턴을 연다.
6. 12턴 종료: `endMatch(log:)`로 결과를 확정한다.
7. 재접속: 메뉴의 "온라인 대전"이 진행 중인 매치 목록(`GKTurnBasedMatch.loadMatches`)을 보여준다.

### 5.3 필요한 외부 설정 (사용자 작업)

- Apple Developer 포털에서 앱 ID에 Game Center 기능을 켠다.
- App Store Connect에서 앱에 Game Center를 활성화한다.
- 프로젝트에는 `com.apple.developer.game-center` 엔타이틀먼트를 `project.yml`로 추가한다.

시뮬레이터에서는 Game Center 샌드박스 로그인이 제한적이다. 실기기 2대(또는 실기기 + 시뮬레이터)로 확인한다.
자동화 테스트는 `InMemoryTurnTransport`로 두 세션을 연결해 전체 판을 돌린다.

## 6. 테스트

| 대상 | 테스트 |
|---|---|
| 궤적 | 조합당 ≥ 20개, 정지 위치 전부 화면 안, 선반과 겹침 없음, 보이는 벽 위 벽 접촉 0 (기존 + 신규) |
| 3D 탭 | 주사위에 히트테스트 컴포넌트가 있고, 탭 슬롯 매핑이 이름과 맞는다 |
| YachtBot | 시드 고정 시 결정 재현. 어려움 기대값 계산이 알려진 손패에서 옳은 집합을 고른다(예: 6,6,6,2,3 → 6 셋 고정). 어려움 vs 쉬움 100판 평균 점수 우위. 계산 시간 상한 |
| GameSession | 봇 턴이 끝나면 사람 차례로 돌아온다. 사람 차례가 아닐 때 send가 거부된다. 패스앤플레이 4인 12턴 완주 |
| MatchStore | v1 파일을 solo로 읽는다. v2 왕복 |
| Transport | InMemory로 두 세션이 한 판을 완주하고 로그가 동일하다. 조작된 로그는 canApply에서 거부된다 |
| UI | 메뉴에서 각 모드 진입, 봇 대전 1턴, 접근성 식별자 유지 |

## 7. 리스크와 치르는 값

### 7.1 봇 턴이 3D 연출을 기다린다
봇 한 턴은 굴림 3회 × (리드인 0.2 + 궤적 ~1.2초) + 지연 ≈ 6초다. 4인 중 3명이 봇이면 턴 사이가 길다.
완화: 봇 턴에는 "빨리 감기" 토글(연출 건너뛰기)을 둔다. 기본은 켜지 않는다.

### 7.2 어려움 봇의 계산 시간
Debug에서 1초를 넘으면 UI가 멈춘 것처럼 보인다. 계산은 `Task.detached`로 돌리고 상한 테스트를 둔다.

### 7.3 Game Center 검증 환경
시뮬레이터에서 매치메이킹이 안 될 수 있다. 실기기 없이 끝낼 수 있는 것은 InMemory 전송 테스트까지다.
실기기 검증은 사용자 작업으로 남긴다.

### 7.4 서버 권위 RNG 포기
클라이언트가 굴린 눈을 상대가 그대로 믿는다. 조작된 클라이언트는 원하는 눈을 만들 수 있다.
`canApply`가 규칙 위반(길이·범위·점수 계산)은 막지만 "운 좋은 눈"은 막을 수 없다.
캐주얼 무료 게임이라 감수한다. 랭킹·리더보드를 붙이는 순간 다시 논의한다.

## 8. 완료 기준

- A: 굴림이 "던져서 굴러가 멈춘다"로 보인다. 순간이동 없음. 궤적 테스트 전부 통과.
- B: 메뉴에서 컴퓨터 대전(3단계)과 로컬 4인을 시작해 12턴을 완주하고 순위가 뜬다. 저장·복원이 모드를 유지한다.
- C: InMemory 전송으로 두 세션이 한 판을 완주한다. Game Center 코드가 컴파일되고 인증·매치메이커 화면이 뜬다. 실기기 검증은 사용자.
