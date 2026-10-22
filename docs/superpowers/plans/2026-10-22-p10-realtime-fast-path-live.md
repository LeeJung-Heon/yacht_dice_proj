# P10 — 온라인 대전 빠른 전달과 순간 상태 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 확정된 수가 DB를 기다리지 않고 채널로 먼저 가고, 요트 굴림과 컵퐁 던지기가 두 화면에서 거의 함께 시작하며, 오목·알까기·컵퐁에서 상대의 확정 전 손놀림이 보인다.

**Architecture:** `SupabaseTurnTransport`가 이미 구독 중인 비공개 채널 `match:<id>`에 클라이언트 브로드캐스트 `move`(로그 전체)와 `live`(순간 상태)를 더하고, DB는 조건부 갱신과 감소 거절 트리거로 계속 판의 기준이 된다. `OnlineMatch<G>`가 순간 상태의 묶기·거르기·비우기를 맡고 각 화면은 자기 게임의 작은 Codable 값만 보내고 그린다. 요트는 `DiceStage`의 계획·재생을 나눠 굴림을 착지 전에 올리고, 컵퐁은 놓는 순간 수를 올리며 착지까지 화면을 묶는다.

**Tech Stack:** Supabase Realtime Broadcast(비공개 채널), Postgres 트리거, supabase-swift 2.55.1(`RealtimeChannelV2.broadcast(event:message:)`, `broadcastStream(event:)`, `httpSend`), SwiftUI, Swift Testing, XCTest UI.

**Spec:** `docs/superpowers/specs/2026-10-22-p10-realtime-fast-path-live-design.md`

## Global Constraints

- iOS 18.0 이상, Swift 6, `SWIFT_STRICT_CONCURRENCY: complete`. Xcode 프로젝트는 `xcodegen generate`로 만든다.
- Supabase SDK는 `App/Online` 아래에서만 import한다. `GameSession`·`OnlineMatch`·화면은 `TurnTransport`만 안다. `GameCore`에는 순간 상태 타입을 넣지 않는다.
- 빌드·테스트의 `-derivedDataPath`는 저장소 밖을 가리킨다(`$SCRATCH/dd`, `SCRATCH=/private/tmp/claude-501/-Users-leejungheon-Library-Mobile-Documents-com-apple-CloudDocs-yacht-dice-proj/8bf6896e-6449-4a26-ae36-cc8621d77f4c/scratchpad`).
- 단위 테스트 명령(시뮬레이터 `iPhone 17 Pro`, id `64A5E02A-510C-4E97-AFF0-5BB8AFA368EB`):
  ```sh
  xcodebuild -project YachtDice.xcodeproj -scheme YachtDice \
    -destination 'id=64A5E02A-510C-4E97-AFF0-5BB8AFA368EB' -derivedDataPath "$SCRATCH/dd" \
    -only-testing:YachtDiceTests/<Suite 구조체 이름> test 2>&1 | grep -E "error:|✘|✔ Test run|Test run with"
  ```
  기준선은 단위 테스트 192개 통과다.
- 통합 테스트는 `TEST_RUNNER_YACHT_SUPABASE_E2E=1`일 때만 돌며, 익명 가입이 같은 IP에서 시간당 30회로 제한되므로 새 통합 테스트는 기존 계정 쌍을 재사용한다.
- 순간 상태: 이벤트 이름 `live`, 묶음 간격 `100ms`, 채널 페이로드 `{"event_count": n, "state": <JSON|null>}`. 빠른 길: 이벤트 이름 `move`, 페이로드 `{"log": <JSON>, "event_count": n, "throws": [ThrowHint]}`.
- 문구: 컵퐁 받는 쪽 "상대가 조준 중"(식별자 `cuppong.remoteAiming`). 기존 접근성 식별자는 유지한다.
- 커밋 메시지는 Conventional Commits, 한국어 제목(`~한다`), 본문은 왜만, 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. 브랜치는 `feat/p10-realtime-live`이고 푸시하지 않는다.
- 운영 DB(프로젝트 ref `lkernselwouldtuialjh`)에 마이그레이션을 적용하기 전에 사용자의 확인을 받는다.

## Review Focus

