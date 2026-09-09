# Yacht Dice P6 — 온라인 실시간 고도화 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 상대의 플레이가 50~150ms 안에 같은 던지기로 보이고, 상대의 접속·연결 상태가 화면에 보이며, 앱이 닫힌 상대에게 "내 차례" 푸시가 간다.

**Architecture:** 서버는 `matches` 갱신을 트리거로 비공개 채널에 브로드캐스트하고, 굴린 쪽이 궤적 힌트를 `throws` 열에 함께 올려 받는 쪽이 같은 궤적을 재생한다. 전송 프로토콜은 `RemoteUpdate(log, throws)`와 presence·연결 스트림을 갖고, `GameSession`은 힌트를 만들고 쓰는 것 외에는 그대로다. 푸시는 `turn_seat` 변경 트리거 → 웹훅 → Edge Function → APNs다.

**Tech Stack:** Supabase Realtime Broadcast(비공개 채널, Presence), Postgres 트리거·`pg_cron`, Edge Functions(Deno) + APNs HTTP/2, supabase-swift 2.55, UserNotifications, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-09-yacht-dice-p6-realtime-design.md`

## Global Constraints

- P2 계획의 전역 제약(Swift 6 strict concurrency, xcodegen, 저장소 밖 derivedData, 커밋 규칙, 시뮬레이터 id `64A5E02A-510C-4E97-AFF0-5BB8AFA368EB`)을 따른다.
- Supabase 프로젝트 ref `lkernselwouldtuialjh`. DDL은 MCP `apply_migration`으로 적용하고 같은 SQL을 `supabase/migrations/`에 파일로 남긴다.
- Supabase SDK와 GameKit은 `App/Online` 아래에서만 import한다. `GameSession`은 `TurnTransport`만 안다.
- 네트워크 통합 테스트는 `TEST_RUNNER_YACHT_SUPABASE_E2E=1`일 때만 돈다. 실행:
  ```sh
  TEST_RUNNER_YACHT_SUPABASE_E2E=1 xcodebuild -project YachtDice.xcodeproj -scheme YachtDice \
    -destination 'id=64A5E02A-510C-4E97-AFF0-5BB8AFA368EB' -derivedDataPath "$SCRATCH/dd" \
    -only-testing:YachtDiceTests/SupabaseE2ETests test
  ```
- 접근성 식별자는 유지한다. 새 식별자: `players.presence.<i>`, `online.connection`.

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `supabase/migrations/20260909_broadcast_throws.sql` | `throws`·`turn_seat` 열, 브로드캐스트 트리거, `realtime.messages` 정책, `abandoned` (Task 1) |
| `App/Online/ThrowHint.swift` | 힌트 모델 (Task 2) |
| `App/Scene3D/TrajectoryLibrary.swift`, `DiceStage.swift` | ID 조회, 지정 재생, 고른 값 반환 (Task 2) |
| `App/Online/TurnTransport.swift` | `RemoteUpdate`, 힌트 전송, presence·연결 스트림 (Task 3) |
| `App/Game/GameSession.swift` | 힌트 생성·사용, `opponentPresent`, `isConnected` (Task 3) |
| `App/Online/SupabaseTurnTransport.swift` | 비공개 브로드캐스트, Presence, 채널 상태, `throws`·`turn_seat` (Task 4) |
| `App/Views/PlayerStrip.swift`, `GameScreen.swift` | 접속 점, 연결 띠 (Task 5) |
| `supabase/migrations/20260909_device_tokens.sql`, `supabase/functions/notify-turn/` | 푸시 (Task 6) |
| `App/Online/PushRegistration.swift`, `App/YachtDiceApp.swift`, `App/YachtDice.entitlements`, `project.yml` | 토큰 등록, 알림 탭 (Task 6) |
| `README.md`, 스펙 | 문서 (Task 7) |

---

### Task 1: 서버 — 브로드캐스트 트리거, 힌트 열, 권한, 정리

**Files:**
- Create: `supabase/migrations/20260909_broadcast_throws.sql`

**Interfaces:**
- Produces: `matches.throws jsonb`, `matches.turn_seat smallint`, `matches.status` 값 `abandoned`, 비공개 토픽 `match:<id>`의 브로드캐스트 이벤트 `UPDATE`(payload `record` = 행), Presence 허용.

- [ ] **Step 1: SQL 작성**

```sql
-- 힌트와 다음 차례 좌석
alter table public.matches
  add column if not exists throws jsonb not null default '[]'::jsonb,
  add column if not exists turn_seat smallint;
