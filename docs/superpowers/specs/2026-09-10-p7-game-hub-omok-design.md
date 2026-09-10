# P7: 게임 허브, 공통 온라인 코어, Game Center 전적, 오목 설계

- 작성일: 2026-09-10
- 상태: 구현 완료 (2026-09-10). 통합 테스트로 오목 온라인 한 판을 winner_seat·records까지 확인했고, 푸시를 탭해 오목 매치를 여는 것과 리더보드 제출은 실기기 확인이 남았다
- 선행: P6 실시간 고도화 (`2026-09-09-yacht-dice-p6-realtime-design.md`)
- 후속: P8 컵퐁, P9 알까기 (각각 별도 스펙)
- 범위: 요트 다이스 전용이던 온라인 코어를 게임에 무관하게 떼어내고, 게임 허브와 Game Center 신원·전적을 붙이며, 첫 게임으로 오목을 올린다.

## 1. 목표

지금 앱은 `GameSession`·`MatchLog`·`matches.log`·`throws`까지 요트 다이스에 묶여 있어 다른 게임을 붙이려면 전송·세션·화면을 복제해야 하므로, 이 스펙은 규칙 계층을 `Game` 프로토콜로 추상화하고 전송이 JSON만 나르게 하여 게임 하나가 규칙 파일·화면·재생 훅 세 조각으로 끝나게 하며, 시작 화면을 게임 넷의 허브로 바꾸고, Game Center 로그인을 선택으로 두어 로그인한 사용자는 앱을 지웠다 깔아도 전적이 이어지고 리더보드에 승수가 오르게 하고, 규칙이 결정적이라 가장 단순한 오목을 온라인·로컬 2인으로 완주하게 한다.

## 2. 결정

| 항목 | 결정 |
|---|---|
| 전적 위치 | Game Center 리더보드(게임별 승수)와 Supabase `matches`에서 파생한 `records` 뷰. 앱 전적 화면은 서버를, 공개 순위는 리더보드를 쓴다 |
| 모드 | 새 게임은 온라인 대전과 로컬 2인만 둔다. 컴퓨터 상대는 뒤로 미룬다 |
| Game Center | 로그인은 선택이다. 되면 표시 이름이 닉네임이 되고 `gamePlayerID`로 전적이 이어지며, 안 되면 익명 계정으로 대전하고 전적은 기기 수명만큼 남는다 |
| 오목 규칙 | 15×15, 흑(호스트, 좌석 0) 선, 5개 이상 연속이면 승리, 금수 없음, 225수가 차면 무승부 |
| 앱 구조 | 시작 화면이 게임 허브(요트·오목·컵퐁·알까기 타일)이고 타일마다 그 게임의 메뉴가 열린다. 온라인 방은 호스트가 만든 게임으로 정해지고 게스트는 코드만 넣는다 |
| 코어 방식 | `Game` 프로토콜 + `MoveLog<G>` + 게임에 무관한 `OnlineMatch<G>`. 요트는 기존 `GameSession`을 유지하고 전송만 공유한다 |
| 승자 기록 | 양쪽 클라이언트가 같은 로그로 같은 결론을 내므로 `endMatch`가 `winner_seat`를 쓰고 트리거가 끝난 매치의 변경을 막는다 |
| 기존 GC 턴제 코드 | `GameCenterTurnTransport`·`MatchmakerView`·턴제 매치 부분은 지운다. Supabase가 그 자리를 대신한다 |
| 업적 | 이번 범위에서 뺀다 |

## 3. GameCore 패키지

`Packages/GameCore`에 게임에 무관한 형을 두고 `YachtCore`는 건드리지 않는다.