- 상대가 보낸 순간 상태의 알까기 돌 번호·초안 개수·오목 좌표가 범위를 벗어나도 앱이 죽지 않고 그리지 않아야 한다 → Task 5, 6의 검증 테스트.
- 끌던 중 화면을 떠나면 상대 화면에 멈춘 조준이 남지 않아야 한다 → Task 1의 `stop()` 테스트, Task 5~7의 비활성 처리.
- 상대 수가 온 뒤에 늦게 도착한 그 전 차례의 순간 상태는 무시해야 한다 → Task 1의 옛 프레임 테스트.
- 굴림 전송이 실패하거나 늦어도 내 화면의 굴림은 착지하면 드러나고 오류 띠가 떠야 한다 → Task 4의 실패·지연 테스트.
- 로컬 2인 컵퐁에서 빗나가 차례가 넘어가도 공이 나는 동안 시점과 머리글이 뒤집히지 않아야 한다 → Task 7의 UI 테스트 단언.

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `App/Online/TurnTransport.swift` | `LiveFrame`, `sendLive`·`live`와 기본 구현, 메모리 전송의 순간 상태·테스트 훅 (Task 1) |
| `App/Game/OnlineMatch.swift` | `publishLive`, `remoteLive`, 묶기·거르기·비우기 (Task 1) |
| `App/Online/RealtimeMessages.swift` (새 파일) | `MoveMessage`, `LiveMessage` 채널 페이로드 (Task 2) |
| `App/Online/SupabaseTurnTransport.swift` | `move`·`live` 송수신, 조건부 갱신, 보류 규칙, `fastPathDeliveries` (Task 2) |
| `App/Scene3D/DiceStage.swift` | `RollPlan`, `planRoll`, `play` (Task 3) |
| `App/Game/GameSession.swift` | 굴림 선전송, 묶음 끝 뜸 없애기 (Task 4) |
| `App/Games/Omok/OmokLive.swift` (새 파일), `OmokScreen.swift` | 오목 순간 상태 (Task 5) |
| `App/Games/Alkkagi/AlkkagiLive.swift` (새 파일), `AlkkagiScreen.swift` | 알까기 순간 상태와 보간 (Task 6) |
| `App/Games/CupPong/CupPongScreen.swift` | 놓는 순간 전송, `frozen`, 조준 중 (Task 7) |
| `supabase/migrations/20261022_live_broadcast.sql`, `Tests/YachtDiceTests/SupabaseE2ETests.swift`, `README.md`, 스펙 | 서버, 통합 검증, 문서 (Task 8) |

---

### Task 1: 순간 상태 전송 계층과 `OnlineMatch`

**Files:**
- Modify: `App/Online/TurnTransport.swift`, `App/Game/OnlineMatch.swift`
- Create: `Tests/YachtDiceTests/OnlineMatchLiveTests.swift`
- Modify: `Tests/YachtDiceTests/TurnTransportTests.swift`

**Interfaces:**
- Produces:
  - `struct LiveFrame: Sendable, Equatable { let eventCount: Int; let state: Data? }`
  - `TurnTransport`에 `func sendLive(_ frame: LiveFrame) async`, `var live: AsyncStream<LiveFrame> { get }` (기본: 아무것도 안 함, 곧 끝나는 스트림)
  - `InMemoryTurnTransport`: `var sentLive: [LiveFrame]`, `func emitPresence(_ uids: Set<String>)`, `func emitConnection(_ connected: Bool)`, `connection` 스트림 구현
  - `OnlineMatch`: `static let liveInterval: Duration = .milliseconds(100)`, `func publishLive<L: Encodable>(_ state: L?)`, `private(set) var remoteLive: Data?`, `func remoteLive<L: Decodable>(as type: L.Type) -> L?`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`TurnTransportTests`에 "메모리 전송의 순간 상태는 짝에게만 간다"(A의 `sendLive`가 B의 `live`로 오고 A의 `sentLive`에 남는다)와 "기본 구현의 live는 빈 스트림이다"를 더한다. `OnlineMatchLiveTests`는 `OnlineMatchTests.makePair()`와 같은 오목 쌍을 쓰고, 보낸 것은 `ta.sentLive`의 `state`를 `Omok.Move?`로 디코드해 비교한다.

```swift
@Test("100ms 안에 보낸 값은 처음 것과 마지막 것만 나간다")
// a.publishLive(Move(1,1)); (2,2); (3,3); 250ms 뒤 → [(1,1), (3,3)], 모두 eventCount 0
@Test("nil은 바로 나가고 들고 있던 값을 버린다")
// (1,1); (2,2); nil → 곧바로 [(1,1), nil], 250ms 뒤에도 같다
@Test("같은 값은 다시 보내지 않는다")
// (1,1); 150ms; (1,1) → 하나
@Test("내 차례가 아니면 보내지 않는다")
// b.publishLive(Move(1,1)) → tb.sentLive.isEmpty
@Test("상대의 순간 상태가 보이고 상대 수가 오면 비워진다")
// a.publishLive((4,4)) → b.remoteLive(as: Omok.Move.self) == (4,4); a.play((4,4)) → b.waitForIncoming() → b.remoteLive == nil
@Test("내 로그와 수가 다른 순간 상태는 무시한다")
// a.play((4,4)); b.waitForIncoming(); ta.sendLive(LiveFrame(eventCount: 0, state: (5,5))) → b.remoteLive == nil
// ta.sendLive(LiveFrame(eventCount: 7, ...)) → nil
@Test("상대가 채널을 떠나거나 연결이 끊기면 비워진다")
// b가 (4,4)를 본 뒤 tb.emitPresence([]) → nil; 다시 받은 뒤 tb.emitConnection(false) → nil
@Test("stop()은 보낸 순간 상태를 nil로 거둔다")
// a.publishLive((1,1)); a.stop() → ta.sentLive.last?.state == nil
@Test("로컬 2인은 아무것도 보내지 않고 remoteLive가 없다")
```

