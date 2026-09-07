# Yacht Dice P3 — Game Center 턴제 온라인 대전 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 메뉴의 "온라인 대전"에서 Game Center로 상대를 찾아 2인 야추 한 판을 턴제로 완주한다.

**Architecture:** 전송 계층을 `TurnTransport` 프로토콜로 추상화한다. 매치 데이터는 `MatchLog` JSON 그대로이며, 수신 측은 자기 로그보다 긴 부분만 `GameState.canApply`로 검증해 재생한다(굴림은 3D로). `GameCenterTurnTransport`가 `GKTurnBasedMatch`를 감싸고, `InMemoryTurnTransport` 쌍이 테스트에서 두 세션을 잇는다. 눈은 클라이언트가 굴린다(스펙 §7.4).

**Tech Stack:** GameKit (`GKLocalPlayer`, `GKTurnBasedMatch`, `GKTurnBasedMatchmakerViewController`, `GKTurnBasedEventListener`), SwiftUI `UIViewControllerRepresentable`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-07-yacht-dice-p2-p3-design.md` §5

## Global Constraints

- P2 계획의 전역 제약을 그대로 따른다 (Swift 6 strict concurrency, xcodegen, 저장소 밖 derivedData, 커밋 규칙).
- GameKit은 `App/Online/` 아래에서만 import한다. `GameSession`은 `TurnTransport`만 안다.
- 온라인 판은 `MatchStore`에 저장하지 않는다. 진행 상태의 원본은 Game Center 매치 데이터다.
- 시뮬레이터에서는 Game Center 인증이 안 될 수 있다. 자동화 테스트는 `InMemoryTurnTransport`까지다.

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `App/Online/TurnTransport.swift` | 프로토콜 + `InMemoryTurnTransport` 쌍 (Task 1) |
| `App/Game/GameSession.swift` | 원격 좌석: 내 턴 끝나면 올리고, 도착한 로그를 재생 (Task 2) |
| `App/Online/GameCenterService.swift` | 인증, 매치 목록, 이벤트 리스너 (Task 3) |
| `App/Online/GameCenterTurnTransport.swift` | `GKTurnBasedMatch` 어댑터 (Task 3) |
| `App/Online/MatchmakerView.swift` | 매치메이커 VC 래퍼 (Task 4) |
| `App/Views/OnlineMenu.swift` | 온라인 대전 화면: 로그인 상태, 새 매치, 진행 중 매치 (Task 4) |
| `App/AppContainer.swift` | 온라인 매치로 세션 시작 (Task 4) |
| `App/YachtDice.entitlements`, `project.yml` | Game Center 엔타이틀먼트 (Task 3) |
| `Tests/YachtDiceTests/TurnTransportTests.swift`, `GameSessionOnlineTests.swift` | (Task 1, 2) |

---

### Task 1: TurnTransport 프로토콜과 InMemory 쌍

**Files:**
- Create: `App/Online/TurnTransport.swift`
- Create: `Tests/YachtDiceTests/TurnTransportTests.swift`

**Interfaces:**
```swift
protocol TurnTransport: Sendable {
    /// 내 턴이 끝났다. 전체 로그를 올리고 다음 참가자에게 넘긴다.
    func endTurn(log: MatchLog) async throws
    /// 게임이 끝났다. 결과를 올린다. outcome[i]는 좌석 i의 결과.
    func endMatch(log: MatchLog, totals: [Int]) async throws
    /// 상대 턴이 끝나 새 로그가 도착하면 흐른다.
    var incomingLogs: AsyncStream<MatchLog> { get }
}

/// 같은 프로세스 안의 두 세션을 잇는다. 테스트용.
final class InMemoryTurnTransport: TurnTransport, @unchecked Sendable {
    static func pair() -> (InMemoryTurnTransport, InMemoryTurnTransport)
    private(set) var sentLogs: [MatchLog]
    private(set) var finishedTotals: [Int]?
}
```

- [ ] **Step 1: 실패하는 테스트**

```swift
import Testing
import YachtCore
@testable import YachtDice

@Suite("턴 전송 - 메모리")
struct TurnTransportTests {
    @Test("한쪽이 endTurn하면 다른 쪽 incomingLogs로 같은 로그가 온다")
    func 왕복() async throws {
        let (a, b) = InMemoryTurnTransport.pair()
        var log = MatchLog(playerCount: 2)
        log.append(.rolled([1, 2, 3, 4, 5]))
        var iterator = b.incomingLogs.makeAsyncIterator()
        try await a.endTurn(log: log)
        let received = await iterator.next()
        #expect(received == log)
        #expect(a.sentLogs == [log])
    }

