# P10 — 온라인 대전 빠른 전달과 순간 상태 설계

- 작성일: 2026-10-22
- 상태: 설계
- 선행: P6 실시간 고도화 (`2026-09-09-yacht-dice-p6-realtime-design.md`), 규칙 2 (`2026-09-22-realistic-games.md`)
- 범위: 확정된 수를 DB보다 먼저 채널로 보내는 빠른 길(A), 조준·배치·자리 고르기처럼 확정 전의 손놀림을 상대 화면에 흘리는 순간 상태(B). 전용 게임 서버, 서버 주사위, 동시 진행 게임은 범위 밖이다.

## 1. 목표

지금은 수를 두면 로그 전체를 REST로 `matches`에 쓰고 DB 트리거가 그 행을 `match:<id>`로 브로드캐스트한 뒤에야 상대가 받으므로 DB 쓰기와 트리거가 전달 경로 한가운데 있고, 확정된 수만 오가므로 상대가 알까기 돌을 당기거나 오목 자리를 고르는 동안 내 화면은 멈춰 있으며, 요트 굴림과 컵퐁 던지기는 굴린 쪽의 연출이 끝난 뒤에 올라가 상대 화면이 그 연출 길이만큼 늦게 따라온다. 이 스펙은 수가 DB를 기다리지 않고 채널로 먼저 가게 하고, 굴림과 던지기를 손을 놓는 순간 올려 두 화면의 연출이 거의 함께 시작하게 하며, 확정 전의 손놀림을 초당 10번 상대에게 흘려 상대가 지금 무엇을 하는지 보이게 한다.

성공은 세 가지로 잰다. 상대의 확정된 수가 내 화면에 닿는 시간이 DB 경로보다 짧아야 하고, 요트 굴림과 컵퐁 던지기가 두 화면에서 0.3초 안쪽 차이로 시작해야 하며, 오목·알까기·컵퐁에서 상대의 확정 전 손놀림이 보여야 한다.

## 2. 하지 않는 것과 해서는 안 되는 것

- 하지 않는다: 방마다 상태를 들고 있는 전용 서버, 서버가 정하는 주사위와 물리, 두 사람이 동시에 움직이는 게임, 3초 폴링 주기 변경, 요트의 순간 상태(고정·굴림은 이미 이벤트로 그때그때 오간다), 규칙 버전 변경.
- 해서는 안 된다: DB가 판의 기준이 아니게 되는 것, 빌드 11 이하 앱과의 대전이 깨지는 것, 순간 상태가 로그·전적·`throws`에 섞이는 것, 무료 티어 한도를 넘겨 연결이 끊기는 것, 내 화면의 연출 순서(컵이 공보다 먼저 사라지거나 차례 배너가 날아가는 공·돌을 덮는 것)가 바뀌는 것.

## 3. 결정

| 항목 | 결정 |
|---|---|
| 빠른 길 | `publish`는 채널이 구독된 상태면 같은 채널에 클라이언트 브로드캐스트 `move`로 `{log, event_count, throws}`를 먼저 보내고, 이어서 지금처럼 DB를 갱신한다. 받는 쪽은 `move`와 DB `UPDATE`를 같은 `lastSeenCount` 거르개에 넣는다 |
| DB 순서 | 갱신은 `event_count < 보낼 값`인 행에만 걸어 늦게 도착한 옛 갱신이 새 로그를 덮지 못하게 하고, 서버 트리거도 `event_count`가 줄어드는 갱신을 거절한다 |
| 권한 | `realtime.messages` INSERT 정책을 참가자의 `broadcast`와 `presence` 둘 다로 넓힌다 |
| 요트 굴림 | 눈과 궤적·회전을 먼저 정하고 그 굴림을 담은 로그를 올리는 일과 내 화면의 연출을 동시에 시작한다. 내 `visibleState`는 지금처럼 착지한 뒤에 바뀐다 |
| 요트 원격 재생 | 한 번에 받은 이벤트 묶음 안에서만 이벤트 사이에 뜸을 두고, 묶음의 마지막 이벤트 뒤에는 쉬지 않는다 |
| 컵퐁 던지기 | 손을 놓는 순간 `play(shot)`으로 올리고, 착지할 때까지 내 화면의 시점·컵·숫자를 던지기 직전 것으로 묶어 둔다 |
| 순간 상태 | 같은 채널의 클라이언트 브로드캐스트 `live`로 `{event_count, state}`를 보내며, 보내는 쪽은 100ms에 한 번으로 묶되 마지막 값은 반드시 보내고, 받는 쪽은 자기 로그의 수와 `event_count`가 같을 때만 그린다 |
| 게임별 순간 상태 | 오목은 고른 교차점, 알까기는 당김(튕길 때)과 초안·끄는 돌(배치할 때), 컵퐁은 조준 중인지 여부다 |
| 측정 | 통합 테스트가 빠른 길로 도착한 수를 세고, 순간 상태가 상대에게 닿는지와 옛 갱신이 새 로그를 덮지 못하는지를 확인한다 |