- [ ] **Step 2: 실패를 확인한다**

Run: 단위 테스트 명령, `-only-testing:YachtDiceTests/OnlineMatchLiveTests -only-testing:YachtDiceTests/TurnTransportTests`
Expected: `sendLive`·`publishLive`가 없어 컴파일 실패

- [ ] **Step 3: 전송 계층을 구현한다**

`InMemoryTurnTransport.sendLive`는 `sentLive`에 더하고 짝의 `live` 연속체로 넘기며, `emitPresence`·`emitConnection`은 자기 스트림에 흘린다.

- [ ] **Step 4: `OnlineMatch`의 순간 상태를 구현한다**

`publishLive`는 `JSONEncoder`로 인코딩한 값이 마지막으로 보낸 값과 같으면 버리고, 비nil 값은 내 차례(`isLocalTurn`)이고 전송이 있을 때만 다루며, 마지막으로 보낸 지 `liveInterval`이 지났으면 바로 보내고 아니면 들고 있다가 간격이 찰 때 가장 최근 것만 보낸다. `nil`은 마지막으로 보낸 값이 비nil일 때만, 차례와 무관하게, 들고 있던 값을 버리고 바로 보낸다. 프레임의 `eventCount`는 보내는 순간의 `log.moves.count`이고, 보내기는 앞의 보내기 Task가 끝난 뒤 잇는 사슬로 순서를 지킨다. `startListening`은 `live` 루프를 더해 `eventCount == log.moves.count`일 때만 `remoteLive`를 바꾸고, `replay`의 시작·presence에서 상대가 빠질 때·연결이 끊길 때 `remoteLive = nil`로 비운다. `stop()`은 들고 있던 값을 버리고 `publishLive(nil)` 규칙대로 거둔 뒤 루프를 접는다.

- [ ] **Step 5: 통과를 확인한다**

Run: Step 2와 같은 명령
Expected: 새 테스트와 기존 `TurnTransportTests` 모두 통과

- [ ] **Step 6: 커밋한다**

```bash
git add App/Online/TurnTransport.swift App/Game/OnlineMatch.swift Tests/YachtDiceTests/OnlineMatchLiveTests.swift Tests/YachtDiceTests/TurnTransportTests.swift
git commit -m "feat(online): 확정 전 손놀림을 상대에게 흘리는 순간 상태를 더한다"
```

---

### Task 2: Supabase 전송의 빠른 길과 순간 상태

**Files:**
- Create: `App/Online/RealtimeMessages.swift`, `Tests/YachtDiceTests/RealtimeMessagesTests.swift`
- Modify: `App/Online/SupabaseTurnTransport.swift`

**Interfaces:**
- Consumes: `LiveFrame`, `TurnTransport.sendLive`·`live` (Task 1), `TurnPayload`, `RemoteUpdate`, `ThrowHint`, `JSONValue`(`App/Online/MatchRow.swift`)
- Produces:
  - `struct MoveMessage: Codable, Equatable { let log: JSONValue; let eventCount: Int; let hints: [ThrowHint] }`, 키 `log`·`event_count`·`throws`, `init(_ payload: TurnPayload) throws`, `func remoteUpdate() throws -> RemoteUpdate`
  - `struct LiveMessage: Codable, Equatable { let eventCount: Int; let state: JSONValue? }`, 키 `event_count`·`state`, `init(_ frame: LiveFrame) throws`, `func frame() throws -> LiveFrame`
  - `SupabaseTurnTransport.fastPathDeliveries: Int`(진단용), `lastBroadcastError: String?`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