```swift
public enum Outcome: Equatable, Sendable { case win(seat: Int), draw }

public protocol Game {
    associatedtype State: Codable & Equatable & Sendable
    associatedtype Move: Codable & Equatable & Sendable
    static var id: String { get }             // "omok", "cuppong", "alkkagi" — 서버 game 열과 같다
    static var displayName: String { get }
    static var seatCount: Int { get }         // 2
    static func initial() -> State
    static func canApply(_ move: Move, to state: State) -> Bool
    static func apply(_ move: Move, to state: State) -> State
    static func currentSeat(_ state: State) -> Int?   // 끝났으면 nil
    static func outcome(_ state: State) -> Outcome?   // 진행 중이면 nil
}

public struct MoveLog<G: Game>: Codable, Equatable, Sendable {
    public var moves: [G.Move]
    public var state: G.State            // 처음부터 다시 적용해 만든다
    public mutating func append(_ move: G.Move) -> Bool   // canApply가 거짓이면 거부
    public func encoded() throws -> Data
    public static func decoded(from: Data) throws -> Self  // 적용 불가한 수가 있으면 던진다
}
```

로그는 수 목록이라 서버 `log`에 JSON으로 들어가고 받는 쪽은 `canApply`로 검증하며 처음부터 재적용해 상태를 만들며, 오목은 최대 225수라 충분히 싸고 컵퐁·알까기도 수십 수라 같다. 재생 힌트(`throws` 열의 `ThrowHint`)는 컵퐁·알까기가 궤적 시드로 쓰고 오목은 비운다.

### 3.1 오목 (`Sources/GameCore/Omok.swift`)

```swift
public enum Omok: Game {
    public struct State: Codable, Equatable, Sendable {
        public var cells: [UInt8]        // 225칸, 0 빈칸 1 흑 2 백
        public var nextSeat: Int?        // nil이면 끝
        public var lastMove: Move?
        public var outcome: Outcome?
    }
    public struct Move: Codable, Equatable, Sendable { public let x: Int; public let y: Int }
    public static let id = "omok", displayName = "오목", seatCount = 2, size = 15
}
```

`canApply`는 범위 안·빈칸·`nextSeat`가 있음을 보고, `apply`는 돌을 놓고 마지막 수를 지나는 가로·세로·두 대각선에서 같은 돌이 5개 이상 이어지면 `.win(seat)`, 빈칸이 없으면 `.draw`, 아니면 좌석을 넘긴다. 흑은 좌석 0이다.

## 4. 서버 (Supabase, 마이그레이션 `20260910_games.sql`)

- `matches`에 `game text not null default 'yacht'`, `host_player text`, `guest_player text`(Game Center `gamePlayerID`, 미로그인은 null), `winner_seat smallint`(무승부·미종료는 null)를 더한다. `log`·`event_count`·`turn_seat`·`throws`·`status`·브로드캐스트·푸시·정리는 그대로 게임에 무관하게 동작한다. `game`은 `('yacht','omok','cuppong','alkkagi')` 제약을 둔다.
- `join_match(p_code, p_name, p_player text default null)`이 게스트의 gamePlayerID도 받아 `guest_player`에 넣는다.
- `matches_guard_seats` 트리거를 넓혀 `game`·`host_player`·`guest_player`의 교체와 `status = 'finished'` 뒤의 어떤 변경도 막는다.
- `profiles(player text primary key, uid uuid not null, name text not null, updated_at timestamptz)`: Game Center 로그인 때 upsert하여 gamePlayerID ↔ 현재 익명 uid를 잇는다. RLS는 `uid = auth.uid()`인 행만 삽입·갱신하고, 읽기는 인증 사용자 전체에 연다(상대 이름 표시용).
- 전적은 따로 저장하지 않고 `status = 'finished'`인 `matches`에서 읽는다. 뷰 `records(player, game, wins, losses, draws)`는 참가자를 `coalesce(host_player, host_uid::text)`로 두어 Game Center 사용자는 gamePlayerID로, 미로그인 사용자는 uid로 집계되며, 상대별 전적과 최근 매치는 앱이 `matches`를 두 player 값으로 직접 조회한다. 뷰는 `security_invoker`로 두어 RLS를 지나며, 다른 사람의 전적 조회는 이번 범위에 없다.
- 리더보드 제출은 클라이언트가 `records`의 자기 승수를 읽어 `GKLeaderboard.submitScore`로 올린다. 리더보드 ID는 `wins.yacht`, `wins.omok`, `wins.cuppong`, `wins.alkkagi`이며 App Store Connect API(`gameCenterDetails`, `gameCenterLeaderboards`)로 만들어 보고 안 되면 사용자 작업으로 넘긴다.
- 요트도 `endMatch`에서 `winner_seat`를 쓰도록 하여 전적에 든다(총점 동점은 무승부).