## 4. 서버

### 4.1 마이그레이션 `20261022_live_broadcast.sql`

참가자가 같은 토픽에 브로드캐스트를 보낼 수 있도록 P6의 `participants send presence` 정책을 지우고 `participants send broadcast and presence`로 바꾸며, 조건은 P6와 같되 `realtime.messages.extension in ('broadcast', 'presence')`다. 비참가자는 지금처럼 그 토픽을 구독할 수도 보낼 수도 없다.

`matches_guard_event_count`는 `BEFORE UPDATE` 트리거로 `new.event_count < old.event_count`이면 `event count must not decrease`로 거절하고, 같은 값은 통과시킨다. 같은 값을 막지 않는 것은 `join_match`와 `pg_cron`처럼 로그를 건드리지 않는 갱신이 있기 때문이며, 빌드 11 이하 앱은 앞선 갱신이 끝나야 다음 갱신을 보내므로 `event_count`를 줄이는 일이 없어 이 트리거에 걸리지 않는다.

운영 DB에는 사용자의 확인을 받은 뒤 적용하며, 정책을 넓히고 트리거를 더하는 것뿐이라 구버전 앱의 동작은 바뀌지 않는다.

### 4.2 한도

Supabase 무료 티어는 프로젝트 전체에서 초당 100개의 Realtime 메시지를 허용하며 보낸 것과 받은 것을 각각 하나로 세고, 넘기면 연결을 끊으며, 한 메시지는 256KB까지이고 한 달에 200만 개까지다. 순간 상태는 한 판에서 손가락이 닿아 있는 동안 초당 10번 보내 보내기와 받기를 합쳐 초당 20개를 쓰므로 다섯 판이 동시에 조준해야 한도에 닿고, 로그 전체를 싣는 `move`는 요트 한 판 끝에서도 수십 KB 안쪽이라 크기 한도와 거리가 멀다.

## 5. 앱

### 5.1 전송 계층

`TurnTransport`에 순간 상태 송수신을 더하고 기본 구현은 아무것도 하지 않는다.

```swift
protocol TurnTransport: Sendable {
    // 기존 멤버는 그대로다
    /// 확정 전의 손놀림. 저장하지 않으며 놓쳐도 판에 영향이 없다.
    func sendLive(_ frame: LiveFrame) async
    var live: AsyncStream<LiveFrame> { get }
}

struct LiveFrame: Sendable, Equatable {
    /// 보낸 쪽 로그의 수·이벤트 개수. 받는 쪽은 자기 것과 같을 때만 그린다.
    let eventCount: Int
    /// 게임별 JSON. nil이면 손을 뗐다는 뜻이다.
    let state: Data?
}
```

채널에는 `{"event_count": n, "state": <게임별 JSON 또는 null>}`로 실리며, `state`를 base64가 아닌 JSON 그대로 싣는 변환은 Supabase 전송이 맡는다.