@Test("MoveMessage는 SDK의 JSONObject로 바꿨다 되돌려도 같은 RemoteUpdate가 된다")
// TurnPayload(log: 요트 로그 한 턴, eventCount: 3, hints: [힌트 하나], ...) → MoveMessage → JSONObject(_:)
// → AnyJSON.object(...).decode(as: MoveMessage.self) → remoteUpdate()의 log를 MatchLog.decoded로 읽은 값·eventCount·hints가 원래와 같다
@Test("LiveMessage는 state를 JSON 그대로 싣고 nil은 nil로 돌아온다")
// LiveFrame(eventCount: 2, state: {"x":3,"y":4}) → 인코딩한 JSON 문자열에 "state":{"x":3,"y":4}가 있다(base64가 아니다) → frame() == 원래
// LiveFrame(eventCount: 2, state: nil) → frame().state == nil
@Test("깨진 페이로드는 디코드에 실패한다")
// ["event_count": "x"] → MoveMessage, LiveMessage 모두 throw
```

- [ ] **Step 2: 실패를 확인한다**

Run: 단위 테스트 명령, `-only-testing:YachtDiceTests/RealtimeMessagesTests`
Expected: 타입이 없어 컴파일 실패

- [ ] **Step 3: `RealtimeMessages.swift`를 구현하고 통과를 확인한다**

Run: Step 2와 같은 명령
Expected: PASS

- [ ] **Step 4: `SupabaseTurnTransport`를 고친다**

`listen()`이 만든 채널을 잠금 아래 속성으로 들고 빠져나갈 때 지운다. 채널 상태가 `.subscribed`일 때만 `publish`가 `channel.broadcast(event: "move", message: MoveMessage(payload))`를 먼저 보내고(구독 전이면 SDK의 REST 대체를 타지 않도록 건너뛴다, 실패는 `lastBroadcastError`에만 남긴다), 이어서 DB 갱신을 `.eq("id", …).lt("event_count", value: update.eventCount)`로 보낸다. `retryPendingIfAny`도 같은 조건을 쓰고, 보류분은 지금 보류분보다 큰 `eventCount`일 때만 바뀌며, 성공한 갱신은 그보다 크지 않은 보류분만 지운다. 수신은 기존 task group에 `broadcastStream(event: "move")`(메시지의 `payload`를 `MoveMessage`로) 루프와 `broadcastStream(event: "live")`(`LiveMessage`로) 루프를 더하고, `deliver`를 `RemoteUpdate`와 빠른 길 여부를 받게 바꿔 빠른 길로 들어와 새 것으로 인정된 것만 `fastPathDeliveries`를 올린다. `sendLive`는 구독 중일 때만 `live`로 보낸다. 채널 설정의 `receiveOwnBroadcasts`는 기본값 그대로 둔다.

- [ ] **Step 5: 전체 단위 테스트가 통과하는지 확인한다**

Run: 단위 테스트 명령, `-only-testing:YachtDiceTests`
Expected: 기준선 192개와 Task 1·2의 새 테스트 모두 통과(네트워크 경로는 Task 8의 통합 테스트가 확인한다)

- [ ] **Step 6: 커밋한다**

```bash
git add App/Online/RealtimeMessages.swift App/Online/SupabaseTurnTransport.swift Tests/YachtDiceTests/RealtimeMessagesTests.swift
git commit -m "feat(online): 수를 DB보다 먼저 채널로 보내고 옛 갱신이 새 로그를 덮지 않게 한다"
```

---

### Task 3: `DiceStage` 굴림 계획과 재생 나누기

**Files:**
- Modify: `App/Scene3D/DiceStage.swift`, `Tests/YachtDiceTests/DiceStageTests.swift`

**Interfaces:**
- Produces:
  - `struct RollPlan { let values: [Int]; let slots: [Int]; let trajectoryID: UInt16; let direction: ThrowDirection; let yaws: [Int] }` (궤적과 오프셋은 내부 저장 속성으로 든다; 슬롯이 비었거나 궤적이 없으면 재생할 것이 없는 계획이다)
  - `func planRoll(values: [Int], slots: [Int], direction: ThrowDirection, hint: ThrowHint? = nil) -> RollPlan`
  - `func play(_ plan: RollPlan, skipAnimation: Bool, onCue: ((CollisionCue) -> Void)? = nil) async -> RollOutcome`
  - 기존 `roll(values:slots:direction:skipAnimation:hint:onCue:)`은 시그니처를 유지하고 `play(planRoll(...))`가 된다

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
@Test("계획을 세우기만 하면 주사위가 움직이지 않는다")
// 다섯 슬롯의 orientation을 기록 → planRoll([1,2,3,4,5], slots: 0..<5, direction: .center) → orientation이 그대로다
@Test("계획대로 재생하면 계획의 궤적·회전으로 요청한 눈에 멈춘다")
// plan = planRoll(...); outcome = await play(plan, skipAnimation: true)
// outcome.trajectoryID == plan.trajectoryID, outcome.yaws == plan.yaws, outcome.direction == plan.direction, faceUpValue(slot: i) == values[i]
@Test("힌트로 세운 계획은 힌트의 궤적과 회전을 쓴다")
// 첫 스테이지의 계획으로 ThrowHint를 만들고 두 번째 스테이지에서 planRoll(hint:) → trajectoryID·yaws가 같다
```

- [ ] **Step 2: 실패를 확인한다**

Run: 단위 테스트 명령, `-only-testing:YachtDiceTests/DiceStageTests`
Expected: `planRoll`이 없어 컴파일 실패

- [ ] **Step 3: `roll`의 앞부분(궤적·회전 선택)을 `planRoll`로, 리드인과 재생을 `play`로 옮긴다**

- [ ] **Step 4: 통과를 확인한다**

Run: Step 2와 같은 명령
Expected: 기존 `DiceStageTests`와 새 테스트 모두 통과

- [ ] **Step 5: 커밋한다**

```bash
git add App/Scene3D/DiceStage.swift Tests/YachtDiceTests/DiceStageTests.swift
git commit -m "refactor(scene): 굴림의 궤적 선택과 재생을 나눈다"
```

---

### Task 4: 요트 굴림을 착지 전에 올리고 원격 재생의 끝 뜸을 없앤다

