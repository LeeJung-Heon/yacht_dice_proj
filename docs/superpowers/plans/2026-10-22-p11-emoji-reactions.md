# P11 — 게임 중 이모지 반응 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 네 게임의 온라인 대전에서 게임 도중과 결과 카드가 떠 있는 동안 아이폰 기본 이모지를 상대에게 보내고, 받으면 판 위로 크게 떠올랐다 흩어진 뒤 보낸 사람 명패에 배지로 남는다.

**Architecture:** `TurnTransport`에 `Reaction{emoji, eventCount}` 송수신을 더해 Supabase는 비공개 채널의 클라이언트 브로드캐스트 `emoji`로 나르고, 판정·빈도·떠오름·배지 상태는 `@MainActor @Observable ReactionBoard` 하나가 맡아 `GameSession`과 `OnlineMatch<G>`가 온라인일 때만 들고 있으며, 화면은 공용 `ReactionButton`(이모지 키보드)·`ReactionOverlay`(떠오름)·배지 수정자를 네 게임에 붙인다.

**Tech Stack:** SwiftUI, UIKit(`UITextField`의 `textInputMode`), Supabase Realtime Broadcast, Swift Testing, XCTest UI.

**Spec:** `docs/superpowers/specs/2026-10-22-p11-emoji-reactions-design.md`

## Global Constraints

- iOS 18.0 이상, Swift 6, `SWIFT_STRICT_CONCURRENCY: complete`. 새 파일을 더한 뒤에는 `xcodegen generate`를 돌린다.
- Supabase SDK는 `App/Online` 아래에서만 import한다. 세션과 화면은 `TurnTransport`와 `ReactionBoard`만 안다. 서버(SQL·정책)는 바꾸지 않는다.
- 빌드·테스트의 `-derivedDataPath`는 `$SCRATCH/dd`(`SCRATCH=/private/tmp/claude-501/-Users-leejungheon-Library-Mobile-Documents-com-apple-CloudDocs-yacht-dice-proj/8bf6896e-6449-4a26-ae36-cc8621d77f4c/scratchpad`)이고, 실패 뒤 진단 수집으로 10분을 기다리지 않도록 `-collect-test-diagnostics never`를 붙인다.
- 단위 테스트 명령(시뮬레이터 id `64A5E02A-510C-4E97-AFF0-5BB8AFA368EB`):
  ```sh
  xcodebuild -project YachtDice.xcodeproj -scheme YachtDice -destination 'id=64A5E02A-510C-4E97-AFF0-5BB8AFA368EB' \
    -derivedDataPath "$SCRATCH/dd" -collect-test-diagnostics never -only-testing:YachtDiceTests/<Suite> test 2>&1 | grep -E "error:|✘|Test run with"
  ```
  기준선은 단위 229개, UI 16개 통과다.
- 값: 채널 이벤트 `emoji`, 페이로드 `{"emoji": String, "event_count": Int}`, 보내기 간격 1초, 떠오름 2초·64pt, 판정은 `Character` 하나이고 UTF-8 64바이트 이하.
- 문구와 식별자: 단추 라벨 "이모지 보내기", 식별자 `reaction.button`·`reaction.burst`·`reaction.badge.<좌석>`, VoiceOver 알림 "<보낸 사람 이름>: <이모지>".
- 커밋은 Conventional Commits, 한국어 제목(`~한다`), 본문은 왜만, 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. 브랜치 `feat/p11-emoji-reactions`, 푸시하지 않는다.

## Review Focus