`SupabaseTurnTransport`는 `listen()` 안에서 만든 채널을 속성으로 들고, `publish`는 채널이 `subscribed`일 때만 `channel.broadcast(event: "move", message:)`를 먼저 보낸 뒤 DB 갱신을 `.lt("event_count", value: 보낼 값)` 조건과 함께 보내며, 구독되지 않았으면 SDK가 REST로 대신 보내는 길을 타지 않도록 브로드캐스트를 건너뛴다. 브로드캐스트 실패는 삼키고 진단용 속성에만 남기며, DB 갱신의 재시도와 보류는 지금과 같되 보류분은 더 큰 `event_count`로만 바뀐다. 받는 쪽은 `broadcastStream(event: "move")`의 `payload`를 `RemoteUpdate`로 디코드해 `deliver`와 같은 거르개에 넣고, 빠른 길로 들어와 새 것으로 인정된 수를 진단용 카운터 `fastPathDeliveries`로 센다. `sendLive`는 구독 중일 때만 `live` 이벤트로 보내고, `broadcastStream(event: "live")`를 `live` 스트림으로 흘린다. 채널 설정의 `receiveOwnBroadcasts`는 기본값 `false`를 그대로 써 내 브로드캐스트가 나에게 돌아오지 않는다.

`InMemoryTurnTransport`는 `sendLive`를 짝의 `live`로 그대로 넘겨 단위 테스트가 두 세션 사이의 순간 상태를 확인할 수 있게 한다.

### 5.2 `OnlineMatch<G>`의 순간 상태

```swift
/// 내 손놀림을 상대에게 흘린다. 로컬 2인이거나 내 차례가 아니면 아무것도 하지 않는다.
func publishLive<L: Encodable>(_ state: L?)
/// 상대가 지금 하고 있는 것. 내 로그의 수와 맞지 않거나 수가 도착하면 nil이 된다.
private(set) var remoteLive: Data?
func remoteLive<L: Decodable>(as type: L.Type) -> L?
```

`publishLive`는 마지막으로 보낸 지 100ms가 지나지 않았으면 값을 들고 있다가 100ms가 찰 때 가장 최근 값만 보내고, `nil`은 들고 있던 값을 버리고 바로 보내며, 같은 값은 다시 보내지 않는다. 받는 쪽은 `frame.eventCount == log.moves.count`일 때만 `remoteLive`를 바꾸고, 상대 수를 재생하기 시작할 때, 상대의 Presence가 빠질 때, 연결이 끊길 때 `nil`로 비운다. 순간 상태는 `log`, `hints`, `onLogChanged`, 저장소 어디에도 들어가지 않는다.

### 5.3 게임별 순간 상태

| 게임 | 보내는 값 | 보내는 때 | 받는 쪽 화면 |
|---|---|---|---|
| 오목 | `{x, y}` 고른 교차점 | 교차점을 고를 때, 수를 두면 `nil` | 상대 색의 반투명 돌을 그 교차점에 그린다(`OmokBoardView`의 `preview`·`previewSeat`를 상대 좌석으로 쓴다) |
| 알까기 튕김 | `{stone, to}` 잡은 돌 번호와 손끝의 격자 좌표 | 당기는 동안, 놓거나 취소하면 `nil` | 그 돌의 지금 자리에서 `clampPull`한 당김선, 하이라이트, 짧은 조준선을 보내는 쪽 화면과 같게 그린다 |
| 알까기 배치 | `{draft: [Point], dragging: {stone, at}?}` | 배치 차례가 열릴 때 기본 배치를 한 번, 돌을 끌거나 놓을 때마다, 배치를 확정하면 `nil` | 상대 좌석에 초안 돌을 그리고 끄는 돌은 손끝 자리에 그린다 |
| 컵퐁 | `{aiming: true}` | 손가락이 닿으면, 떼면 `nil` | 던지는 자리에 공을 얹고 "상대가 조준 중"을 보인다 |