**Files:**
- Modify: `App/Game/GameSession.swift`, `Tests/YachtDiceTests/GameSessionOnlineTests.swift`

**Interfaces:**
- Consumes: `DiceStage.planRoll`·`play`·`RollPlan` (Task 3)

- [ ] **Step 1: 실패하는 테스트를 쓴다**

테스트 파일에 두 전송 대역을 둔다: `GatedTransport`는 `publish`가 payload를 기록한 뒤 테스트가 `open()`할 때까지 멈추고, `FailingTransport`는 `publish`가 늘 `URLError(.notConnectedToInternet)`을 던진다(둘 다 `incoming`은 끝나지 않는 빈 스트림).

```swift
@Test("굴림은 착지 전에 한 번만 올라가고 내 화면은 전송을 기다리지 않는다")
// GatedTransport로 A 세션(reduceMotion = true). Task { await a.send(.roll) }
// 기록된 payload가 생길 때까지 기다린다 → payload.eventCount == 1, MatchLog.decoded(payload.log).events == [.rolled([3,3,3,3,3])], payload.hints.count == 1
// 게이트가 닫힌 채로 a.visibleState.rollsRemaining == 2가 된다(2초 안)
// open() 뒤 send가 끝나면 기록된 payload는 여전히 1개다
@Test("굴림 전송이 실패해도 굴림은 내 화면에 드러나고 오류가 남는다")
// FailingTransport: await a.send(.roll) → a.visibleState.rollsRemaining == 2, a.lastTransportError == "서버에 보내지 못해 다시 시도하는 중이다"
@Test("따로 도착한 고정 둘은 뜸 없이 이어 재생한다")
// 메모리 쌍, a.reduceMotion = true, b.reduceMotion = false
// await a.send(.roll); await b.waitForIncoming()
// await a.send(.toggleHold(0)); await a.send(.toggleHold(1))
// b.visibleState.held에 0이 들어온 시각 t0과 1이 들어온 시각 t1을 10ms 간격으로 재고(최대 3초) t1 - t0 < .milliseconds(300)
```

- [ ] **Step 2: 실패를 확인한다**

Run: 단위 테스트 명령, `-only-testing:YachtDiceTests/GameSessionOnlineTests`
Expected: 첫 테스트는 게이트가 닫힌 동안 굴림이 드러나지 않아 실패, 셋째는 간격이 600ms 안팎이라 실패

- [ ] **Step 3: `performRoll`을 고친다**

눈을 받고 `planRoll`로 계획을 세운 뒤, 지금 `record.log`에 `.rolled(values)`를 더한 로그와 `throwHints`에 이번 힌트(이벤트 번호 = 지금 이벤트 수)를 더한 목록으로 payload를 만들어(`turnSeat`는 지금 좌석, `finished: false`) 전송을 `async let`으로 시작하고, `play`로 연출한 뒤 지금처럼 힌트·이벤트를 더하고 `visibleState`를 바꾸고 `driver.submit`·`onLogChanged`를 부른 다음에야 전송을 기다리며, 전송 오류는 `publishProgressIfOnline`과 같은 문구로 `lastTransportError`에 남긴다. 온라인이 아니면 payload를 만들지 않는다. `perform`의 `.roll` 갈래에서 `publishProgressIfOnline()`을 지운다.

- [ ] **Step 4: `replay(remote:)`를 고친다**

새 이벤트 가운데 마지막 것 뒤에는 `remotePause`를 부르지 않는다.

- [ ] **Step 5: 통과를 확인한다**

Run: 단위 테스트 명령, `-only-testing:YachtDiceTests/GameSessionOnlineTests -only-testing:YachtDiceTests/GameSessionTests`
Expected: 새 테스트와 기존 `한_턴_전파`·`실시간_중계`·12턴 완주 모두 통과

- [ ] **Step 6: 커밋한다**

```bash
git add App/Game/GameSession.swift Tests/YachtDiceTests/GameSessionOnlineTests.swift
git commit -m "feat(yacht): 굴림을 착지 전에 올리고 따로 온 이벤트 뒤에는 쉬지 않는다"
```

---

### Task 5: 오목 — 고른 교차점을 상대에게 보인다

**Files:**
- Create: `App/Games/Omok/OmokLive.swift`, `Tests/YachtDiceTests/OmokLiveTests.swift`
- Modify: `App/Games/Omok/OmokScreen.swift`