    @Test("endMatch는 결과를 기록하고 상대에게도 로그를 보낸다")
    func 종료() async throws {
        let (a, b) = InMemoryTurnTransport.pair()
        var iterator = b.incomingLogs.makeAsyncIterator()
        try await a.endMatch(log: MatchLog(playerCount: 2), totals: [120, 90])
        #expect(await iterator.next() != nil)
        #expect(a.finishedTotals == [120, 90])
    }
}
```

- [ ] **Step 2: 실패 확인** — 컴파일 에러.

- [ ] **Step 3: 구현**

```swift
import Foundation
import YachtCore

protocol TurnTransport: Sendable {
    func endTurn(log: MatchLog) async throws
    func endMatch(log: MatchLog, totals: [Int]) async throws
    var incomingLogs: AsyncStream<MatchLog> { get }
}

/// 같은 프로세스 안의 두 세션을 잇는다. 테스트와 디버깅용.
final class InMemoryTurnTransport: TurnTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var peer: InMemoryTurnTransport?
    private var continuation: AsyncStream<MatchLog>.Continuation?
    let incomingLogs: AsyncStream<MatchLog>
    private(set) var sentLogs: [MatchLog] = []
    private(set) var finishedTotals: [Int]?

    private init() {
        var continuation: AsyncStream<MatchLog>.Continuation!
        incomingLogs = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation
    }

    static func pair() -> (InMemoryTurnTransport, InMemoryTurnTransport) {
        let a = InMemoryTurnTransport(), b = InMemoryTurnTransport()
        a.peer = b; b.peer = a
        return (a, b)
    }

    func endTurn(log: MatchLog) async throws {
        lock.withLock { sentLogs.append(log) }
        peer?.continuation?.yield(log)
    }

    func endMatch(log: MatchLog, totals: [Int]) async throws {
        lock.withLock { sentLogs.append(log); finishedTotals = totals }
        peer?.continuation?.yield(log)
    }
}
```

- [ ] **Step 4: 통과 확인** — `-only-testing:YachtDiceTests/TurnTransportTests`.
- [ ] **Step 5: 커밋** — `feat(online): TurnTransport 프로토콜과 메모리 전송`

---

### Task 2: GameSession — 원격 좌석

**Files:**
- Modify: `App/Game/GameSession.swift`
- Create: `Tests/YachtDiceTests/GameSessionOnlineTests.swift`

**Interfaces:**
```swift
init(driver: any MatchDriver, stage: DiceStage, record: MatchRecord, transport: (any TurnTransport)? = nil)
/// 원격 로그를 받아 재생하는 루프를 시작한다. transport가 있을 때 AppContainer가 부른다.
func startListening()
/// 테스트용: 도착한 로그를 전부 재생할 때까지 기다린다.
func waitForIncoming() async
```

동작:
- `perform(.commit)`에서 `turnAdvanced`가 적용되고 새 주인이 `.remote`면 `transport.endTurn(log:)`. `gameEnded`면 `transport.endMatch(log:totals:)`.
- `startListening()`은 `for await log in transport.incomingLogs`를 Task로 돌린다. 각 로그에 대해 `replay(remote: log)`.
- `replay(remote:)`: `log.events.count <= record.log.events.count`면 무시. 그 뒤의 이벤트를 하나씩 `visibleState.canApply`로 검증(실패하면 중단하고 `lastTransportError` 설정). `.rolled(values)`는 `stage.roll(values:slots:direction:skipAnimation:)`를 기다린 뒤 노출. `.holdToggled`는 적용 후 `stage.placeHeld`. `.committed`/`.turnAdvanced`/`.gameEnded`는 즉시. `turnAdvanced` 뒤 `stage.reset()`과 `scheduleTurnOwner(announceHandoff: false)`.
- 원격 차례에는 `isLocalTurn == false`(이미 `.remote`는 `isHuman`이 아니다).

- [ ] **Step 1: 실패하는 테스트**

```swift
import Testing
import YachtCore
import DiceTrajectory
@testable import YachtDice

@Suite("게임 세션 - 온라인")
@MainActor
struct GameSessionOnlineTests {
    private struct ConstantDriver: MatchDriver {
        let face: Int
        func requestRoll(count: Int) async throws -> [Int] { Array(repeating: face, count: count) }
        func submit(_ event: Event) async throws {}
        var incoming: AsyncStream<Event> { AsyncStream { $0.finish() } }
    }