alter table public.matches drop constraint if exists matches_status_check;
alter table public.matches add constraint matches_status_check
  check (status in ('waiting', 'playing', 'finished', 'abandoned'));

-- 갱신을 비공개 채널 match:<id>로 브로드캐스트한다 (WAL을 거치지 않아 빠르다)
create or replace function public.matches_broadcast()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.broadcast_changes(
    'match:' || new.id::text, tg_op, tg_op, tg_table_name, tg_table_schema, new, old);
  return null;
end;
$$;
drop trigger if exists matches_broadcast on public.matches;
create trigger matches_broadcast
  after update on public.matches
  for each row execute function public.matches_broadcast();

-- 참가자만 그 토픽의 브로드캐스트·Presence를 받고, Presence를 보낼 수 있다
drop policy if exists "participants receive match broadcasts" on realtime.messages;
create policy "participants receive match broadcasts" on realtime.messages
  for select to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and exists (
      select 1 from public.matches m
      where 'match:' || m.id::text = (select realtime.topic())
        and (select auth.uid()) in (m.host_uid, m.guest_uid)));
drop policy if exists "participants send presence" on realtime.messages;
create policy "participants send presence" on realtime.messages
  for insert to authenticated
  with check (
    realtime.messages.extension = 'presence'
    and exists (
      select 1 from public.matches m
      where 'match:' || m.id::text = (select realtime.topic())
        and (select auth.uid()) in (m.host_uid, m.guest_uid)));

-- 3일 넘게 멈춘 판은 버려진 것으로 본다
create or replace function public.mark_abandoned_matches()
returns integer
language sql
security definer
set search_path = ''
as $$
  with updated as (
    update public.matches set status = 'abandoned'
    where status = 'playing' and updated_at < now() - interval '3 days'
    returning 1)
  select count(*)::integer from updated;
$$;
revoke execute on function public.mark_abandoned_matches() from public, anon, authenticated;
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('mark-abandoned-matches', '*/10 * * * *', $$select public.mark_abandoned_matches()$$);
```

- [ ] **Step 2: 적용** — MCP `apply_migration`(name `broadcast_throws`)으로 적용하고 같은 SQL을 파일로 저장한다. `pg_cron`이 없다고 나오면 대시보드 Database → Extensions에서 켠 뒤 다시 적용한다.
- [ ] **Step 3: 검증** — MCP `execute_sql`로 `begin; update public.matches set event_count = event_count where false; rollback;`가 오류 없이 돌고, `select count(*) from realtime.messages`가 접근되며(0 이상), `get_advisors(security)`에 새 경고가 `matches_broadcast`·`mark_abandoned_matches`의 security definer 외에는 없는지 본다.
- [ ] **Step 4: 커밋** — `feat(server): 매치 갱신을 비공개 채널로 브로드캐스트하고 힌트 열을 더한다`

---

### Task 2: 던지기 힌트와 지정 재생

**Files:**
- Create: `App/Online/ThrowHint.swift`
- Modify: `App/Scene3D/TrajectoryLibrary.swift`, `App/Scene3D/DiceStage.swift`
- Test: `Tests/YachtDiceTests/DiceStageTests.swift`, `Tests/YachtDiceTests/ThrowHintTests.swift`

**Interfaces:**
```swift
struct ThrowHint: Codable, Equatable, Sendable {
    let event: Int          // 이 굴림이 로그에서 차지하는 이벤트 번호
    let trajectory: UInt16  // Trajectory.id
    let direction: UInt8    // ThrowDirection.rawValue
    let yaws: [Int]         // 굴린 주사위 순서대로 0...3
}
extension TrajectoryLibrary { func trajectory(id: UInt16) -> Trajectory? }
struct RollOutcome { let cues: [CollisionCue]; let trajectoryID: UInt16; let direction: ThrowDirection; let yaws: [Int] }
// DiceStage
func roll(values: [Int], slots: [Int], direction: ThrowDirection, skipAnimation: Bool,
          hint: ThrowHint? = nil, onCue: ((CollisionCue) -> Void)? = nil) async -> RollOutcome