**Interfaces:**
- Consumes: `OnlineMatch.publishLive`·`remoteLive(as:)` (Task 1)
- Produces: `enum OmokLive { static func remotePreview(_ move: Omok.Move?, in state: Omok.State) -> Omok.Move? }` — 순간 상태 값은 `Omok.Move` 그대로다

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
@Test("판 밖 좌표는 그리지 않는다")   // (19,0), (0,19), (-1,3) → nil
@Test("이미 돌이 있는 자리는 그리지 않는다")   // (7,7)을 둔 판에서 (7,7) → nil
@Test("빈 교차점은 그대로 그린다")   // (3,4) → (3,4); nil → nil
```

- [ ] **Step 2: 실패를 확인한다**

Run: 단위 테스트 명령, `-only-testing:YachtDiceTests/OmokLiveTests`
Expected: `OmokLive`가 없어 컴파일 실패

- [ ] **Step 3: `OmokLive`를 구현하고 화면을 잇는다**

교차점을 고르면 `match.publishLive(move)`를 부르고, 화면을 떠날 때와 `scenePhase`가 `.active`가 아니게 될 때 `match.publishLive(Omok.Move?.none)`을 부른다. 판의 미리보기는 내 차례면 지금의 `preview`와 `localSeat`를, 아니면 `OmokLive.remotePreview(match.remoteLive(as: Omok.Move.self), in: match.state)`와 지금 차례 좌석을 넘긴다.

- [ ] **Step 4: 통과와 빌드를 확인한다**

Run: 단위 테스트 명령, `-only-testing:YachtDiceTests/OmokLiveTests -only-testing:YachtDiceTests/OnlineMatchTests`
Expected: PASS

- [ ] **Step 5: 커밋한다**

```bash
git add App/Games/Omok/OmokLive.swift App/Games/Omok/OmokScreen.swift Tests/YachtDiceTests/OmokLiveTests.swift
git commit -m "feat(omok): 상대가 고른 교차점을 반투명 돌로 보인다"
```

---

### Task 6: 알까기 — 당김과 배치 초안을 상대에게 보인다

**Files:**
- Create: `App/Games/Alkkagi/AlkkagiLive.swift`, `Tests/YachtDiceTests/AlkkagiLiveTests.swift`
- Modify: `App/Games/Alkkagi/AlkkagiScreen.swift`

**Interfaces:**
- Consumes: `OnlineMatch.publishLive`·`remoteLive(as:)` (Task 1), `AlkkagiGeometry.clampPull`·`flick`·`preview`
- Produces:
  - `enum AlkkagiLive: Codable, Equatable { case pull(stone: Int, to: Alkkagi.Point); case setup(draft: [Alkkagi.Point], dragging: Dragging?) }`, `struct Dragging: Codable, Equatable { let stone: Int; let at: Alkkagi.Point }`
  - `func aim(in state: Alkkagi.State) -> (stone: Int, from: Alkkagi.Point, to: Alkkagi.Point)?` — `.play` 단계이고 돌 번호가 `0..<Alkkagi.stonesPerSeat`이며 지금 차례 좌석의 그 돌이 판에 있을 때만
  - `func draft() -> (points: [Alkkagi.Point], dragging: Dragging?)?` — 초안이 `stonesPerSeat`개이고 끄는 돌 번호가 범위 안일 때만
  - `struct AlkkagiLiveTrack { init(_ point: Alkkagi.Point, at date: Date); mutating func update(_ point: Alkkagi.Point, at date: Date); func point(at date: Date) -> Alkkagi.Point; func isMoving(at date: Date) -> Bool }` — `update`는 그 시각의 보간 위치에서 새 값까지 100ms 동안 선형으로 잇는다

- [ ] **Step 1: 실패하는 테스트를 쓴다**

플레이 단계 상태는 `MoveLog<Alkkagi>`에 두 좌석의 `.setup(Alkkagi.defaultPlacement(seat:))`를 차례대로 더해 만든다.

```swift
@Test("두 경우 모두 인코딩을 왕복한다")
@Test("범위 밖 돌 번호와 판에 없는 돌은 당김을 그리지 않는다")   // stone 5, -1 → nil; 떨어진 돌 → nil
@Test("배치 단계에는 당김을 그리지 않는다")   // 빈 MoveLog의 상태에서 .pull → nil
@Test("올바른 당김은 그 돌의 자리에서 시작한다")   // aim?.from == state.stones[seat][stone]
@Test("초안이 다섯이 아니거나 끄는 돌 번호가 범위 밖이면 버린다")   // 4개, 6개, dragging.stone 5 → nil
@Test("보간은 0ms에 직전 값, 50ms에 중간, 100ms 뒤에 새 값이다")   // (0,0)→(1000,2000): (0,0), (500,1000), (1000,2000); 100ms 뒤 isMoving == false
```

- [ ] **Step 2: 실패를 확인한다**

Run: 단위 테스트 명령, `-only-testing:YachtDiceTests/AlkkagiLiveTests`
Expected: `AlkkagiLive`가 없어 컴파일 실패

- [ ] **Step 3: `AlkkagiLive.swift`를 구현하고 통과를 확인한다**

Run: Step 2와 같은 명령
Expected: PASS

- [ ] **Step 4: 보내는 쪽을 잇는다**

튕김 끌기의 `onChanged`는 잡은 돌과 손끝이 있으면 `.pull(stone:to:)`를, `onEnded`는 맨 앞에서 `AlkkagiLive?.none`을 보낸다. 내 배치 차례가 열리면(`onChange(of: placingSeat)`에서 초안을 기본 배치로 채울 때) `.setup(draft:dragging: nil)`을, 배치 끌기 중에는 `.setup(draft: myDraft, dragging: Dragging(stone:at: finger))`를, 놓으면 그 결과 초안으로 `.setup(draft:dragging: nil)`을 보낸다. 화면을 떠날 때와 `scenePhase`가 `.active`가 아니게 될 때 `nil`을 보낸다.

- [ ] **Step 5: 받는 쪽을 잇는다**

내 차례가 아닐 때 `remoteLive(as: AlkkagiLive.self)`를 읽어, 플레이 단계의 `aim`은 손끝을 `AlkkagiLiveTrack`으로 이은 점으로 `drawnPull`(`clampPull`)·`previewPath`(`flick`+`preview`)·`highlight`를 보내는 쪽 화면과 같게 만들고, 배치 단계의 `draft`는 `displayedStones`의 상대 좌석 자리에 초안을 얹고 끄는 돌을 `dragging:`에 상대 좌석으로 넘긴다. `TimelineView`는 재생 중이거나 트랙이 움직이는 동안 돈다.

- [ ] **Step 6: 빌드와 기존 알까기 테스트를 확인한다**

Run: 단위 테스트 명령, `-only-testing:YachtDiceTests/AlkkagiLiveTests -only-testing:YachtDiceTests/AlkkagiInterpolationTests -only-testing:YachtDiceTests/AlkkagiGeometryTests`
Expected: PASS

- [ ] **Step 7: 커밋한다**

```bash
git add App/Games/Alkkagi/AlkkagiLive.swift App/Games/Alkkagi/AlkkagiScreen.swift Tests/YachtDiceTests/AlkkagiLiveTests.swift
git commit -m "feat(alkkagi): 상대의 당김선과 배치 초안을 실시간으로 보인다"
```

---

### Task 7: 컵퐁 — 놓는 순간 올리고 조준 중을 보인다

**Files:**
- Modify: `App/Games/CupPong/CupPongScreen.swift`, `Tests/YachtDiceUITests/CupPongUITests.swift`

**Interfaces:**
- Consumes: `OnlineMatch.publishLive`·`remoteLive(as:)` (Task 1)
- Produces: 화면 파일 안의 `struct Live: Codable, Equatable { let aiming: Bool }`, `struct ThrowFreeze { let shooter: Int; let cups: [Bool]; let remaining: [Int] }`

- [ ] **Step 1: UI 테스트에 단언을 더한다**

`test_로컬_2인_한_번_던지면_결과가_보인다`에서 `press(forDuration:thenDragTo:)` 바로 뒤에 `XCTAssertEqual(turn.label, "나 차례", "공이 나는 동안 차례가 넘어가 보였다")`를 더한다. 놓는 순간 수를 넣고 화면을 묶지 않으면 빗나간 던지기에서 곧바로 "상대 차례"가 보여 실패한다.

- [ ] **Step 2: 던지기를 고친다**

끌기 `onChanged`의 첫 표본에서 `Live(aiming: true)`를, `onEnded`의 맨 앞에서 `Live?.none`을 보낸다. 놓으면 샷을 만든 뒤 `frozen = ThrowFreeze(shooter: shooter, cups: targetCups, remaining: [두 좌석의 남은 컵])`과 `isThrowing = true`를 세우고, `throwTask`에서 공 연출(`async let`)과 `match.play(shot)`을 동시에 시작해 둘 다 끝나면 `frozen`과 `vanishing`을 함께 거둔 뒤 차례 배너를 띄운다. `shooter`·`targetCups`·머리글의 컵 수와 차례·명패는 `frozen`이 있으면 그 값을 쓰고, `onChange(of: match.log.moves.count)`의 배너는 `isThrowing`이면 건너뛰며 배너 문구를 고르는 부분은 연출 뒤에도 부를 수 있게 함수로 뺀다. `onDisappear`는 `frozen`도 지우고 `Live?.none`을 보내며, `scenePhase`가 `.active`가 아니게 되면 `Live?.none`을 보낸다.

- [ ] **Step 3: 받는 쪽을 잇는다**

내 차례가 아니고 `remoteLive(as: Live.self)?.aiming == true`면 `displayedBall`이 던지는 자리의 공 `(x: 0, y: 0, height: 400)`을 돌려주고, 액션 바의 기다림 문구 대신 "상대가 조준 중"을 `cuppong.remoteAiming` 식별자로 보인다.

- [ ] **Step 4: UI 테스트와 빌드를 확인한다**

Run:
```sh
xcodebuild -project YachtDice.xcodeproj -scheme YachtDice -destination 'id=64A5E02A-510C-4E97-AFF0-5BB8AFA368EB' \
  -derivedDataPath "$SCRATCH/dd" -only-testing:YachtDiceUITests/CupPongUITests test 2>&1 | grep -E "error:|Test Case|Executed"