    /// 두 기기. A는 좌석 0, B는 좌석 1.
    private func makePair() throws -> (GameSession, GameSession) {
        let (ta, tb) = InMemoryTurnTransport.pair()
        let library = try TrajectoryLibrary.bundled()
        let seatsA: [Participant] = [.human(name: "A"), .remote(playerID: "b", name: "B")]
        let seatsB: [Participant] = [.remote(playerID: "a", name: "A"), .human(name: "B")]
        let a = GameSession(driver: ConstantDriver(face: 3), stage: DiceStage(library: library),
                            record: MatchRecord(mode: .online(matchID: "m"), participants: seatsA, log: MatchLog(playerCount: 2)),
                            transport: ta)
        let b = GameSession(driver: ConstantDriver(face: 5), stage: DiceStage(library: library),
                            record: MatchRecord(mode: .online(matchID: "m"), participants: seatsB, log: MatchLog(playerCount: 2)),
                            transport: tb)
        a.reduceMotion = true; b.reduceMotion = true
        a.startListening(); b.startListening()
        return (a, b)
    }

    @Test("A의 턴이 끝나면 B에 같은 상태가 재생되고 B의 차례가 열린다")
    func 한_턴_전파() async throws {
        let (a, b) = try makePair()
        #expect(a.isLocalTurn && !b.isLocalTurn)
        await a.send(.roll)
        await a.send(.toggleHold(0))
        await a.send(.commit(.threes))
        await b.waitForIncoming()
        #expect(b.visibleState == a.visibleState)
        #expect(b.visibleState.scorecards[0].entry(.threes) == 15)
        #expect(b.isLocalTurn && !a.isLocalTurn)
    }

    @Test("두 세션이 12턴을 완주하고 로그가 같다")
    func 완주() async throws {
        let (a, b) = try makePair()
        for category in ScoreCategory.allCases {
            await a.send(.roll); await a.send(.commit(category))
            await b.waitForIncoming()
            await b.send(.roll); await b.send(.commit(category))
            await a.waitForIncoming()
        }
        #expect(a.visibleState.phase == .finished)
        #expect(a.record.log == b.record.log)
    }

    @Test("조작된 로그는 거부되고 상태가 바뀌지 않는다")
    func 조작_거부() async throws {
        let (ta, tb) = InMemoryTurnTransport.pair()
        let seats: [Participant] = [.remote(playerID: "a", name: "A"), .human(name: "B")]
        let b = GameSession(driver: ConstantDriver(face: 5), stage: DiceStage(library: try TrajectoryLibrary.bundled()),
                            record: MatchRecord(mode: .online(matchID: "m"), participants: seats, log: MatchLog(playerCount: 2)),
                            transport: tb)
        b.reduceMotion = true; b.startListening()
        var forged = MatchLog(playerCount: 2)
        forged.append(.committed(.yacht, 50))   // 굴리지도 않고 기록
        try await ta.endTurn(log: forged)
        await b.waitForIncoming()
        #expect(b.visibleState.scorecards[0].entry(.yacht) == nil)
        #expect(b.lastTransportError != nil)
    }
}
```

- [ ] **Step 2: 실패 확인** — 컴파일 에러.
- [ ] **Step 3: 구현** — 위 "동작" 항목대로 `GameSession`에 `transport`, `listenTask`, `incomingDrain: Task?`, `lastTransportError: String?`, `startListening()`, `waitForIncoming()`, `replay(remote:)`를 추가한다. `waitForIncoming()`은 "현재 처리 중인 재생 Task"가 끝날 때까지 기다린다: 재생마다 `pendingReplay = Task { ... }`로 감싸고 `await pendingReplay?.value`. 로그가 아직 안 왔을 수 있으므로 최대 2초까지 `Task.yield()`를 반복하며 `record.log.events.count`가 늘었는지 본다.
- [ ] **Step 4: 통과 확인** — 전체 단위 테스트.
- [ ] **Step 5: 커밋** — `feat(game): 원격 좌석 — 내 턴을 올리고 도착한 로그를 재생한다`

---

### Task 3: Game Center 어댑터와 엔타이틀먼트

**Files:**
- Create: `App/YachtDice.entitlements` (`com.apple.developer.game-center` = true)
- Modify: `project.yml` (`CODE_SIGN_ENTITLEMENTS: App/YachtDice.entitlements`)
- Create: `App/Online/GameCenterService.swift`
- Create: `App/Online/GameCenterTurnTransport.swift`

**Interfaces:**
```swift
@MainActor @Observable
final class GameCenterService: NSObject, GKTurnBasedEventListener {
    enum AuthState { case unknown, authenticated(name: String), unavailable(String) }
    private(set) var authState: AuthState
    private(set) var activeMatches: [GKTurnBasedMatch]
    /// 매치메이커나 알림으로 열린 매치. AppContainer가 구독해 게임을 시작한다.
    var onMatchOpened: ((GKTurnBasedMatch) -> Void)?
    func authenticate()          // GKLocalPlayer.local.authenticateHandler 설정, 리스너 등록
    func reloadMatches() async   // GKTurnBasedMatch.loadMatches()
    // GKTurnBasedEventListener
    func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool)
    func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch)
}