```
힌트가 있고 그 궤적이 존재하며 `dieCount == slots.count`이면 그 궤적·방향·yaw를 쓰고, 아니면 지금처럼 고른다. 기존 호출부는 `.cues`를 쓴다.

- [ ] **Step 1: 실패하는 테스트**

`Tests/YachtDiceTests/ThrowHintTests.swift`:
```swift
import Testing
import Foundation
@testable import YachtDice

@Suite("던지기 힌트")
struct ThrowHintTests {
    @Test("JSON 왕복")
    func 왕복() throws {
        let hint = ThrowHint(event: 7, trajectory: 123, direction: 2, yaws: [0, 3, 1, 2, 0])
        let data = try JSONEncoder().encode([hint])
        #expect(try JSONDecoder().decode([ThrowHint].self, from: data) == [hint])
    }
}
```
`Tests/YachtDiceTests/DiceStageTests.swift`에 스위트 추가:
```swift
@Suite("주사위 무대 - 힌트 재생")
@MainActor
struct DiceStageHintTests {
    @Test("힌트를 주면 같은 궤적·회전으로 재생해 자세가 같다")
    func 같은_자세() async throws {
        let library = try TrajectoryLibrary.bundled()
        let a = DiceStage(library: library), b = DiceStage(library: library)
        let values = [2, 5, 1, 6, 3]
        let first = await a.roll(values: values, slots: [0, 1, 2, 3, 4], direction: .left, skipAnimation: true)
        let hint = ThrowHint(event: 0, trajectory: first.trajectoryID, direction: first.direction.rawValue, yaws: first.yaws)
        let second = await b.roll(values: values, slots: [0, 1, 2, 3, 4], direction: .right, skipAnimation: true, hint: hint)
        #expect(second.trajectoryID == first.trajectoryID && second.yaws == first.yaws)
        for slot in 0..<5 {
            let qa = a.orientation(slot: slot)!, qb = b.orientation(slot: slot)!
            #expect(DiceStage.rotationAngle(from: qa, to: qb) < 1e-4, "슬롯 \(slot) 자세가 다르다")
            #expect(b.faceUpValue(slot: slot) == values[slot])
        }
    }

    @Test("없는 궤적 ID나 개수가 다른 힌트는 무시하고 정상 재생한다")
    func 나쁜_힌트() async throws {
        let stage = DiceStage(library: try TrajectoryLibrary.bundled())
        let bad = ThrowHint(event: 0, trajectory: 65535, direction: 1, yaws: [0, 0, 0])
        let outcome = await stage.roll(values: [4, 4, 4], slots: [0, 2, 4], direction: .center, skipAnimation: true, hint: bad)
        #expect(outcome.trajectoryID != 65535)
        #expect(stage.faceUpValue(slot: 0) == 4 && stage.faceUpValue(slot: 4) == 4)
    }
}
```

- [ ] **Step 2: 실패 확인** — 컴파일 에러.
- [ ] **Step 3: 구현**

`App/Online/ThrowHint.swift`:
```swift
import Foundation