```
Expected: `CupPongUITests`의 두 테스트 통과

- [ ] **Step 5: 커밋한다**

```bash
git add App/Games/CupPong/CupPongScreen.swift Tests/YachtDiceUITests/CupPongUITests.swift
git commit -m "feat(cuppong): 놓는 순간 던지기를 올리고 상대의 조준 중을 보인다"
```

---

### Task 8: 서버 마이그레이션, 통합 검증, 문서

**Files:**
- Create: `supabase/migrations/20261022_live_broadcast.sql`
- Modify: `Tests/YachtDiceTests/SupabaseE2ETests.swift`, `README.md`, `docs/superpowers/specs/2026-10-22-p10-realtime-fast-path-live-design.md`

**Interfaces:**
- Consumes: `SupabaseTurnTransport.fastPathDeliveries`, `sendLive`·`live` (Task 1, 2)
- Produces: 정책 `participants send broadcast and presence`, 트리거 `matches_guard_event_count`(오류 문구 `event count must not decrease`)

- [ ] **Step 1: SQL을 쓴다**

`participants send presence` 정책을 지우고 같은 참가자 조건에 `realtime.messages.extension in ('broadcast', 'presence')`인 INSERT 정책을 만들며, `matches_guard_event_count()`(`security definer`, `search_path = ''`, `new.event_count < old.event_count`면 예외)와 `before update` 트리거를 만들고 함수 실행 권한을 `public, anon, authenticated`에서 거둔다. P6 마이그레이션의 `drop … if exists` 뒤 `create` 형식을 따른다.

- [ ] **Step 2: 통합 테스트를 쓴다**

```swift
// 지연(): 끝에 #expect(pair.tb.fastPathDeliveries > 0, "빠른 길로 도착한 수가 없다")
@Test("순간 상태가 상대 채널에 닿는다")
// makePair(); ta.sendLive(LiveFrame(eventCount: 0, state: {"x":1,"y":2})) → 5초 안에 tb.live에서 같은 프레임을 받는다
@Test("옛 갱신은 새 로그를 덮지 못하고 줄이는 갱신은 거절된다")
// 요트 방에서 호스트가 event_count를 5로 갱신 → ta.publish(eventCount 2인 payload) 뒤 행의 event_count == 5
// 조건 없이 ["event_count": 1]로 갱신 → PostgrestError.message == "event count must not decrease"
// 기존 "참가자가 아닌 계정은 비공개 채널을 구독할 수 없다"에 덧붙여: 그 계정이 setAuth 뒤 같은 토픽의 비공개 채널로 httpSend(event: "move", …)를 하면 실패한다
```

- [ ] **Step 3: 운영 적용 전에 사용자의 확인을 받는다**

적용할 SQL 전문과 영향(구버전 앱 동작은 그대로, 정책 확대와 트리거 추가뿐)을 보여 주고 확인을 기다린다.

- [ ] **Step 4: 운영 DB에 적용한다**

P6처럼 Supabase MCP `apply_migration`(이름 `live_broadcast`)으로 적용하고, MCP를 쓸 수 없으면 사용자에게 대시보드 SQL 편집기로 같은 SQL을 실행해 달라고 요청한다. `supabase db push`는 쓰지 않는다.

- [ ] **Step 5: 통합 테스트를 돌린다**

Run:
```sh
TEST_RUNNER_YACHT_SUPABASE_E2E=1 xcodebuild -project YachtDice.xcodeproj -scheme YachtDice \
  -destination 'id=64A5E02A-510C-4E97-AFF0-5BB8AFA368EB' -derivedDataPath "$SCRATCH/dd" \
  -only-testing:YachtDiceTests/SupabaseE2ETests test 2>&1 | grep -E "error:|✘|✔|지연 표본|Test run"