## 5. 앱

### 5.1 파일

| 파일 | 책임 |
|---|---|
| `Packages/GameCore` | `Game`, `Outcome`, `MoveLog`, `Omok` |
| `App/Online/TurnTransport.swift` | `TurnPayload { log: Data, eventCount, hints, turnSeat, winnerSeat }`·`RemoteUpdate { log: Data, hints }`. 게임을 모른다 |
| `App/Online/SupabaseTurnTransport.swift`, `InMemoryTurnTransport` | JSON을 그대로 옮긴다. `winner_seat`·`game`을 함께 쓴다 |
| `App/Online/MatchRow.swift` | `game`, `hostPlayer`, `guestPlayer`, `winnerSeat`, `log: Data` |
| `App/Game/GameSession.swift` | 요트 전용 그대로. `MatchLog` ↔ `Data` 어댑터만 더한다 |
| `App/Game/OnlineMatch.swift` | 새 게임 공통 세션 `OnlineMatch<G: Game>` |
| `App/Game/MatchRecord.swift` | `game: String`, `log: Data`. v2 파일은 `game = "yacht"`로 읽는다(v3) |
| `App/AppContainer.swift` | `status = .hub / .menu(game) / .playing(...)`, 게임별 열기, 이어하기 |
| `App/Views/HubScreen.swift` | 타일 넷, 진행 중 매치 카드, 전적 카드 |
| `App/Views/GameMenu.swift` | 게임별 메뉴(온라인·로컬 2인, 요트는 컴퓨터·이어하기 포함). 지금 `MenuScreen`을 요트 메뉴로 옮긴다 |
| `App/Views/OnlineMenu.swift` | `game`을 받아 방을 만든다. 게스트는 코드만 넣고 행의 `game`으로 화면을 고른다 |
| `App/Views/RecordsScreen.swift` | 게임별 승·패·무, 최근 매치 열 개, 리더보드 버튼(`GKGameCenterViewController`) |
| `App/Games/Omok/OmokScreen.swift`, `OmokBoardView.swift` | 판·돌·미리보기·놓기 버튼·승자 배너 |
| `App/Online/GameCenterService.swift` | 신원 전용으로 다시 쓴다: 인증, `gamePlayerID`·`displayName`, `profiles` upsert, 리더보드 제출 |
| 삭제 | `GameCenterTurnTransport.swift`, `MatchmakerView.swift`, 턴제 매치 관련 코드·테스트 |

### 5.2 OnlineMatch<G>

`@MainActor @Observable final class OnlineMatch<G: Game>`는 `record: MatchRecord`, `log: MoveLog<G>`, `participants`, `localSeat`, `isLocalTurn`, `opponentPresent`, `isConnected`, `lastTransportError`, `outcome`를 갖고, `play(_ move: G.Move, hint: ThrowHint?)`가 `canApply` 검증 → 로그 추가 → 저장 → `publishProgress`(턴이 안 끝났으면)·`endTurn`(다음 좌석)·`endMatch`(winnerSeat)를 부르며, 원격 로그는 내 것보다 긴 수만 `canApply`로 검증해 하나씩 `onRemoteMove: (G.Move, ThrowHint?) async -> Void` 훅으로 화면에 넘겨 재생을 기다린 뒤 다음 수로 간다. `startListening`·`resync`·재시도·`lastOpponentMove`(팝업용)·Presence·연결은 `GameSession`의 것을 옮기고, 로컬 2인은 전송이 nil인 같은 객체로 수마다 좌석이 바뀌며 핸드오프 화면은 두지 않는다(같은 화면에서 번갈아 둔다).