/// 굴린 쪽이 고른 궤적과 회전 선택. 받는 쪽이 같은 던지기를 보게 한다. 연출일 뿐이라 검증하지 않는다.
struct ThrowHint: Codable, Equatable, Sendable {
    let event: Int
    let trajectory: UInt16
    let direction: UInt8
    let yaws: [Int]
}
```
`TrajectoryLibrary`에 `private let byID: [UInt16: Trajectory]`를 `init`에서 `Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })`로 채우고 `func trajectory(id: UInt16) -> Trajectory? { byID[id] }`를 더한다.

`DiceStage.roll`:
```swift
    struct RollOutcome {
        let cues: [CollisionCue]
        let trajectoryID: UInt16
        let direction: ThrowDirection
        let yaws: [Int]
    }

    func roll(values: [Int], slots: [Int], direction: ThrowDirection,
              skipAnimation: Bool, hint: ThrowHint? = nil,
              onCue: ((CollisionCue) -> Void)? = nil) async -> RollOutcome {
        precondition(values.count == slots.count, "값과 슬롯의 개수가 다르다")
        guard !slots.isEmpty else { return RollOutcome(cues: [], trajectoryID: 0, direction: direction, yaws: []) }

        var generator = SystemRandomNumberGenerator()
        // 힌트가 맞으면 그대로 쓴다. 상대 화면과 같은 던지기를 보이기 위해서다.
        let hinted = hint.flatMap { hint -> Trajectory? in
            guard let t = library.trajectory(id: hint.trajectory), t.dieCount == slots.count,
                  hint.yaws.count == slots.count, hint.yaws.allSatisfy({ (0..<4).contains($0) }) else { return nil }
            return t
        }
        let usedDirection = hinted.flatMap { _ in hint.flatMap { ThrowDirection(rawValue: $0.direction) } } ?? direction
        guard let trajectory = hinted ?? library.pick(dieCount: slots.count, direction: usedDirection, using: &generator) else {
            assertionFailure("\(slots.count)개 / \(direction) 궤적이 번들에 없다")
            return RollOutcome(cues: [], trajectoryID: 0, direction: direction, yaws: [])
        }
        let yaws: [Int] = (0..<slots.count).map { lane in
            if let hinted, hinted.id == trajectory.id { return hint!.yaws[lane] }
            return Self.leastRotationYawChoice(current: dice[slots[lane]].orientation, trajectory: trajectory,
                                               die: lane, showing: values[lane])
        }
        let offsets = (0..<slots.count).map { lane in
            FaceControl.offset(restUpFace: trajectory.restUpFace(die: lane), showing: values[lane], yawChoice: yaws[lane])
        }
        // …(기존 skipAnimation·리드인·프레임 루프는 그대로, 반환만 바꾼다)
        return RollOutcome(cues: trajectory.collisions, trajectoryID: trajectory.id, direction: usedDirection, yaws: yaws)
    }
```
기존 호출부(`GameSession.performRoll`, `replay`, `AppContainer.launch`, `DiceStageTests`)는 `_ = await stage.roll(...)` 또는 `.cues`로 맞춘다.

- [ ] **Step 4: 통과 확인** — `-only-testing:YachtDiceTests`.
- [ ] **Step 5: 커밋** — `feat(dice): 궤적 힌트로 같은 던지기를 재생한다`

---

### Task 3: 전송 프로토콜과 세션 — RemoteUpdate, 힌트, 접속·연결 상태

**Files:**
- Modify: `App/Online/TurnTransport.swift`, `App/Online/GameCenterTurnTransport.swift`, `App/Game/GameSession.swift`
- Test: `Tests/YachtDiceTests/TurnTransportTests.swift`, `Tests/YachtDiceTests/GameSessionOnlineTests.swift`

**Interfaces:**
```swift
struct RemoteUpdate: Sendable, Equatable { let log: MatchLog; let throws: [ThrowHint] }
protocol TurnTransport: Sendable {
    func publishProgress(log: MatchLog, throws: [ThrowHint]) async throws
    func endTurn(log: MatchLog, throws: [ThrowHint], nextSeat: Int) async throws
    func endMatch(log: MatchLog, throws: [ThrowHint], totals: [Int]) async throws
    var incoming: AsyncStream<RemoteUpdate> { get }
    /// 채널에 함께 있는 상대의 uid 집합. 기본은 빈 스트림.
    var presence: AsyncStream<Set<String>> { get }
    /// 채널이 구독된 상태인가. 기본은 빈 스트림.
    var connection: AsyncStream<Bool> { get }
    func refresh() async
}
// GameSession
private(set) var throwHints: [ThrowHint]
private(set) var opponentPresent = false
private(set) var isConnected = true
```
`InMemoryTurnTransport`는 `throws`를 함께 넘기고 presence는 `pair()` 시 서로의 uid("a"/"b")를 곧바로 흘린다.

- [ ] **Step 1: 실패하는 테스트**

`TurnTransportTests`의 기존 테스트를 `incoming`·`RemoteUpdate`로 바꾸고 추가:
```swift
    @Test("힌트가 로그와 함께 전달된다")
    func 힌트_전달() async throws {
        let (a, b) = InMemoryTurnTransport.pair()
        var iterator = b.incoming.makeAsyncIterator()
        let hint = ThrowHint(event: 0, trajectory: 5, direction: 1, yaws: [0, 1, 2, 3, 0])
        try await a.publishProgress(log: MatchLog(playerCount: 2), throws: [hint])
        #expect(await iterator.next()?.throws == [hint])
    }