좌표는 모두 판 좌표라 알까기 게스트의 180도 회전과 무관하며, 알까기 판은 `Canvas`라 SwiftUI 애니메이션이 먹지 않으므로 받는 쪽은 손끝 좌표를 직전 값에서 새 값까지 100ms 동안 선형으로 이어 그리고 그동안만 `TimelineView`를 돌려 초당 10번의 갱신이 끊겨 보이지 않게 한다. 받은 순간 상태는 상대가 보낸 입력이므로 돌 번호와 배치 개수, 오목 좌표가 범위를 벗어나면 그리지 않고 버린다. 보내는 쪽은 화면을 떠나거나 앱이 비활성으로 갈 때 `nil`을 보내 끊긴 끌기가 상대 화면에 남지 않게 한다. 각 게임의 순간 상태 타입은 그 게임 화면 파일 옆에 두고 `GameCore`에는 넣지 않는다.

### 5.4 요트 굴림을 착지 전에 올린다

`DiceStage.roll`을 두 단계로 나눠, `planRoll(values:slots:direction:hint:)`이 지금 자세에서 궤적과 회전 선택을 정해 `RollPlan`을 돌려주고 `play(_:skipAnimation:onCue:)`가 그 계획을 재생해 지금의 `RollOutcome`을 돌려준다. 원격 재생은 두 단계를 이어 부르는 지금의 `roll`을 그대로 쓴다.

`GameSession.performRoll`은 눈을 받고 계획을 세운 뒤, `record.log`에 이번 굴림을 더한 로그와 이번 힌트를 더한 `throwHints`로 만든 payload의 전송을 연출과 동시에 시작하고(`async let`) 둘 다 끝나기를 기다리며, `record.log`·`throwHints`·`visibleState`는 지금처럼 착지한 뒤에 바꾼다. 굴림을 이미 올렸으므로 `perform`의 `.roll` 갈래는 굴림 뒤에 `publishProgressIfOnline`을 다시 부르지 않는다.

### 5.5 요트 원격 재생의 뜸

`GameSession.replay`는 한 `RemoteUpdate`에서 새로 받은 이벤트 가운데 마지막 것 뒤에는 `remotePause`를 두지 않는다. 상대가 고정을 빠르게 여러 번 바꾸면 이벤트가 하나씩 따로 도착하는데, 지금은 이벤트마다 600~700ms를 쉬어 내 화면이 점점 뒤처지기 때문이다. `committed`와 `turnAdvanced`는 같은 묶음으로 오므로 그 사이의 1.5초는 그대로 남고, 끊겼다 따라잡을 때처럼 여러 이벤트가 한 번에 오면 이벤트 사이의 뜸도 그대로 남는다.

### 5.6 컵퐁 던지기를 놓는 순간 올린다

`CupPongScreen`의 끌기가 끝나면 시뮬레이션을 만들고, 던지기 직전의 시점 좌석과 목표 컵과 두 좌석의 남은 컵 수를 `frozen`으로 묶은 뒤 `isThrowing`을 세우고, `play(shot)`과 공의 연출을 동시에 시작한다. 화면은 `frozen`이 있는 동안 시점·컵·머리글·명패를 그 값으로 그리고, `match.log.moves.count`가 바뀌어도 던지는 동안에는 배너를 띄우지 않으며, 연출이 끝나면 `frozen`과 `vanishing`을 함께 거둔 뒤 그때의 상태로 배너를 띄운다. 알까기의 `playing`·`replayingSeat`·`announceTurn`과 같은 방식이고, 받는 쪽 재생 경로는 바뀌지 않는다.

### 5.7 파일