final class GameCenterTurnTransport: TurnTransport, @unchecked Sendable {
    init(match: GKTurnBasedMatch, service: GameCenterService)
    // endTurn: match.endTurn(withNextParticipants: [다음], turnTimeout: GKTurnTimeoutDefault, match: log.encoded())
    // endMatch: participants[i].matchOutcome = totals 기준 won/lost/tied; match.endMatch(withMatch: data)
    // incomingLogs: service가 이 match ID의 turn event를 받을 때 matchData를 디코드해 yield
}

/// 매치에서 좌석을 만든다. participants 순서가 좌석 순서다.
func makeParticipants(from match: GKTurnBasedMatch) -> [Participant]
```

- [ ] **Step 1: 엔타이틀먼트와 project.yml** — `xcodegen generate` 뒤 빌드가 되는지 확인. 서명 문제가 나면 시뮬레이터 빌드는 엔타이틀먼트를 검사하지 않으므로 `CODE_SIGN_ENTITLEMENTS`는 그대로 두고 진행한다.
- [ ] **Step 2: 구현** — 위 인터페이스대로. `makeParticipants`는 `match.participants`를 순회해 `player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID`면 `.human(name: displayName)`, 아니면 `.remote(playerID: gamePlayerID 또는 "?", name: displayName 또는 "상대")`.
- [ ] **Step 3: 단위 테스트** — `makeParticipants`는 GameKit 객체가 필요해 시뮬레이터에서 만들기 어렵다. 대신 순수 함수 `seatParticipants(localID:players:[(id: String?, name: String?)]) -> [Participant]`로 분리해 테스트한다: 로컬이 1번이면 `[.remote, .human]`, 이름 없는 상대는 "상대".
- [ ] **Step 4: 커밋** — `feat(online): Game Center 턴제 매치 어댑터`

---

### Task 4: 온라인 메뉴와 매치 시작

**Files:**
- Create: `App/Online/MatchmakerView.swift` (`GKTurnBasedMatchmakerViewController` 래퍼, `minPlayers = maxPlayers = 2`)
- Create: `App/Views/OnlineMenu.swift`
- Modify: `App/Views/MenuScreen.swift` ("온라인 대전" 활성화 → `OnlineMenu`)
- Modify: `App/AppContainer.swift` (`gameCenter: GameCenterService`, `startOnlineMatch(_ match: GKTurnBasedMatch)`)
- Modify: `App/Views/GameScreen.swift` (원격 차례 표시는 이미 있음. `lastTransportError`가 있으면 배너)

동작:
- `OnlineMenu`: 나타날 때 `authenticate()`. `.unavailable`이면 이유와 "설정에서 Game Center에 로그인하세요". `.authenticated`면 "새 매치 찾기" 버튼(매치메이커 시트)과 `activeMatches` 목록(상대 이름, 내 차례 여부). 항목을 누르면 `container.startOnlineMatch(match)`.
- `startOnlineMatch`: `participants = makeParticipants(from:)`, `log = matchData가 비었으면 MatchLog(playerCount: 2), 아니면 MatchLog.decoded`. 디코드 실패면 오류 표시. `GameSession(..., transport: GameCenterTurnTransport(...))`, `startListening()`, `resumeTurnOwner()`. `onLogChanged`는 붙이지 않는다(로컬 저장 안 함).
- `service.onMatchOpened`(알림으로 앱이 열린 경우) → 같은 경로.

- [ ] **Step 1: 구현**
- [ ] **Step 2: 빌드와 단위 테스트 전체 통과**
- [ ] **Step 3: 시뮬레이터 확인** — 메뉴 → 온라인 대전 화면이 뜨고, 인증 실패 시 안내가 보인다. 매치메이커는 실기기에서 확인한다.
- [ ] **Step 4: UI 테스트** — `MenuUITests`에 "온라인 대전 화면이 열리고 상태 문구가 있다"를 추가 (`online.status` 식별자).
- [ ] **Step 5: 커밋** — `feat(ui): 온라인 대전 메뉴와 Game Center 매치 시작`

---

### Task 5: 문서

- README 구조 표에 `App/Online` 추가, "온라인 대전을 실기기에서 확인하려면" 절(Apple Developer 포털 Game Center 켜기, App Store Connect 활성화, 샌드박스 계정 2개).
- 스펙 상태를 "C 구현 완료 (실기기 검증 대기)"로.
- 커밋: `docs: 온라인 대전 설정 안내`