- 상대가 이모지가 아닌 글자, 여러 글자, 아주 긴 조합, 빈 문자열을 보내도 내 화면에는 아무것도 뜨지 않아야 한다 → Task 1·2의 판정·수신 테스트.
- 조작된 클라이언트가 이모지를 연달아 퍼부어도 떠오르는 이모지가 쌓여 판을 덮거나 앱이 느려지지 않아야 한다 → Task 2의 1초 제한 테스트와 Task 1의 버퍼 상한.
- 떠오르는 이모지 위를 눌러도 판 입력(오목 자리, 알까기 당김, 컵퐁 끌기, 요트 굴림)이 그대로 들어가야 한다 → Task 4·5의 `allowsHitTesting(false)`와 UI 테스트.
- 이모지 키보드를 연 채 화면을 떠나거나 차례가 바뀌어도 키보드가 남거나 입력이 막히지 않아야 한다 → Task 4의 사라질 때 닫기.
- 상대가 내 수를 재생하는 중에 받은 이모지 배지가 재생이 끝나자마자 사라지지 않아야 한다 → Task 3의 재생 중 수신 테스트.

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `App/Online/TurnTransport.swift` | `Reaction`, `sendReaction`·`reactions`와 기본 구현, 메모리 전송 (Task 1) |
| `App/Online/RealtimeMessages.swift` | `ReactionMessage` 채널 페이로드 (Task 1) |
| `App/Online/SupabaseTurnTransport.swift` | `emoji` 송수신 (Task 1) |
| `App/Game/ReactionBoard.swift` (새 파일) | 판정, 보내기·받기, 1초 제한, 떠오름 목록, 배지와 수명 (Task 2) |
| `App/Game/OnlineMatch.swift`, `App/Game/GameSession.swift` | `reactions`, `sendReaction`, 시작·접기, `noteTurn` (Task 3) |
| `App/Views/Reactions/ReactionButton.swift`, `ReactionOverlay.swift` (새 파일) | 단추·이모지 키보드, 떠오름 겹층, 배지 수정자 (Task 4) |
| `App/Games/Omok/OmokScreen.swift` | 오목 연결 (Task 4) |
| `App/Views/GameScreen.swift`, `PlayerStrip.swift`, `App/Games/CupPong/CupPongScreen.swift`, `App/Games/Alkkagi/AlkkagiScreen.swift` | 나머지 세 게임 연결 (Task 5) |
| `Tests/YachtDiceTests/SupabaseE2ETests.swift`, `README.md`, 스펙 | 통합 검증과 문서 (Task 6) |

---

### Task 1: 반응 전송 계층

**Files:**
- Modify: `App/Online/TurnTransport.swift`, `App/Online/RealtimeMessages.swift`, `App/Online/SupabaseTurnTransport.swift`
- Test: `Tests/YachtDiceTests/TurnTransportTests.swift`, `Tests/YachtDiceTests/RealtimeMessagesTests.swift`

**Interfaces:**
- Produces:
  - `struct Reaction: Sendable, Equatable { let emoji: String; let eventCount: Int }`
  - `TurnTransport`에 `func sendReaction(_ reaction: Reaction) async`, `var reactions: AsyncStream<Reaction> { get }` (기본: 아무것도 안 함, 곧 끝나는 스트림)
  - `InMemoryTurnTransport.sentReactions: [Reaction]`
  - `struct ReactionMessage: Codable, Equatable { let emoji: String; let eventCount: Int }`, 키 `emoji`·`event_count`, `init(_ reaction: Reaction)`, `var reaction: Reaction`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