```
`GameSessionOnlineTests`에 추가:
```swift
    @Test("상대의 굴림이 내 화면에서도 같은 자세로 멈춘다")
    func 같은_던지기() async throws {
        let (a, b) = try makePair()
        await a.send(.roll)
        await b.waitForIncoming()
        for slot in 0..<5 {
            #expect(DiceStage.rotationAngle(from: a.stageOrientation(slot: slot)!, to: b.stageOrientation(slot: slot)!) < 1e-4,
                    "슬롯 \(slot) 자세가 다르다")
        }
    }

    @Test("메모리 전송의 presence로 상대 접속이 보인다")
    func 접속_표시() async throws {
        let (a, _) = try makePair()
        let deadline = ContinuousClock.now + .seconds(2)
        while !a.opponentPresent, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(a.opponentPresent)
    }
```
`GameSession`에 테스트용 `func stageOrientation(slot: Int) -> simd_quatf? { stage.orientation(slot: slot) }`를 둔다.

- [ ] **Step 2: 실패 확인** — 컴파일 에러.
- [ ] **Step 3: 구현**

`TurnTransport.swift`: 위 인터페이스대로 바꾸고 `extension TurnTransport { var presence: AsyncStream<Set<String>> { AsyncStream { $0.finish() } }; var connection: AsyncStream<Bool> { AsyncStream { $0.finish() } }; func refresh() async {} }`. `InMemoryTurnTransport`는 `incoming: AsyncStream<RemoteUpdate>`, `sent: [RemoteUpdate]`, `presence`는 생성 시 `{"peer"}`를 한 번 yield하는 스트림(pair가 만든 뒤 각자 `presenceContinuation.yield(["peer"])`).

`GameCenterTurnTransport`: 시그니처만 맞추고 `throws`는 무시한다(매치 데이터는 로그만).

`GameSession`:
- `performRoll`: `let eventIndex = record.log.events.count`; `let outcome = await stage.roll(..., onCue:)`; `throwHints.append(ThrowHint(event: eventIndex, trajectory: outcome.trajectoryID, direction: outcome.direction.rawValue, yaws: outcome.yaws))`; 큐는 `outcome.cues`.
- `publishProgressIfOnline`: `transport.publishProgress(log: record.log, throws: throwHints)`; `publishTurnIfNeeded`: `endTurn(log:throws:nextSeat: visibleState.currentPlayer)`, `endMatch(log:throws:totals:)`.
- `startListening`: `for await update in transport.incoming` → `replay(remote: update)`; 같은 곳에서 `Task { for await present in transport.presence { opponentPresent = present.contains { $0 != myID } } }`와 `Task { for await ok in transport.connection { isConnected = ok } }`. 내 uid는 `participants` 중 `.human`이 아닌 `.remote(playerID:)`를 상대로 보므로 `present.contains(remoteID)`로 판단한다.
- `replay(remote update: RemoteUpdate)`: 이벤트 번호 `mine.count + offset`에 맞는 힌트를 `update.throws.first { $0.event == index }`로 찾아 `stage.roll(..., hint:)`에 준다. 받은 힌트는 `throwHints`에 합친다(중복 제거).
- `startNewGame`에서 `throwHints = []`.

- [ ] **Step 4: 통과 확인** — `-only-testing:YachtDiceTests`.
- [ ] **Step 5: 커밋** — `feat(online): 던지기 힌트와 접속·연결 상태를 전송 프로토콜에 더한다`

---

### Task 4: SupabaseTurnTransport — 비공개 브로드캐스트, Presence, 채널 상태

**Files:**
- Modify: `App/Online/SupabaseTurnTransport.swift`, `App/Online/MatchRow.swift`
- Test: `Tests/YachtDiceTests/SupabaseE2ETests.swift`

**Interfaces:**
- `MatchRow`에 `throws: [ThrowHint]`, `turnSeat: Int?` (키 `throws`, `turn_seat`).
- `SupabaseTurnTransport(client:matchID:localUid:realtimeEnabled:)`.

- [ ] **Step 1: 실패하는 테스트 (통합)**

```swift
    @Test("브로드캐스트로 호스트의 기록이 1.5초 안에 게스트에게 도착한다")
    func 지연() async throws { /* makePair처럼 두 세션을 만들고 */
        let start = ContinuousClock.now
        await hostSession.send(.roll); await hostSession.send(.commit(.threes))
        while !guestSession.isLocalTurn, ContinuousClock.now - start < .seconds(10) { try await Task.sleep(for: .milliseconds(25)) }
        let elapsed = ContinuousClock.now - start
        #expect(guestSession.isLocalTurn)
        #expect(elapsed < .seconds(1.5), "전달 \(elapsed)")
    }

    @Test("참가자가 아니면 매치 채널을 구독하지 못한다")
    func 권한() async throws {
        let stranger = SupabaseService(client: makeClient()); await stranger.signIn()
        let transport = SupabaseTurnTransport(client: stranger.client, matchID: room.id, localUid: stranger.uid!)
        try await Task.sleep(for: .seconds(3))
        #expect(transport.subscribeError != nil, "남의 채널 구독이 막히지 않았다")
    }

    @Test("게스트가 들어오면 호스트에 상대 접속이 보인다")
    func 접속() async throws { /* 두 세션 startListening 뒤 */
        let deadline = ContinuousClock.now + .seconds(8)
        while !hostSession.opponentPresent, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        #expect(hostSession.opponentPresent)
    }

    @Test("게스트가 재생한 주사위 자세가 호스트와 같다")
    func 재현() async throws { /* 호스트 roll 뒤 게스트 waitForIncoming, 다섯 슬롯 rotationAngle < 1e-4 */ }