### 5.3 흐름

1. 앱을 열면 허브가 보이고 `GameCenterService`가 인증을 시도하며, 성공하면 닉네임 기본값이 표시 이름이 되고 `profiles`에 upsert한다.
2. 오목 타일 → 오목 메뉴 → 온라인이면 `OnlineMenu(game: "omok")`가 방을 만들고(`host_player` 포함), 게스트가 들어오면 `AppContainer.openMatch(row)`가 `row.game`으로 `OnlineMatch<Omok>`와 `OmokScreen`을 연다. 로컬 2인이면 전송 없이 같은 화면이다.
3. 수를 두면 로그가 올라가고 상대는 브로드캐스트로 받아 `onRemoteMove`로 돌 애니메이션과 소리를 재생한다. 끝나면 `endMatch(winnerSeat)`가 `status = finished`·`winner_seat`를 쓴다.
4. 끝난 뒤 `records`를 읽어 승수를 리더보드에 올리고, 허브의 전적 카드가 갱신된다.
5. 허브의 진행 중 매치 카드는 게임 이름을 함께 보여 열면 해당 게임 화면으로 간다. 푸시 알림 탭도 `row.game`으로 같은 길을 탄다.

### 5.4 오목 화면

SwiftUI `Canvas`로 나무색 판·격자·화점·돌·마지막 수 표식을 그리고, 탭한 교차점에 반투명 미리보기 돌을 보였다가 "놓기" 버튼으로 확정하며, 상대 수는 돌이 살짝 커졌다 놓이는 0.25초 애니메이션과 `SoundSynth.stamp`로 재생한다. 상단은 `PlayerStrip`(접속 점·현재 차례)과 연결 띠·턴 배너를 재사용하고 끝나면 승자 배너와 "허브로" 버튼을 보인다. 식별자는 `omok.board`, `omok.place`, `omok.result`.

## 6. 테스트

| 대상 | 테스트 |
|---|---|
| `MoveLog`·`Omok` | 단위: 5목 판정(가로·세로·두 대각선, 6목도 승리), 빈칸·차례·범위 검증, 무승부, 로그 인코딩 왕복, 적용 불가한 로그 거부 |
| `OnlineMatch` | 단위: 메모리 전송 쌍으로 오목 한 판 완주, 조작된 수 거부, 힌트 전달, 로컬 2인 |
| 요트 회귀 | 기존 단위·UI·통합 테스트가 그대로 통과 |
| 서버 | 통합: `game = 'omok'` 방 만들기·입장·수 왕복, `winner_seat`와 `records` 뷰, 끝난 매치 변경 거부 |
| 허브·UI | UI: 허브에서 오목 로컬 2인을 열어 다섯 수 두고 승리 배너까지, 요트 타일이 기존 메뉴로 간다 |
| Game Center | 단위: `GameCenterService` 인증 상태 머신을 가짜 로컬 플레이어로. 리더보드 제출은 실기기에서 사용자가 확인 |

## 7. 치르는 값

- 승자 판정은 클라이언트가 쓰므로 조작된 클라이언트가 거짓 승리를 적을 수 있다. 상대 화면의 로그가 남아 반박 근거는 되지만 서버가 막지는 않는다.
- Game Center 미로그인 전적은 기기 수명만큼이고, 여러 기기를 쓰는 사용자의 리더보드는 최신 제출 승수로 덮인다(승수는 서버에서 세므로 값은 같다).
- 리더보드 넷은 App Store Connect에 있어야 하며 API로 못 만들면 사용자 작업이 된다.
- 기존 Game Center 턴제 코드를 지우므로 Supabase 없이 도는 온라인 경로는 없다.