| 파일 | 책임 |
|---|---|
| `supabase/migrations/20261022_live_broadcast.sql` | 4.1의 정책과 트리거 |
| `App/Online/TurnTransport.swift` | `LiveFrame`, `sendLive`·`live`, 메모리 전송의 순간 상태 |
| `App/Online/SupabaseTurnTransport.swift` | `move`·`live` 송수신, 조건부 갱신, 보류분 규칙, `fastPathDeliveries` |
| `App/Game/OnlineMatch.swift` | `publishLive`, `remoteLive`, 묶기와 비우기 |
| `App/Scene3D/DiceStage.swift` | `planRoll`·`play` |
| `App/Game/GameSession.swift` | 굴림 선전송, 묶음 끝 뜸 없애기 |
| `App/Games/Omok/OmokScreen.swift` | 고른 교차점 송수신과 상대 미리보기 |
| `App/Games/Alkkagi/AlkkagiScreen.swift` | 당김·배치 송수신과 상대 당김선·초안 |
| `App/Games/CupPong/CupPongScreen.swift` | 놓는 순간 전송, `frozen`, 조준 중 송수신 |
| `README.md` | 온라인 대전 절의 전달 경로와 순간 상태 |

## 6. 호환

빌드 11 이하 앱은 `UPDATE`만 구독하므로 `move`와 `live`를 받지 않고 DB 경로로 지금처럼 동작하며, 새 앱은 구버전 상대에게서 `move`가 오지 않아도 DB 경로로 받으므로 섞여 두어도 판이 이어진다. 새 앱끼리만 빠른 길과 순간 상태가 보인다.

## 7. 테스트

| 대상 | 테스트 |
|---|---|
| 메모리 전송 | 단위: `sendLive`가 짝의 `live`로 가고 기본 구현은 빈 스트림이다 |
| 순간 상태 묶기 | 단위: 100ms 안에 여러 값을 보내면 마지막 값 하나만 나가고, `nil`은 바로 나가며, 같은 값은 다시 나가지 않는다 |
| 순간 상태 거르기 | 단위: `eventCount`가 내 로그와 다르면 무시하고, 상대 수가 오면 `remoteLive`가 비며, 로컬 2인은 아무것도 보내지 않는다 |
| 요트 선전송 | 단위: 굴림의 payload가 나갈 때 `record.log`에는 아직 그 굴림이 없고 payload의 `eventCount`가 하나 크며, 굴림 하나에 payload가 한 번만 나간다 |
| 요트 뜸 | 단위: 고정 하나만 담은 갱신을 받으면 뜸 없이 바로 다음 갱신을 재생한다(뜸 길이를 주입할 수 있게 하거나 `reduceMotion`을 끈 채 시간을 잰다) |
| 순서 보호 | 통합: 더 작은 `event_count`의 조건부 갱신은 행을 바꾸지 않고, 조건 없이 줄이는 갱신은 트리거가 거절한다 |
| 빠른 길 | 통합: 기존 지연 테스트를 돌리며 게스트 전송의 `fastPathDeliveries`가 0보다 크고 중앙값이 1.5초 아래다 |
| 순간 상태 전달 | 통합: 호스트가 보낸 `live`가 게스트 `live` 스트림에 닿는다 |
| 권한 | 통합: 참가자가 아닌 계정은 그 토픽에 브로드캐스트를 보낼 수 없다(구독이 거절되므로 REST `httpSend`가 실패하는지로 확인한다) |
| 화면 | 시뮬레이터 두 대로 오목 미리보기, 알까기 당김선과 배치, 컵퐁 조준 표시와 던지기 동시 시작을 눈으로 확인한다 |

## 8. 치르는 값

- 빠른 길로 받은 수는 DB에 아직 없을 수 있어, 보낸 쪽의 DB 갱신이 서버 거절로 끝나면 받는 쪽은 서버에 없는 수를 들고 있게 된다. 서버가 거절하는 것은 끝났거나 버려진 판뿐이라 다음에 판을 열면 서버 상태로 돌아간다.
- 순간 상태는 조작된 클라이언트가 거짓으로 보낼 수 있지만 그림일 뿐이고 수는 지금처럼 `canApply`로 검증한다.
- 무료 티어에서는 동시에 조준하는 판이 다섯을 넘으면 초당 메시지 한도에 닿으므로, 사용자가 늘면 보내는 빈도를 낮추거나 유료 플랜으로 한도를 올려야 한다.