```
Expected: 새 테스트와 기존 통합 테스트 모두 통과, 지연 표본 출력. HTTP 429로 실패하면 한 시간 뒤 다시 돌린다.

- [ ] **Step 6: 전체 단위·UI 테스트를 돌린다**

Run: 단위 테스트 명령 `-only-testing:YachtDiceTests`, 이어서 `-only-testing:YachtDiceUITests`
Expected: 모두 통과

- [ ] **Step 7: 문서를 고친다**

README "온라인 대전" 절의 전달 경로 문장을 빠른 길(`move`)→DB 갱신(조건부)·트리거 브로드캐스트·폴링 순으로 고치고, 순간 상태(`live`, 100ms, 게임별 내용, 저장하지 않음)와 무료 티어 한도를 한 문단으로 더하며, 스펙 상태를 구현 완료와 측정한 지연으로 바꾼다. `writing-korean-prose` 문체를 따른다.

- [ ] **Step 8: 커밋한다**

```bash
git add supabase/migrations/20261022_live_broadcast.sql Tests/YachtDiceTests/SupabaseE2ETests.swift README.md docs/superpowers/specs/2026-10-22-p10-realtime-fast-path-live-design.md
git commit -m "feat(server): 참가자 브로드캐스트를 허용하고 event_count 감소를 막는다"
```