```
기존 테스트의 `SupabaseTurnTransport(client:matchID:)` 호출에 `localUid:`를 더한다.

- [ ] **Step 2: 실패 확인** — 컴파일 에러.
- [ ] **Step 3: 구현**

`SupabaseTurnTransport`:
```swift
    init(client: SupabaseClient, matchID: UUID, localUid: UUID, realtimeEnabled: Bool = true) {
        // ... 스트림 셋(incoming, presence, connection)을 만든다
        if realtimeEnabled {
            listenTask = Task { [client, weak self] in
                // 비공개 채널은 세션 토큰이 있어야 한다
                if let session = try? await client.auth.session { client.realtimeV2.setAuth(session.accessToken) }
                let channel = client.channel("match-\(idText)") { $0.isPrivate = true }
                //   ↑ 토픽은 서버 정책과 같아야 하므로 "match:<id>"를 쓴다. SDK가 "realtime:" 접두를 붙이므로 channel("match:\(idText)")로 만든다.
                let updates = channel.broadcastStream(event: "UPDATE")
                let presences = channel.presenceChange()
                let statuses = channel.statusChange
                Task { for await status in statuses { self?.connectionContinuation.yield(status == .subscribed) } }
                Task { for await change in presences {
                    // 상태 전체는 change.joins/leaves로 관리한다: joins의 uid를 더하고 leaves의 uid를 뺀다
                } }
                do { try await channel.subscribeWithError() } catch { self?.subscribeError = "\(error)"; return }
                try? await channel.track(["uid": localUid.uuidString.lowercased()])
                for await message in updates {
                    // broadcast_changes 페이로드: message["payload"]["record"]
                    if let payload = message["payload"]?.objectValue, let record = payload["record"],
                       let data = try? JSONEncoder().encode(record),
                       let row = try? JSONDecoder().decode(MatchRow.self, from: data) {
                        self?.deliver(row)
                    }
                }
            }
        }
        // 폴링과 재시도는 그대로. deliver(row)는 RemoteUpdate(log: row.log, throws: row.throws)를 흘린다.
    }