// TurnTransportTests
@Test("메모리 전송의 반응은 짝에게만 가고 보낸 쪽은 기억한다")   // a.sendReaction(Reaction(emoji: "🔥", eventCount: 3)) → b.reactions 첫 값 == 그것, a.sentReactions == [그것], b.sentReactions.isEmpty
@Test("기본 구현의 reactions는 빈 스트림이다")   // 기존 Silent 대역으로 next() == nil
// RealtimeMessagesTests
@Test("ReactionMessage는 SDK의 JSONObject를 거쳐도 같은 Reaction이 된다")   // 👨‍👩‍👧‍👦, eventCount 7 왕복; 인코딩한 JSON에 "event_count":7
@Test("깨진 반응 페이로드는 디코드에 실패한다")   // ["emoji": 3] → throw
```

- [ ] **Step 2: 실패를 확인한다** — Run: 단위 명령, `-only-testing:YachtDiceTests/TurnTransportTests -only-testing:YachtDiceTests/RealtimeMessagesTests`. Expected: 타입이 없어 컴파일 실패

- [ ] **Step 3: 구현한다**

`SupabaseTurnTransport`는 `live`와 같은 길로 `subscribedChannel()`일 때만 `channel.broadcast(event: "emoji", message: ReactionMessage(reaction))`를 보내고(실패는 `lastBroadcastError`), 기존 task group에 `broadcastStream(event: "emoji")` 루프를 더해 `payload`를 `ReactionMessage`로 읽어 흘린다. 받는 스트림은 `.bufferingNewest(8)`이다. `realtimeEnabled == false`면 스트림을 끝낸다.

- [ ] **Step 4: 통과를 확인한다** — Run: Step 2와 같다. Expected: PASS

- [ ] **Step 5: 커밋한다**

```bash
git add App/Online/TurnTransport.swift App/Online/RealtimeMessages.swift App/Online/SupabaseTurnTransport.swift Tests/YachtDiceTests/TurnTransportTests.swift Tests/YachtDiceTests/RealtimeMessagesTests.swift
git commit -m "feat(online): 이모지 반응을 채널로 주고받는 전송을 더한다"
```

---

### Task 2: `ReactionBoard`

**Files:**
- Create: `App/Game/ReactionBoard.swift`, `Tests/YachtDiceTests/ReactionBoardTests.swift`

**Interfaces:**
- Consumes: `Reaction`, `TurnTransport.sendReaction`·`reactions` (Task 1)
- Produces (`@MainActor @Observable final class ReactionBoard`):
  - `init(localSeat: Int, remoteSeat: Int, remoteName: String, transport: any TurnTransport, cooldown: Duration = .seconds(1), burstDuration: Duration = .seconds(2))`
  - `struct Burst: Identifiable, Equatable { let id: UUID; let emoji: String; let seat: Int }`, `private(set) var bursts: [Burst]`
  - `struct Badge: Equatable { let emoji: String; let eventCount: Int }`, `private(set) var badges: [Int: Badge]`
  - `private(set) var canSend: Bool` (마지막으로 보낸 뒤 `cooldown`이 지나면 참으로 돌아온다)
  - `let localSeat: Int`, `let remoteSeat: Int`, `let remoteName: String`
  - `func send(_ text: String, eventCount: Int) -> Bool`, `func start()`, `func stop()`, `func noteTurn(_ seat: Int?, eventCount: Int)`
  - `static func isSingleEmoji(_ text: String) -> Bool`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

메모리 전송 쌍 `(ta, tb)`로 `a = ReactionBoard(localSeat: 0, remoteSeat: 1, remoteName: "B", transport: ta, cooldown: .milliseconds(200), burstDuration: .milliseconds(300))`, `b`는 좌석을 뒤집어 만들고 `start()`한다.

```swift
@Test("이모지 하나만 참이다", arguments: ["🔥", "👍🏽", "🇰🇷", "👨‍👩‍👧‍👦", "1️⃣", "❤️", "😀"])
@Test("이모지가 아니거나 둘 이상이거나 너무 길면 거짓이다", arguments: ["a", "1", "#", "🔥🔥", "", "🔥a", " ", "가", String(repeating: "👨‍👩‍👧‍👦", count: 3)])
// 마지막 인수는 UTF-8 64바이트 초과 판정도 겸한다; 별도로 String(repeating: "\u{200D}", count: 70)을 붙인 🔥도 거짓
@Test("보내면 상대에게 가고 내 좌석으로 떠오르며 내 명패에 배지가 붙는다")
// a.send("🔥", eventCount: 2) == true; ta.sentReactions == [Reaction("🔥", 2)]; a.bursts.map(\.seat) == [0]; a.badges[0] == Badge("🔥", 2)
@Test("간격 안의 둘째는 보내지 않고 간격이 지나면 다시 보낸다")
// send("🔥") true → canSend false → send("😭") false, sentReactions 하나 → 250ms 뒤 canSend true, send("😭") true
@Test("이모지가 아니면 보내지 않는다")   // send("hi") false, sentReactions 비어 있음
@Test("받으면 상대 좌석으로 떠오르고 배지가 붙는다")   // a.send("🔥", 1) → b.bursts.map(\.seat) == [0]... (b의 상대 좌석은 0), b.badges[0]?.emoji == "🔥"
@Test("받은 것이 이모지가 아니거나 같은 사람의 간격 안 둘째면 버린다")
// ta.sendReaction(Reaction("hello", 0)) → b.bursts 비어 있음; 두 이모지를 연달아 ta로 직접 → b.bursts.count == 1
@Test("떠오른 반응은 정한 시간이 지나면 목록에서 빠지고 배지는 남는다")   // 400ms 뒤 a.bursts.isEmpty, a.badges[0] != nil
@Test("배지는 보낸 수 뒤에 차례가 바뀌면 사라지고 같은 차례에서는 남는다")
// a.noteTurn(0, eventCount: 0); a.send("🔥", eventCount: 0); a.noteTurn(0, eventCount: 1) → 남음; a.noteTurn(1, eventCount: 2) → badges[0] == nil
@Test("차례가 바뀐 그 수에서 보낸 배지는 다음 차례가 바뀔 때까지 남는다")
// noteTurn(1, 3) 뒤 send("😭", 3) → noteTurn(1, 3) 다시 → 남음; noteTurn(0, 4) → 사라짐
@Test("같은 사람의 다음 이모지가 배지를 바꾸고 판이 끝난 뒤에도 주고받는다")
// noteTurn(nil, 9); 260ms 간격으로 send("🔥", 9), send("👏", 9) → badges[0]?.emoji == "👏"; noteTurn(nil, 9) 다시 → 남음
@Test("stop() 뒤에는 받지 않는다")
```

- [ ] **Step 2: 실패를 확인한다** — Run: 단위 명령, `-only-testing:YachtDiceTests/ReactionBoardTests`. Expected: `ReactionBoard`가 없어 컴파일 실패

- [ ] **Step 3: 구현한다**

판정은 `text.count == 1 && text.utf8.count <= 64`이고 그 `Character`의 스칼라 중 하나가 `isEmojiPresentation`이거나, 첫 스칼라가 `isEmoji`이면서 U+FE0F(이모지 표시 선택자) 또는 U+20E3(키캡)을 품을 때 참이다. 떠오름은 넣은 뒤 `burstDuration`이 지나면 그 `id`만 빼는 Task로 지우고, `canSend`도 같은 방식으로 `cooldown` 뒤 되돌린다. 받는 쪽의 간격은 좌석별 마지막 받은 시각으로 잰다. `noteTurn`은 이전 차례(처음엔 아직 없음)와 다르면 그 `eventCount`를 마지막으로 차례가 바뀐 수로 두고 `badge.eventCount`가 그보다 작은 배지를 지운다.

- [ ] **Step 4: 통과를 확인한다** — Run: Step 2와 같다. Expected: PASS

- [ ] **Step 5: 커밋한다**

```bash
git add App/Game/ReactionBoard.swift Tests/YachtDiceTests/ReactionBoardTests.swift
git commit -m "feat(online): 이모지 반응의 판정·빈도·떠오름·배지를 맡는 ReactionBoard를 더한다"
```

---

### Task 3: 세션에 잇기

**Files:**
- Modify: `App/Game/OnlineMatch.swift`, `App/Game/GameSession.swift`
- Test: `Tests/YachtDiceTests/OnlineMatchLiveTests.swift`(같은 파일에 `@Suite("OnlineMatch - 이모지 반응") struct OnlineMatchReactionTests`), `Tests/YachtDiceTests/GameSessionOnlineTests.swift`

**Interfaces:**
- Consumes: `ReactionBoard` (Task 2)
- Produces: 두 세션 모두 `let reactions: ReactionBoard?`(전송이 있고 원격 좌석이 있을 때만), `@discardableResult func sendReaction(_ text: String) -> Bool`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```swift
@Test("온라인은 반응을 내놓고 로컬은 없다")   // 오목 쌍의 a.reactions?.localSeat == 0 && remoteSeat == 1; passAndPlay는 nil, sendReaction("🔥") == false
@Test("상대 수를 재생해 차례가 바뀌면 그 전의 배지가 양쪽에서 사라진다")
// a.sendReaction("🔥") → b.reactions?.badges[0] 생김 → a.play((7,7)) → b.waitForIncoming() → a·b 모두 badges[0] == nil
@Test("내 수를 상대가 재생하는 중에 보낸 이모지는 재생이 끝나도 양쪽에 남는다")
// b.onRemoteMove를 continuation으로 붙잡는다 → a.play((5,5)) → a.sendReaction("😭") → b 배지 생김 → 재생을 풀고 b.waitForIncoming()
// → a·b 모두 badges[0]?.emoji == "😭" → b.play((6,6)) → a.waitForIncoming() → 양쪽 badges[0] == nil
@Test("판이 끝난 뒤에도 반응을 주고받는다")   // 오목 다섯 수로 끝낸 뒤 b.sendReaction("👏") == true, a.reactions?.badges[1]?.emoji == "👏"
@Test("stop()하면 반응을 받지 않는다")
// GameSessionOnlineTests
@Test("요트 온라인 세션은 반응을 주고받고 상대 기록으로 차례가 바뀌면 배지가 사라진다")
// a.sendReaction("🔥") → b.reactions?.badges[0] → a.roll, a.commit(.threes) → b.waitForIncoming() → b.reactions?.badges[0] == nil
@Test("요트 로컬 세션은 반응이 없다")
```

- [ ] **Step 2: 실패를 확인한다** — Run: 단위 명령, `-only-testing:YachtDiceTests/OnlineMatchReactionTests -only-testing:YachtDiceTests/GameSessionOnlineTests`. Expected: `reactions`가 없어 컴파일 실패

- [ ] **Step 3: 구현한다**

`OnlineMatch`는 `init`에서 전송이 있으면 `participants.firstIndex(where: \.isHuman)`과 원격 좌석으로 보드를 만들고, `startListening()`에서 `start()`, `stop()`에서 `stop()`하며, `sendReaction`은 `log.moves.count`를 실어 보낸다. 초기 상태와 `play`·`replay`에서 `log.append` 할 때마다 `noteTurn(G.currentSeat(state), eventCount: log.moves.count)`를 부른다. `GameSession`도 같고 수는 `record.log.events.count`, 차례는 끝났으면 nil 아니면 `visibleState.currentPlayer`이며, `visibleState`를 바꾸는 모든 곳(굴림 착지, `commitEvents`, `replay`의 이벤트마다, `startNewGame`) 뒤에 부른다.

- [ ] **Step 4: 통과와 기존 세션 테스트를 확인한다** — Run: 단위 명령, `-only-testing:YachtDiceTests/OnlineMatchReactionTests -only-testing:YachtDiceTests/OnlineMatchLiveTests -only-testing:YachtDiceTests/OnlineMatchTests -only-testing:YachtDiceTests/GameSessionOnlineTests -only-testing:YachtDiceTests/GameSessionTests`. Expected: PASS

- [ ] **Step 5: 커밋한다**

```bash
git add App/Game/OnlineMatch.swift App/Game/GameSession.swift Tests/YachtDiceTests/OnlineMatchLiveTests.swift Tests/YachtDiceTests/GameSessionOnlineTests.swift
git commit -m "feat(online): 네 게임의 온라인 세션이 이모지 반응을 주고받고 차례에 맞춰 배지를 거둔다"
```

---

### Task 4: 반응 화면 조각과 오목

**Files:**
- Create: `App/Views/Reactions/ReactionButton.swift`, `App/Views/Reactions/ReactionOverlay.swift`
- Modify: `App/Games/Omok/OmokScreen.swift`, `Tests/YachtDiceUITests/OmokUITests.swift`

**Interfaces:**
- Consumes: `ReactionBoard` (Task 2), 세션의 `reactions`·`sendReaction` (Task 3)
- Produces:
  - `struct ReactionButton: View { init(canSend: Bool, send: @escaping (String) -> Void) }` — 😊 단추, 라벨 "이모지 보내기", 식별자 `reaction.button`, `canSend`가 거짓이면 흐리게 잠긴다
  - `struct ReactionOverlay: View { init(board: ReactionBoard) }` — `allowsHitTesting(false)`, 떠오르는 이모지 식별자 `reaction.burst`
  - `extension View { func reactionBadge(_ emoji: String?, seat: Int) -> some View }` — 오른쪽 위 모서리 원형 배지, 식별자 `reaction.badge.<seat>`

- [ ] **Step 1: 실패하는 UI 테스트를 쓴다**

`OmokUITests.test_로컬_2인_다섯_수로_흑이_이긴다`에서 판이 뜬 직후 `XCTAssertFalse(app.buttons["reaction.button"].exists, "로컬 대전에 이모지 단추가 보인다")`, 판정 문구를 확인한 뒤 결과 카드에서도 같은 단언을 더한다. 이 단언은 지금 코드에서도 통과하므로, 실패를 보려면 Step 3에서 단추를 조건 없이 먼저 붙여 실패를 확인한 뒤 조건을 건다.

- [ ] **Step 2: 화면 조각을 만든다**

`ReactionButton`은 단추 뒤에 1×1 투명 `UIViewRepresentable`을 두며, 그 안의 `UITextField` 하위 클래스는 `textInputMode`로 `UITextInputMode.activeInputModes`에서 `primaryLanguage == "emoji"`인 것을(없으면 기본) 돌려주고 `textInputContextIdentifier`는 `""`다. 단추를 누르면 첫 응답자가 되고 다시 누르면 내려가며, `shouldChangeCharactersIn`에서 받은 문자열을 `send`로 넘기고 `false`를 돌려준 뒤 내려간다. 응답자인 동안 창에 `cancelsTouchesInView = true`인 탭 인식기를 달아 키보드 밖을 누르면 보내지 않고 내려가며, 뷰가 사라지면 내려가고 인식기를 뗀다. `ReactionOverlay`는 `bursts`마다 64pt 이모지 하나와 작은 사본 둘을 2초 동안 위로 흩어지며 흐려지게 그리고, `accessibilityReduceMotion`이면 제자리에서 흐려지기만 한다. 새 반응의 좌석이 `remoteSeat`이면 `Haptics.shared.play(.selection)`를 내고 VoiceOver가 켜져 있으면 `"\(board.remoteName): \(emoji)"`를 알린다.

- [ ] **Step 3: 오목에 잇는다**

머리글의 수 글자 오른쪽에 `if let board = match.reactions { ReactionButton(canSend: board.canSend) { match.sendReaction($0) } }`, 판 위에 `.overlay { if let board = match.reactions { ReactionOverlay(board: board) } }`, 명패에 `.reactionBadge(match.reactions?.badges[seat]?.emoji, seat: seat)`를 붙인다. 먼저 단추를 `if let` 없이 붙여 Step 1의 단언이 실패하는 것을 본 뒤 조건을 건다.

- [ ] **Step 4: UI 테스트와 단위 테스트를 확인한다**

Run: `-only-testing:YachtDiceUITests/OmokUITests`, 이어서 단위 명령 `-only-testing:YachtDiceTests`. Expected: 모두 통과

- [ ] **Step 5: 커밋한다**

```bash
git add App/Views/Reactions App/Games/Omok/OmokScreen.swift Tests/YachtDiceUITests/OmokUITests.swift
git commit -m "feat(omok): 이모지 키보드로 반응을 보내고 판 위에 띄우는 화면 조각을 더한다"
```

---

### Task 5: 요트·컵퐁·알까기에 잇기

**Files:**
- Modify: `App/Views/GameScreen.swift`, `App/Views/PlayerStrip.swift`, `App/Games/CupPong/CupPongScreen.swift`, `App/Games/Alkkagi/AlkkagiScreen.swift`

**Interfaces:**
- Consumes: Task 4의 `ReactionButton`·`ReactionOverlay`·`reactionBadge`, Task 3의 `reactions`·`sendReaction`

- [ ] **Step 1: 잇는다**

각 화면의 머리글 오른쪽 끝에 단추, 판(요트는 `DiceStageView`, 컵퐁은 `CupPongTableView`, 알까기는 판 `GeometryReader`) 위에 겹층, 명패(요트는 `PlayerStrip`의 좌석 단추)에 배지를 오목과 같은 방식으로 붙인다. 머리글의 기존 글자는 `lineLimit(1)`과 `minimumScaleFactor`로 줄여 자리를 내고 없애지 않는다.

- [ ] **Step 2: UI 테스트 전체와 단위 테스트를 확인한다**

Run: `-only-testing:YachtDiceUITests`, 이어서 단위 명령 `-only-testing:YachtDiceTests`. Expected: UI 16개 이상과 단위 전체 통과(로컬 대전 UI 테스트가 겹층 때문에 입력을 놓치지 않는다)

- [ ] **Step 3: 커밋한다**

```bash
git add App/Views/GameScreen.swift App/Views/PlayerStrip.swift App/Games/CupPong/CupPongScreen.swift App/Games/Alkkagi/AlkkagiScreen.swift
git commit -m "feat(games): 요트·컵퐁·알까기에도 이모지 반응을 붙인다"
```

---

### Task 6: 통합 검증과 문서

**Files:**
- Modify: `Tests/YachtDiceTests/SupabaseE2ETests.swift`, `README.md`, `docs/superpowers/specs/2026-10-22-p11-emoji-reactions-design.md`

- [ ] **Step 1: 통합 테스트를 쓴다**

접속 테스트(`접속()`)의 끝에 호스트 `ta.sendReaction(Reaction(emoji: "🔥", eventCount: 0))`가 5초 안에 게스트 `tb.reactions`에 닿는지 확인하는 단언을 더한다(새 계정 쌍을 만들지 않는다).

- [ ] **Step 2: 그 통합 테스트만 돌린다**

Run: `TEST_RUNNER_YACHT_SUPABASE_E2E=1` 단위 명령에 `"-only-testing:YachtDiceTests/SupabaseE2ETests/접속()"`. Expected: PASS(HTTP 429면 한 시간 뒤)

- [ ] **Step 3: 문서를 고친다**

README "온라인 대전" 절에 반응 한 문단(😊 단추와 시스템 이모지 키보드, `emoji` 브로드캐스트, 판정·1초 제한, 떠오름과 배지, 수명 규칙, 저장하지 않음, 구버전 호환)을 더하고 "게임 허브" 첫 문장의 기능 목록에 반응을 넣으며, 스펙 상태를 구현 완료로 바꾼다. `writing-korean-prose` 문체를 따른다.

- [ ] **Step 4: 커밋한다**

```bash
git add Tests/YachtDiceTests/SupabaseE2ETests.swift README.md docs/superpowers/specs/2026-10-22-p11-emoji-reactions-design.md
git commit -m "docs: 이모지 반응을 README에 적고 통합 검증을 더한다"
```