```
`send`는 `throws`와 `turn_seat`를 함께 갱신한다(`TurnUpdate`에 `throws: [ThrowHint]`, `turnSeat: Int?` 추가, 키 `throws`, `turn_seat`). `endTurn(log:throws:nextSeat:)`는 `turnSeat = nextSeat`, `endMatch`는 `nil`.

`broadcastStream`의 메시지 구조는 SDK 소스 `RealtimeChannelV2.broadcastStream`이 흘리는 `JSONObject`를 실제로 출력해 확인한 뒤 키를 맞춘다(통합 테스트에서 첫 메시지를 `print`해 본다). `record`의 uuid는 소문자 문자열이고 `log`는 객체다.

- [ ] **Step 4: 통과 확인** — 단위 전체 + 통합(`SupabaseE2ETests`).
- [ ] **Step 5: 커밋** — `feat(online): 비공개 브로드캐스트와 Presence로 상대 플레이를 받는다`

---

### Task 5: 화면 — 접속 점과 연결 띠

**Files:**
- Modify: `App/Views/PlayerStrip.swift`, `App/Views/GameScreen.swift`

- [ ] **Step 1: 구현**
  - `PlayerStrip`: `.remote` 좌석의 이름 앞에 8pt 원을 두고 `session.opponentPresent`면 `theme.success`, 아니면 `theme.inkSecondary.opacity(0.5)`. 식별자 `players.presence.<i>`, 라벨 "접속 중"/"자리 비움".
  - `GameScreen`: `session.isConnected == false`가 3초 이상이면 헤더 아래에 "연결 끊김 — 재연결 중" 띠(`ScoreToast` 스타일, 식별자 `online.connection`). 3초는 `@State private var disconnectedSince: Date?`로 잰다.
- [ ] **Step 2: 확인** — 단위 테스트 전체와 `MenuUITests` 통과, 시뮬레이터 두 대 스크립트(`$SCRATCH/duo.sh`)로 접속 점이 초록인 스크린샷.
- [ ] **Step 3: 커밋** — `feat(ui): 상대 접속 점과 연결 끊김 띠`

---

### Task 6: 푸시 알림

**Files:**
- Create: `supabase/migrations/20260909_device_tokens.sql`, `supabase/functions/notify-turn/index.ts`, `supabase/functions/notify-turn/apns.ts`, `supabase/functions/notify-turn/apns_test.ts`
- Create: `App/Online/PushRegistration.swift`
- Modify: `App/YachtDiceApp.swift`, `App/AppContainer.swift`, `App/Views/OnlineMenu.swift`, `App/YachtDice.entitlements`, `project.yml`

**Interfaces:**
- 테이블 `device_tokens(uid uuid references auth.users on delete cascade, token text primary key, platform text not null default 'ios', updated_at timestamptz default now())`, RLS: `uid = auth.uid()`로 select/insert/update/delete.
- 트리거 `matches_turn_webhook` after update on matches when (`old.turn_seat is distinct from new.turn_seat` or `(old.guest_uid is null and new.guest_uid is not null)`) → `supabase_functions.http_request('https://lkernselwouldtuialjh.supabase.co/functions/v1/notify-turn', 'POST', '{"Content-Type":"application/json","Authorization":"Bearer <서비스 키 아님 — 함수는 verify_jwt=false로 배포하고 자체 비밀 헤더 X-Webhook-Secret로 검증>"}', '{}', '5000')`.
- Edge Function `notify-turn`: 웹훅 페이로드 `record`에서 알릴 uid(차례가 바뀌면 `turn_seat`가 0이면 `host_uid`, 1이면 `guest_uid`; 게스트 입장이면 `host_uid`)를 고르고 서비스 역할 키로 `device_tokens`를 읽어 APNs로 보낸다.
- 앱: `PushRegistration`이 `UNUserNotificationCenter` 권한 요청, `UIApplication.registerForRemoteNotifications`, `AppDelegate`(`UIApplicationDelegateAdaptor`)에서 토큰을 받아 `device_tokens`에 upsert, 알림 탭의 `matchID`를 `AppContainer.openOnlineMatchID(_:)`로 넘긴다.

- [ ] **Step 1: 서버**
  - 마이그레이션 SQL을 쓰고 MCP로 적용한다. 웹훅 비밀은 `select gen_random_uuid()`로 만들어 트리거 헤더와 함수 시크릿 `WEBHOOK_SECRET`에 같은 값을 둔다.
  - `apns.ts`: `.p8`(PKCS#8 ES256)로 JWT를 만든다 — `crypto.subtle.importKey("pkcs8", ...)`, `sign("ECDSA", { hash: "SHA-256" })`, JOSE 형식 r||s. `sendPush(token, payload, env)`는 `fetch("https://api.push.apple.com/3/device/" + token, { method: "POST", headers: { authorization: "bearer " + jwt, "apns-topic": bundleId, "apns-push-type": "alert" }, body })`. 410이면 토큰 삭제 신호를 돌려준다.
  - `apns_test.ts`: 테스트용으로 생성한 P-256 키로 JWT를 만들어 헤더 `kid`, `alg`, 페이로드 `iss`, `iat`가 맞고 서명이 `crypto.subtle.verify`로 검증되는지 확인한다. `deno test supabase/functions/notify-turn/`.
  - 배포: MCP `deploy_edge_function`(verify_jwt false). 시크릿 `APNS_KEY_ID`, `APNS_TEAM_ID=9P8KX3RJRR`, `APNS_PRIVATE_KEY`(p8 본문), `APNS_BUNDLE_ID=com.leejungheon.yachtdice.YachtDice`, `WEBHOOK_SECRET`은 대시보드 Edge Functions → Secrets에서 넣는다(사용자 작업).
- [ ] **Step 2: 앱**
  - `App/YachtDice.entitlements`에 `aps-environment: development`를 두고 `project.yml`에 `CODE_SIGN_ENTITLEMENTS: App/YachtDice.entitlements`를 되살리되 Game Center 키는 파일에서 뺀다(개인 팀 서명 문제와 무관하게 유료 팀이므로 push는 된다).
  - `PushRegistration`(`@MainActor final class`, `UNUserNotificationCenterDelegate`): `requestAndRegister()`, `didRegister(token: Data)` → 16진 문자열로 `device_tokens` upsert, `userNotificationCenter(_:didReceive:)`에서 `userInfo["matchID"]`를 `onOpenMatch?(UUID)`로.
  - `YachtDiceApp`: `@UIApplicationDelegateAdaptor(AppDelegate.self)`; `AppDelegate`가 토큰 콜백을 `PushRegistration.shared`로 넘긴다.
  - `AppContainer.openOnlineMatchID(_ id: UUID)`: `supabase.fetchMatch(id:)` 뒤 `openSupabaseMatch`.
  - `OnlineMenu.task`에서 로그인 뒤 `PushRegistration.shared.requestAndRegister(service:)`.
- [ ] **Step 3: 확인** — 단위 테스트 전체, `deno test` 통과, 실기기 두 대에서 한쪽이 앱을 닫아 둔 채 상대가 턴을 끝내면 알림이 오고 탭하면 그 판이 열린다(사용자 확인).
- [ ] **Step 4: 커밋** — `feat(online): 차례가 오면 APNs 푸시로 알린다`

---

### Task 7: 정리와 문서

- [ ] `OnlineMenu` 목록에서 `abandoned` 행을 "상대가 떠남"으로 표시하고 휴지통으로 지운다.
- [ ] README 온라인 절에 브로드캐스트·힌트·푸시 구조와 시크릿 목록을 적고, 스펙 상태를 갱신한다.
- [ ] 전체 테스트(단위·UI·통합) 통과 뒤 빌드 번호를 올려 TestFlight에 올린다.
- [ ] 커밋 — `docs: P6 완료 반영`
