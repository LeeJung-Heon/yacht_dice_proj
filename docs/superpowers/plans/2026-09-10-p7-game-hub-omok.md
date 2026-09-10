# P7 게임 허브·공통 온라인 코어·Game Center 전적·오목 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 요트 전용이던 온라인 코어를 게임에 무관하게 떼어내고, 게임 허브와 Game Center 신원·전적을 붙이며, 오목을 온라인·로컬 2인으로 완주하게 한다.

**Architecture:** 새 패키지 `GameCore`의 `Game` 프로토콜과 `MoveLog<G>`가 규칙 계층이고, `TurnTransport`는 JSON `Data`만 나르며, 새 게임은 `OnlineMatch<G>`가 로그·재생·Presence·연결·푸시를 맡는다. 요트는 기존 `GameSession`을 유지하고 전송만 공유한다. 서버 `matches`는 `game`·`host_player`·`guest_player`·`winner_seat` 열을 얻고 전적은 `records` 뷰로 읽는다.

**Tech Stack:** Swift 6 / SwiftUI / Swift Testing, XcodeGen, supabase-swift 2.55.1, Supabase Postgres(RLS, 트리거, 뷰), GameKit(인증·리더보드), App Store Connect API(`Tools/Release/asc.swift`).

**Spec:** `docs/superpowers/specs/2026-09-10-p7-game-hub-omok-design.md`

## Global Constraints

- iOS 18, Swift 6 strict concurrency(`SWIFT_STRICT_CONCURRENCY: complete`), `SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY: YES` — 프로토콜 존재형은 `any`를 쓴다.
- 프로젝트 파일은 `project.yml`에서 `DEVELOPMENT_TEAM=9P8KX3RJRR xcodegen generate`로 만든다. 새 소스는 `App/` 아래 두면 자동으로 들어간다.
- 테스트 실행: `S=/private/tmp/claude-501/-Users-leejungheon-Library-Mobile-Documents-com-apple-CloudDocs-yacht-dice-proj/7bfe8fb6-6a43-43a4-be4d-6f5841bcb76e/scratchpad; xcodebuild -project YachtDice.xcodeproj -scheme YachtDice -destination 'id=64A5E02A-510C-4E97-AFF0-5BB8AFA368EB' -derivedDataPath $S/dd -only-testing:YachtDiceTests test 2>&1 | grep -E "error:|✘|Test run"`. 패키지 단위 테스트는 `swift test --package-path Packages/GameCore`.
- 통합 테스트는 `TEST_RUNNER_YACHT_SUPABASE_E2E=1`을 붙이고 `-only-testing:YachtDiceTests/SupabaseE2ETests`. 익명 가입은 시간당 30회 한도가 있어 한 시간에 두 번 이상 돌리면 `notSignedIn`으로 실패한다.
- Supabase 프로젝트 ref `lkernselwouldtuialjh`. 마이그레이션은 `supabase/migrations/*.sql`에 쓰고 MCP `apply_migration`으로 적용한다.
- 한국어 주석·문서는 `~다` 종결, 연결 문장, 사고 과정 배제(`writing-korean-prose` 스킬).
- 게임 ID 문자열은 `"yacht"`, `"omok"`, `"cuppong"`, `"alkkagi"`. 리더보드 ID는 `wins.<game>`.
- 커밋마다 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`를 붙인다.

---

### Task 1: GameCore 패키지 — Game, Outcome, MoveLog, Omok

**Files:**
- Create: `Packages/GameCore/Package.swift`, `Packages/GameCore/Sources/GameCore/Game.swift`, `Packages/GameCore/Sources/GameCore/MoveLog.swift`, `Packages/GameCore/Sources/GameCore/Omok.swift`
- Test: `Packages/GameCore/Tests/GameCoreTests/OmokTests.swift`, `Packages/GameCore/Tests/GameCoreTests/MoveLogTests.swift`
- Modify: `project.yml` (`packages:`에 GameCore, `YachtDice` 타깃 `dependencies:`에 `- package: GameCore`)

**Interfaces:**
- Produces: `public protocol Game { associatedtype State; associatedtype Move; static var id, displayName: String; static var seatCount: Int; static func initial() -> State; static func canApply(_:to:) -> Bool; static func apply(_:to:) -> State; static func currentSeat(_:) -> Int?; static func outcome(_:) -> Outcome? }`, `public enum Outcome { case win(seat: Int), draw }`, `public struct MoveLog<G: Game> { var moves: [G.Move]; var state: G.State; mutating func append(_:) -> Bool; func encoded() throws -> Data; static func decoded(from:) throws -> Self }`, `public enum Omok: Game` with `State { cells: [UInt8]; nextSeat: Int?; lastMove: Move?; outcome: Outcome? }`, `Move { x, y }`, `static let size = 15`.

- [ ] **Step 1: 패키지 뼈대와 실패하는 테스트**

`Packages/GameCore/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GameCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "GameCore", targets: ["GameCore"])],
    targets: [
        .target(name: "GameCore"),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"]),
    ]
)
```

`Packages/GameCore/Tests/GameCoreTests/OmokTests.swift`:
```swift
import Testing
@testable import GameCore

@Suite("오목 규칙")
struct OmokTests {
    private func play(_ moves: [(Int, Int)]) -> Omok.State {
        var state = Omok.initial()
        for (x, y) in moves {
            let move = Omok.Move(x: x, y: y)
            precondition(Omok.canApply(move, to: state), "적용 불가 \(move)")
            state = Omok.apply(move, to: state)
        }
        return state
    }

    @Test("빈 판은 흑(좌석 0) 차례이고 끝나지 않았다")
    func 초기() {
        let s = Omok.initial()
        #expect(s.cells.count == 225 && s.cells.allSatisfy { $0 == 0 })
        #expect(Omok.currentSeat(s) == 0 && Omok.outcome(s) == nil)
    }

    @Test("가로 5목이면 흑이 이긴다")
    func 가로() {
        // 흑 (0..4, 0), 백 (0..3, 1)
        let s = play([(0,0),(0,1),(1,0),(1,1),(2,0),(2,1),(3,0),(3,1),(4,0)])
        #expect(Omok.outcome(s) == .win(seat: 0))
        #expect(Omok.currentSeat(s) == nil)
    }

    @Test("세로·대각선 5목과 6목도 승리다")
    func 방향들() {
        let 세로 = play([(7,0),(0,0),(7,1),(0,1),(7,2),(0,2),(7,3),(0,3),(7,4)])
        #expect(Omok.outcome(세로) == .win(seat: 0))
        let 대각 = play([(0,0),(1,0),(1,1),(2,0),(2,2),(3,0),(3,3),(4,0),(4,4)])
        #expect(Omok.outcome(대각) == .win(seat: 0))
        let 역대각 = play([(4,0),(0,0),(3,1),(0,1),(2,2),(0,2),(1,3),(0,3),(0,4)])
        #expect(Omok.outcome(역대각) == .win(seat: 0))
        // 백이 6목: 흑은 14행에 흩어 둔다
        let 육목 = play([(0,14),(0,0),(2,14),(1,0),(4,14),(2,0),(6,14),(3,0),(8,14),(5,0),(10,14),(4,0)])
        #expect(Omok.outcome(육목) == .win(seat: 1))
    }

    @Test("찬 칸·범위 밖·끝난 판에는 둘 수 없다")
    func 검증() {
        var s = Omok.initial()
        #expect(!Omok.canApply(Omok.Move(x: 15, y: 0), to: s))
        #expect(!Omok.canApply(Omok.Move(x: -1, y: 3), to: s))
        s = Omok.apply(Omok.Move(x: 7, y: 7), to: s)
        #expect(!Omok.canApply(Omok.Move(x: 7, y: 7), to: s))
        #expect(Omok.currentSeat(s) == 1)
        let done = play([(0,0),(0,1),(1,0),(1,1),(2,0),(2,1),(3,0),(3,1),(4,0)])
        #expect(!Omok.canApply(Omok.Move(x: 9, y: 9), to: done))
    }

    @Test("225수가 차면 무승부다")
    func 무승부() {
        // 5목이 생기지 않는 배열: 행마다 2칸씩 색을 바꿔 채운다(흑흑백백…), 행이 바뀔 때 한 칸 밀어 세로·대각도 끊는다
        var s = Omok.initial()
        var seat = 0
        var placed = 0
        // 같은 색이 가로 최대 2, 세로·대각 최대 2가 되도록 색 지도를 만들고, 차례에 맞는 색이 남아 있는 칸을 고른다
        func color(_ x: Int, _ y: Int) -> Int { (((x + 2 * y) / 2) % 2) }
        var free = (0..<225).map { ($0 % 15, $0 / 15) }
        while !free.isEmpty {
            guard let i = free.firstIndex(where: { color($0.0, $0.1) == seat }) ?? free.indices.first else { break }
            let (x, y) = free.remove(at: i)
            let move = Omok.Move(x: x, y: y)
            #expect(Omok.canApply(move, to: s), "\(placed)번째 수 \(move)를 둘 수 없다")
            s = Omok.apply(move, to: s)
            placed += 1
            if Omok.outcome(s) != nil { break }
            seat = 1 - seat
        }
        #expect(placed == 225 && Omok.outcome(s) == .draw, "놓은 수 \(placed), 결과 \(String(describing: Omok.outcome(s)))")
    }
}
```

`Packages/GameCore/Tests/GameCoreTests/MoveLogTests.swift`:
```swift
import Testing
import Foundation
@testable import GameCore

@Suite("MoveLog")
struct MoveLogTests {
    @Test("수를 더하면 상태가 따라오고 규칙에 어긋난 수는 거부한다")
    func 추가() {
        var log = MoveLog<Omok>()
        #expect(log.append(Omok.Move(x: 7, y: 7)))
        #expect(!log.append(Omok.Move(x: 7, y: 7)))
        #expect(log.moves.count == 1 && log.state.cells[7 * 15 + 7] == 1)
    }

    @Test("JSON 왕복이 같고, 적용 불가한 로그는 디코드에서 던진다")
    func 왕복() throws {
        var log = MoveLog<Omok>()
        _ = log.append(Omok.Move(x: 0, y: 0)); _ = log.append(Omok.Move(x: 1, y: 1))
        let data = try log.encoded()
        #expect(try MoveLog<Omok>.decoded(from: data) == log)
        let bad = Data("{\"moves\":[{\"x\":0,\"y\":0},{\"x\":0,\"y\":0}]}".utf8)
        #expect(throws: (any Error).self) { try MoveLog<Omok>.decoded(from: bad) }
    }
}
```

- [ ] **Step 2: 실패 확인** — `swift test --package-path Packages/GameCore 2>&1 | tail -3` → 컴파일 오류(`Omok` 없음).

- [ ] **Step 3: 구현**

`Game.swift`:
```swift
import Foundation

/// 승부의 결말. 진행 중이면 nil을 쓴다.
public enum Outcome: Codable, Equatable, Sendable {
    case win(seat: Int)
    case draw
}

/// 턴제 게임 하나의 규칙. 상태는 값이고 수는 그대로 로그에 남는다.
public protocol Game {
    associatedtype State: Codable & Equatable & Sendable
    associatedtype Move: Codable & Equatable & Sendable
    /// 서버 `matches.game` 열과 같은 문자열.
    static var id: String { get }
    static var displayName: String { get }
    static var seatCount: Int { get }
    static func initial() -> State
    static func canApply(_ move: Move, to state: State) -> Bool
    static func apply(_ move: Move, to state: State) -> State
    /// 다음에 둘 좌석. 끝났으면 nil.
    static func currentSeat(_ state: State) -> Int?
    static func outcome(_ state: State) -> Outcome?
}
```

`MoveLog.swift`:
```swift
import Foundation

/// 수 목록이 곧 판이다. 상태는 처음부터 다시 적용해 만들며, 디코드도 같은 길을 지나 신뢰 경계를 지킨다.
public struct MoveLog<G: Game>: Codable, Equatable, Sendable {
    public private(set) var moves: [G.Move]
    public private(set) var state: G.State

    public init() {
        moves = []
        state = G.initial()
    }

    /// 규칙에 맞으면 더하고 참, 아니면 그대로 두고 거짓.
    @discardableResult
    public mutating func append(_ move: G.Move) -> Bool {
        guard G.canApply(move, to: state) else { return false }
        moves.append(move)
        state = G.apply(move, to: state)
        return true
    }

    public var isFinished: Bool { G.outcome(state) != nil }

    enum CodingKeys: String, CodingKey { case moves }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let moves = try container.decode([G.Move].self, forKey: .moves)
        self.init()
        for (index, move) in moves.enumerated() {
            guard append(move) else {
                throw DecodingError.dataCorruptedError(forKey: .moves, in: container,
                                                       debugDescription: "\(index)번째 수를 적용할 수 없다")
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(moves, forKey: .moves)
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decoded(from data: Data) throws -> Self { try JSONDecoder().decode(Self.self, from: data) }
}
```

`Omok.swift`:
```swift
import Foundation

/// 15×15 오목. 흑(좌석 0)이 먼저, 5개 이상 이으면 승리, 금수 없음, 판이 차면 무승부.
public enum Omok: Game {
    public static let id = "omok"
    public static let displayName = "오목"
    public static let seatCount = 2
    public static let size = 15

    public struct Move: Codable, Equatable, Sendable {
        public let x: Int
        public let y: Int
        public init(x: Int, y: Int) { self.x = x; self.y = y }
    }

    public struct State: Codable, Equatable, Sendable {
        /// 0 빈칸, 1 흑, 2 백. 인덱스는 y * size + x.
        public var cells: [UInt8]
        public var nextSeat: Int?
        public var lastMove: Move?
        public var outcome: Outcome?
        public func stone(x: Int, y: Int) -> UInt8 { cells[y * Omok.size + x] }
    }

    public static func initial() -> State {
        State(cells: Array(repeating: 0, count: size * size), nextSeat: 0, lastMove: nil, outcome: nil)
    }

    public static func canApply(_ move: Move, to state: State) -> Bool {
        guard state.nextSeat != nil, (0..<size).contains(move.x), (0..<size).contains(move.y) else { return false }
        return state.stone(x: move.x, y: move.y) == 0
    }

    public static func apply(_ move: Move, to state: State) -> State {
        guard canApply(move, to: state), let seat = state.nextSeat else { return state }
        var next = state
        let stone = UInt8(seat + 1)
        next.cells[move.y * size + move.x] = stone
        next.lastMove = move
        if longestLine(through: move, stone: stone, in: next) >= 5 {
            next.outcome = .win(seat: seat)
            next.nextSeat = nil
        } else if !next.cells.contains(0) {
            next.outcome = .draw
            next.nextSeat = nil
        } else {
            next.nextSeat = 1 - seat
        }
        return next
    }

    public static func currentSeat(_ state: State) -> Int? { state.nextSeat }
    public static func outcome(_ state: State) -> Outcome? { state.outcome }

    /// 마지막 수를 지나는 네 방향 중 가장 긴 같은 돌의 줄.
    static func longestLine(through move: Move, stone: UInt8, in state: State) -> Int {
        let directions = [(1, 0), (0, 1), (1, 1), (1, -1)]
        return directions.map { dx, dy in
            1 + run(from: move, dx: dx, dy: dy, stone: stone, in: state) + run(from: move, dx: -dx, dy: -dy, stone: stone, in: state)
        }.max() ?? 1
    }

    private static func run(from move: Move, dx: Int, dy: Int, stone: UInt8, in state: State) -> Int {
        var count = 0
        var x = move.x + dx, y = move.y + dy
        while (0..<size).contains(x), (0..<size).contains(y), state.stone(x: x, y: y) == stone {
            count += 1; x += dx; y += dy
        }
        return count
    }
}
```

`project.yml` — `packages:`에 `GameCore: { path: Packages/GameCore }`를 더하고 `YachtDice` 타깃 `dependencies:`에 `- package: GameCore`를 더한다. `DEVELOPMENT_TEAM=9P8KX3RJRR xcodegen generate`.

- [ ] **Step 4: 통과 확인** — `swift test --package-path Packages/GameCore 2>&1 | tail -3` → 7개 통과. 무승부 테스트의 색 지도가 5목을 만들면 `color` 함수를 `((x / 2 + y) % 2)`로 바꿔 다시 돈다(둘 중 하나는 5목이 안 생긴다 — 확인 뒤 남기는 쪽을 주석에 적는다).

- [ ] **Step 5: 커밋** — `git add Packages/GameCore project.yml && git commit -m "feat(core): 게임 프로토콜과 MoveLog, 오목 규칙을 GameCore 패키지로 둔다"`

---

### Task 2: 서버 — game·player·winner 열, join_match, 가드, profiles, records 뷰

**Files:**
- Create: `supabase/migrations/20260910_games.sql`

**Interfaces:**
- Produces: `matches.game text`, `matches.host_player text`, `matches.guest_player text`, `matches.winner_seat smallint`; RPC `join_match(p_code text, p_name text, p_player text default null)`; 테이블 `profiles(player, uid, name, updated_at)`; 뷰 `records(player, game, wins, losses, draws)`.

- [ ] **Step 1: 마이그레이션 작성**

```sql
-- P7: 여러 게임과 Game Center 신원, 승자 기록
alter table public.matches
  add column if not exists game text not null default 'yacht',
  add column if not exists host_player text,
  add column if not exists guest_player text,
  add column if not exists winner_seat smallint;
alter table public.matches drop constraint if exists matches_game_check;
alter table public.matches add constraint matches_game_check
  check (game in ('yacht', 'omok', 'cuppong', 'alkkagi'));
alter table public.matches drop constraint if exists matches_winner_seat_check;
alter table public.matches add constraint matches_winner_seat_check check (winner_seat is null or winner_seat in (0, 1));
create index if not exists matches_host_player_idx on public.matches (host_player) where host_player is not null;
create index if not exists matches_guest_player_idx on public.matches (guest_player) where guest_player is not null;

-- 게스트가 gamePlayerID를 함께 넣는다
drop function if exists public.join_match(text, text);
create or replace function public.join_match(p_code text, p_name text, p_player text default null)
returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  m public.matches;
begin
  if uid is null then
    raise exception 'not signed in';
  end if;
  if p_name is null or char_length(p_name) not between 1 and 20 then
    raise exception 'invalid name';
  end if;
  update public.matches
     set guest_uid = uid, guest_name = p_name, guest_player = p_player, status = 'playing'
   where code = p_code and status = 'waiting' and guest_uid is null and host_uid <> uid
   returning * into m;
  if m.id is null then
    raise exception 'room not found';
  end if;
  return m;
end;
$$;

-- 좌석·게임·플레이어는 고정이고 끝난 판은 바뀌지 않는다
create or replace function public.matches_guard_seats()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.host_uid is distinct from old.host_uid then
    raise exception 'host seat is fixed';
  end if;
  if old.guest_uid is not null and new.guest_uid is distinct from old.guest_uid then
    raise exception 'guest seat is fixed';
  end if;
  if new.game is distinct from old.game then
    raise exception 'game is fixed';
  end if;
  if old.host_player is not null and new.host_player is distinct from old.host_player then
    raise exception 'host player is fixed';
  end if;
  if old.guest_player is not null and new.guest_player is distinct from old.guest_player then
    raise exception 'guest player is fixed';
  end if;
  if old.status = 'finished' then
    raise exception 'match is finished';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Game Center 신원 ↔ 익명 uid
create table if not exists public.profiles (
  player text primary key,
  uid uuid not null references auth.users (id) on delete cascade,
  name text not null,
  updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create policy "profiles read" on public.profiles for select to authenticated using (true);
create policy "profiles insert own" on public.profiles for insert to authenticated with check (uid = (select auth.uid()));
create policy "profiles update own" on public.profiles for update to authenticated
  using (uid = (select auth.uid())) with check (uid = (select auth.uid()));

-- 전적. Game Center 사용자는 gamePlayerID로, 미로그인은 uid로 센다. security_invoker라 내 매치만 보인다.
create or replace view public.records with (security_invoker = true) as
with seats as (
  select game, coalesce(host_player, host_uid::text) as player, 0 as seat, winner_seat from public.matches where status = 'finished'
  union all
  select game, coalesce(guest_player, guest_uid::text), 1, winner_seat from public.matches where status = 'finished' and guest_uid is not null
)
select player, game,
       count(*) filter (where winner_seat = seat) as wins,
       count(*) filter (where winner_seat is not null and winner_seat <> seat) as losses,
       count(*) filter (where winner_seat is null) as draws
from seats group by player, game;
grant select on public.records to authenticated;
```

- [ ] **Step 2: 적용** — MCP `apply_migration(name: "games", query: 위 SQL)`. 이어서 MCP `execute_sql`로 확인:
```sql
select column_name from information_schema.columns where table_name = 'matches' and column_name in ('game','host_player','guest_player','winner_seat');
select proname, pg_get_function_arguments(oid) from pg_proc where proname = 'join_match';
```
→ 열 넷, `join_match(p_code text, p_name text, p_player text DEFAULT NULL::text)`.

- [ ] **Step 3: 가드 확인** — `execute_sql`:
```sql
do $$ declare m uuid; begin
  select id into m from public.matches where status = 'finished' limit 1;
  if m is not null then
    begin update public.matches set turn_seat = 0 where id = m; raise exception 'guard missing';
    exception when others then if sqlerrm <> 'match is finished' then raise; end if; end;
  end if;
end $$;
select count(*) from public.records;
```
→ 오류 없이 끝나고 `records` 카운트가 나온다. 마지막으로 MCP `get_advisors(type: security)`에서 `records`·`profiles` 관련 새 경고가 없는지 본다(익명 정책 경고는 기존과 같다).

- [ ] **Step 4: 커밋** — `git add supabase/migrations/20260910_games.sql && git commit -m "feat(server): 게임·플레이어·승자 열과 profiles, records 뷰를 더한다"`

---

### Task 3: 전송을 게임에서 뗀다 — TurnPayload, Data 로그, Game Center 턴제 코드 삭제

**Files:**
- Modify: `App/Online/TurnTransport.swift`, `App/Online/SupabaseTurnTransport.swift`, `App/Online/MatchRow.swift`, `App/Online/SupabaseService.swift`, `App/Game/GameSession.swift:118-160, 246-300`, `App/AppContainer.swift`, `App/Views/OnlineMenu.swift:333-337`
- Delete: `App/Online/GameCenterTurnTransport.swift`, `App/Online/MatchmakerView.swift`
- Modify tests: `Tests/YachtDiceTests/TurnTransportTests.swift`, `GameSessionOnlineTests.swift`, `OnlineMatchOpenTests.swift`, `MatchRowTests.swift`, `SupabaseE2ETests.swift`

**Interfaces:**
- Produces:
```swift
struct TurnPayload: Sendable, Equatable { let log: Data; let eventCount: Int; let hints: [ThrowHint]; let turnSeat: Int?; let winnerSeat: Int?; let finished: Bool }
struct RemoteUpdate: Sendable, Equatable { let log: Data; let eventCount: Int; let hints: [ThrowHint] }
protocol TurnTransport: Sendable {
    func publish(_ payload: TurnPayload) async throws      // progress·endTurn·endMatch를 하나로
    var incoming: AsyncStream<RemoteUpdate> { get }
    var presence: AsyncStream<Set<String>> { get }
    var connection: AsyncStream<Bool> { get }
    func refresh() async
}
```
  `MatchRow`: `log: Data`(원문 JSON), `game: String`, `hostPlayer: String?`, `guestPlayer: String?`, `winnerSeat: Int?`, `func yachtLog() -> MatchLog?`, `func record(localUid:)`는 `game == "yacht"`일 때만 요트 기록을 준다. `SupabaseService.createRoom(name:game:player:)`, `joinRoom(code:name:player:)`. `InMemoryTurnTransport.sent: [TurnPayload]`, `sentLogs: [Data]`, `finishedTotals` 삭제, `lastPayload`.

- [ ] **Step 1: 실패하는 테스트로 새 모양을 고정한다**

`Tests/YachtDiceTests/TurnTransportTests.swift`를 다음으로 바꾼다:
```swift
import Testing
import Foundation
import YachtCore
@testable import YachtDice

@Suite("턴 전송")
struct TurnTransportTests {
    private func payload(_ text: String, count: Int, turn: Int? = 1, winner: Int? = nil, finished: Bool = false) -> TurnPayload {
        TurnPayload(log: Data(text.utf8), eventCount: count, hints: [], turnSeat: turn, winnerSeat: winner, finished: finished)
    }

    @Test("A가 올린 것이 B에게만 흐르고 A는 보낸 것을 기억한다")
    func 전달() async throws {
        let (a, b) = InMemoryTurnTransport.pair()
        var iterator = b.incoming.makeAsyncIterator()
        let p = payload("{\"n\":1}", count: 1)
        try await a.publish(p)
        let received = await iterator.next()
        #expect(received?.log == p.log && received?.eventCount == 1)
        #expect(a.sent == [p] && a.lastPayload?.turnSeat == 1)
    }

    @Test("끝난 판은 승자와 finished를 싣는다")
    func 종료() async throws {
        let (a, _) = InMemoryTurnTransport.pair()
        try await a.publish(payload("{}", count: 40, turn: nil, winner: 0, finished: true))
        #expect(a.lastPayload?.winnerSeat == 0 && a.lastPayload?.finished == true)
    }

    @Test("힌트가 로그와 함께 전달된다")
    func 힌트_전달() async throws {
        let (a, b) = InMemoryTurnTransport.pair()
        var iterator = b.incoming.makeAsyncIterator()
        let hint = ThrowHint(event: 0, trajectory: 5, direction: 1, yaws: [0, 1, 2, 3, 0])
        try await a.publish(TurnPayload(log: Data("{}".utf8), eventCount: 1, hints: [hint], turnSeat: 0, winnerSeat: nil, finished: false))
        #expect(await iterator.next()?.hints == [hint])
    }

    @Test("쌍을 만들면 서로의 uid가 presence로 흐른다")
    func 접속() async throws {
        let (a, _) = InMemoryTurnTransport.pair(uidA: "a", uidB: "b")
        var iterator = a.presence.makeAsyncIterator()
        #expect(await iterator.next() == ["b"])
    }
}
```

`Tests/YachtDiceTests/MatchRowTests.swift`에 테스트를 더한다(기존 테스트의 `MatchRow(...)` 생성자 호출은 `log:`에 `try MatchLog(playerCount: 2).encoded()`를, 새 인자 `game: "yacht"`를 준다):
```swift
    @Test("행의 log는 원문 JSON이고 요트 행만 요트 로그로 읽힌다")
    func 원문_로그() throws {
        let json = Data("{\"playerCount\":2,\"events\":[]}".utf8)
        let yacht = MatchRow(id: UUID(), code: "000001", hostUid: UUID(), guestUid: UUID(), hostName: "A", guestName: "B",
                             log: json, eventCount: 0, status: "playing", totals: nil, game: "yacht")
        #expect(yacht.yachtLog()?.playerCount == 2)
        let omok = MatchRow(id: UUID(), code: "000002", hostUid: UUID(), guestUid: UUID(), hostName: "A", guestName: "B",
                            log: Data("{\"moves\":[]}".utf8), eventCount: 0, status: "playing", totals: nil, game: "omok")
        #expect(omok.yachtLog() == nil)
        #expect(omok.record(localUid: omok.hostUid) == nil)
    }

    @Test("game·player·winner 열을 읽고 없으면 기본값이다")
    func 새_열() throws {
        let text = """
        {"id":"\(UUID().uuidString)","code":"123456","host_uid":"\(UUID().uuidString)","guest_uid":null,"host_name":"A","guest_name":null,
         "log":{"moves":[]},"event_count":0,"status":"waiting","totals":null,"game":"omok","host_player":"G:1","guest_player":null,"winner_seat":null}
        """
        let row = try JSONDecoder().decode(MatchRow.self, from: Data(text.utf8))
        #expect(row.game == "omok" && row.hostPlayer == "G:1" && row.winnerSeat == nil)
        let legacy = try JSONDecoder().decode(MatchRow.self, from: Data(text.replacingOccurrences(of: ",\"game\":\"omok\",\"host_player\":\"G:1\",\"guest_player\":null,\"winner_seat\":null", with: "").utf8))
        #expect(legacy.game == "yacht" && legacy.hostPlayer == nil)
        #expect(String(data: row.log, encoding: .utf8) == "{\"moves\":[]}")
    }
```

- [ ] **Step 2: 실패 확인** — 단위 테스트 빌드가 `TurnPayload` 없음으로 실패한다.

- [ ] **Step 3: 전송 프로토콜과 메모리 전송**

`App/Online/TurnTransport.swift` 전체:
```swift
import Foundation

/// 내가 서버에 올리는 것. 로그는 게임별 JSON 원문이라 전송은 게임을 모른다.
struct TurnPayload: Sendable, Equatable {
    let log: Data
    /// 로그 안의 수·이벤트 개수. 서버 `event_count`이며 상대는 이 값으로 새 것을 가린다.
    let eventCount: Int
    let hints: [ThrowHint]
    /// 다음에 둘 좌석. 끝났으면 nil. 바뀌면 서버가 그 좌석에게 푸시를 보낸다.
    let turnSeat: Int?
    /// 끝났을 때의 승자. 무승부나 진행 중이면 nil.
    let winnerSeat: Int?
    let finished: Bool
}

/// 상대에게서 온 것.
struct RemoteUpdate: Sendable, Equatable {
    let log: Data
    let eventCount: Int
    let hints: [ThrowHint]
}

/// 온라인 대전의 전송 계층. `GameSession`(요트)과 `OnlineMatch<G>`(그 외)가 같은 것을 쓴다.
protocol TurnTransport: Sendable {
    /// 로그를 올린다. 턴 도중·턴 끝·게임 끝을 payload의 turnSeat·finished가 구분한다.
    func publish(_ payload: TurnPayload) async throws
    var incoming: AsyncStream<RemoteUpdate> { get }
    /// 채널에 함께 있는 참가자의 uid 집합. 기본은 빈 스트림.
    var presence: AsyncStream<Set<String>> { get }
    /// 채널이 구독된 상태인가. 기본은 빈 스트림(항상 연결된 것으로 본다).
    var connection: AsyncStream<Bool> { get }
    /// 서버 상태를 한 번 읽어 새 것이 있으면 `incoming`으로 흘린다.
    func refresh() async
}

extension TurnTransport {
    var presence: AsyncStream<Set<String>> { AsyncStream { $0.finish() } }
    var connection: AsyncStream<Bool> { AsyncStream { $0.finish() } }
    func refresh() async {}
}

/// 같은 프로세스 안의 두 세션을 잇는다. 테스트와 디버깅용.
final class InMemoryTurnTransport: TurnTransport, @unchecked Sendable {
    private let lock = NSLock()
    private weak var peer: InMemoryTurnTransport?
    private var continuation: AsyncStream<RemoteUpdate>.Continuation?
    private var presenceContinuation: AsyncStream<Set<String>>.Continuation?
    let incoming: AsyncStream<RemoteUpdate>
    let presence: AsyncStream<Set<String>>
    private var _sent: [TurnPayload] = []

    var sent: [TurnPayload] { lock.withLock { _sent } }
    var sentLogs: [Data] { sent.map(\.log) }
    var lastPayload: TurnPayload? { sent.last }

    private init() {
        var continuation: AsyncStream<RemoteUpdate>.Continuation!
        incoming = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation
        var presenceContinuation: AsyncStream<Set<String>>.Continuation!
        presence = AsyncStream(bufferingPolicy: .unbounded) { presenceContinuation = $0 }
        self.presenceContinuation = presenceContinuation
    }

    static func pair(uidA: String = "a", uidB: String = "b") -> (InMemoryTurnTransport, InMemoryTurnTransport) {
        let a = InMemoryTurnTransport(), b = InMemoryTurnTransport()
        a.peer = b
        b.peer = a
        a.presenceContinuation?.yield([uidB])
        b.presenceContinuation?.yield([uidA])
        return (a, b)
    }

    func publish(_ payload: TurnPayload) async throws {
        lock.withLock { _sent.append(payload) }
        peer?.continuation?.yield(RemoteUpdate(log: payload.log, eventCount: payload.eventCount, hints: payload.hints))
    }
}
```

- [ ] **Step 4: MatchRow와 SupabaseService**

`App/Online/MatchRow.swift`에서 `var log: MatchLog`를 `var log: Data`로 바꾸고 `game: String = "yacht"`, `hostPlayer: String?`, `guestPlayer: String?`, `winnerSeat: Int?`를 더한다. `CodingKeys`에 `game`, `hostPlayer = "host_player"`, `guestPlayer = "guest_player"`, `winnerSeat = "winner_seat"`를 더한다. 멤버 초기화자의 인자 순서는 `id, code, hostUid, guestUid, hostName, guestName, log: Data, eventCount, status, totals, hints = [], turnSeat = nil, game = "yacht", hostPlayer = nil, guestPlayer = nil, winnerSeat = nil`이다(뒤 Task의 테스트가 이 순서로 부른다). `init(from:)`에서 `log`는 원문을 남기기 위해 다음처럼 읽는다:
```swift
        // 서버가 jsonb를 객체로 주므로 그대로 다시 인코드해 원문 Data로 둔다. 게임별 디코드는 호출자가 한다.
        let raw = try c.decode(JSONValue.self, forKey: .log)
        log = try JSONEncoder().encode(raw)
        game = try c.decodeIfPresent(String.self, forKey: .game) ?? "yacht"
        hostPlayer = try c.decodeIfPresent(String.self, forKey: .hostPlayer)
        guestPlayer = try c.decodeIfPresent(String.self, forKey: .guestPlayer)
        winnerSeat = try c.decodeIfPresent(Int.self, forKey: .winnerSeat)
```
`encode(to:)`를 직접 써서 `log`는 `JSONValue`로 디코드해 넣고(`try container.encode(JSONDecoder().decode(JSONValue.self, from: log), forKey: .log)`) 나머지는 그대로 인코드한다. `JSONValue`는 같은 파일에 둔다:
```swift
/// 어떤 JSON이든 잃지 않고 왕복한다. 서버 jsonb 열을 원문 Data로 두기 위해서다.
enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
```
`func yachtLog() -> MatchLog? { game == "yacht" ? try? MatchLog.decoded(from: log) : nil }`. `record(localUid:)`는 `guard let log = yachtLog(), guestUid != nil ...`로 바꾸고 `log.playerCount == 2`를 그대로 검사한다. `isMyTurn`용으로 `var isFinishedRow: Bool { status == "finished" }`는 기존 `isFinished`를 쓴다.

`App/Online/SupabaseService.swift`:
- `createRoom(name: String, game: String = "yacht", player: String? = nil)`: `NewMatch`에 `game`, `hostPlayer`(`host_player`)와 `log: JSONValue`를 두고, `log`는 게임별 빈 로그다 — `game == "yacht"`면 `try JSONDecoder().decode(JSONValue.self, from: MatchLog(playerCount: 2).encoded())`, 아니면 `.object(["moves": .array([])])`.
- `joinRoom(code: String, name: String, player: String? = nil)`: `params`를 `["p_code": code, "p_name": name, "p_player": player ?? ""]`로 보내되 `player`가 nil이면 `p_player`를 빼고 보낸다(`var params: [String: String] = [...]; if let player { params["p_player"] = player }`).
- `OnlineMenu.isMyTurn(_:)`: `row.log.state.currentPlayer == mySeat` 대신 `row.turnSeat == mySeat`를 쓴다(P6부터 서버가 `turn_seat`를 갖는다. 대기 방은 nil이라 거짓).

- [ ] **Step 5: SupabaseTurnTransport**

`App/Online/SupabaseTurnTransport.swift`에서 `import YachtCore`를 지우고:
- `deliver(_ row: MatchRow)`: `row.log.events.count` 대신 `row.eventCount`로 새 것을 가리고 `RemoteUpdate(log: row.log, eventCount: row.eventCount, hints: row.hints)`를 흘린다.
- `publishProgress`/`endTurn`/`endMatch` 셋을 지우고
```swift
    func publish(_ payload: TurnPayload) async throws {
        try await send(TurnUpdate(log: payload.log, hints: payload.hints, eventCount: payload.eventCount,
                                  status: payload.finished ? "finished" : "playing",
                                  turnSeat: payload.turnSeat, winnerSeat: payload.winnerSeat))
    }
```
- `TurnUpdate`에서 `log: MatchLog`를 `log: Data`로, `totals`를 `winnerSeat: Int?`(`winner_seat`)로 바꾸고 `encode(to:)`에서 `try container.encode(JSONDecoder().decode(JSONValue.self, from: log), forKey: .log)`로 원문을 jsonb로 넣는다. `totals`는 더 이상 쓰지 않는다(열은 남겨 둔다).

- [ ] **Step 6: GameSession 어댑터**

`App/Game/GameSession.swift`:
- `publishProgressIfOnline`: `try await transport.publish(payload(finished: false, turnSeat: visibleState.currentPlayer))`.
- `publishTurnIfNeeded`: 끝났으면 `publish(payload(finished: true, turnSeat: nil))`, 원격 좌석 차례면 `publish(payload(finished: false, turnSeat: visibleState.currentPlayer))`.
- 도우미:
```swift
    /// 요트 로그를 전송용 JSON으로 싼다. 총점 동점이면 승자 없음(무승부).
    private func payload(finished: Bool, turnSeat: Int?) throws -> TurnPayload {
        var winner: Int? = nil
        if finished {
            let totals = visibleState.scorecards.map(\.total)
            if let best = totals.max(), totals.filter({ $0 == best }).count == 1 { winner = totals.firstIndex(of: best) }
        }
        return TurnPayload(log: try record.log.encoded(), eventCount: record.log.events.count, hints: throwHints,
                           turnSeat: turnSeat, winnerSeat: winner, finished: finished)
    }
```
- `replay(remote update: RemoteUpdate)` 첫 줄을 `guard let log = try? MatchLog.decoded(from: update.log) else { lastTransportError = "상대의 기록을 읽을 수 없다"; return }`로 바꾼다.
- `waitForIncoming`은 그대로다.

- [ ] **Step 7: Game Center 턴제 코드 삭제와 AppContainer**

`git rm App/Online/GameCenterTurnTransport.swift App/Online/MatchmakerView.swift`. `App/Online/GameCenterService.swift`에서 `activeMatches`, `onMatchOpened`, `streams`, `stream(for:)`, `reloadMatches`, `GKLocalPlayerListener` 채택과 두 `player(_:...)` 메서드, `deliver`, `import YachtCore`를 지우고 인증만 남긴다(Task 7이 다시 채운다). `AppContainer`에서 `startOnlineMatch(_ match: GKTurnBasedMatch)`와 `gameCenter.onMatchOpened = ...` 줄, `import GameKit`을 지우고, `openSupabaseMatch`는 `let data = row.log`로 바꾼다. `MenuScreen`의 온라인 카드 부제 "Game Center로 친구·랜덤 매칭"을 "방 코드로 친구와 겨룬다"로 바꾼다.

- [ ] **Step 8: 테스트 갱신**

- `GameSessionOnlineTests.swift`: `조작_거부`에서 `try await ta.endTurn(log: forged, hints: [], nextSeat: 1)`을 `try await ta.publish(TurnPayload(log: try forged.encoded(), eventCount: forged.events.count, hints: [], turnSeat: 1, winnerSeat: nil, finished: false))`로. `#expect(ta.sentLogs ...)`류가 있으면 `ta.sent.map { try? MatchLog.decoded(from: $0.log) }`로 비교한다. `완주` 테스트가 `finishedTotals`를 보면 `ta.lastPayload?.finished == true && ta.lastPayload?.winnerSeat != nil || 총점 동점`으로 바꾼다.
- `OnlineMatchOpenTests.swift`: `theirs.endTurn(log: next, hints: [], nextSeat: 0)`를 `theirs.publish(TurnPayload(log: try next.encoded(), eventCount: next.events.count, hints: [], turnSeat: 0, winnerSeat: nil, finished: false))`로.
- `SupabaseE2ETests.swift`: `refreshed.record(localUid:)`는 그대로 동작한다(요트 행). 마지막 `final.log == hostSession.record.log`는 `try #require(final.yachtLog()) == hostSession.record.log`로. 통합 테스트는 이 Task에서 돌리지 않고 Task 8에서 한 번에 돈다.
- `AppSmokeTests`·`AppContainerTests`에 `MatchmakerView`나 `GKTurnBasedMatch` 참조가 있으면 지운다.

- [ ] **Step 9: 단위 테스트 전체 통과** — Global Constraints의 명령. 회귀가 없어야 한다(요트 온라인 5개, 열기 6개 포함).

- [ ] **Step 10: 커밋** — `git add -A && git commit -m "refactor(online): 전송이 JSON 로그만 나르게 하고 Game Center 턴제 코드를 지운다"`

---

### Task 4: MatchRecord v3와 OnlineMatch<G>

**Files:**
- Modify: `App/Game/Participant.swift` (`MatchRecord`), `App/Game/MatchStore.swift`, `App/AppContainer.swift`, `App/Views/MenuScreen.swift:resumeCard`
- Create: `App/Game/OnlineMatch.swift`
- Test: `Tests/YachtDiceTests/OnlineMatchTests.swift`, `Tests/YachtDiceTests/MatchStoreTests.swift`(추가)

**Interfaces:**
- Consumes: Task 1 `Game`, `MoveLog<G>`, `Omok`; Task 3 `TurnTransport`, `TurnPayload`, `RemoteUpdate`.
- Produces:
```swift
struct MatchRecord { static let formatVersion = 3; var game: String; var mode: GameMode; var participants: [Participant]; var log: MatchLog /* 요트 */ ; var moveLog: Data? /* 그 외 게임 */ }
@MainActor @Observable final class OnlineMatch<G: Game> {
    init(game: G.Type, mode: GameMode, participants: [Participant], log: MoveLog<G>, transport: (any TurnTransport)?)
    private(set) var log: MoveLog<G>; var state: G.State { log.state }
    let participants: [Participant]; let mode: GameMode
    var localSeat: Int?            // 로컬 2인은 현재 좌석, 온라인은 내 좌석
    var isLocalTurn: Bool; var outcome: Outcome?
    private(set) var opponentPresent: Bool; private(set) var isConnected: Bool; private(set) var lastTransportError: String?
    private(set) var isReplaying: Bool
    var onRemoteMove: ((G.Move, ThrowHint?) async -> Void)?
    var onLogChanged: ((Data) -> Void)?
    struct RemoteMove: Equatable { let id: UUID; let seat: Int; let move: G.Move }
    private(set) var lastRemoteMove: RemoteMove?
    func play(_ move: G.Move, hint: ThrowHint? = nil) async -> Bool
    func startListening(); func resync() async; func waitForIncoming() async
    func encodedLog() throws -> Data
}
```

- [ ] **Step 1: 실패하는 테스트**

`Tests/YachtDiceTests/OnlineMatchTests.swift`:
```swift
import Testing
import Foundation
import GameCore
@testable import YachtDice

@Suite("OnlineMatch - 오목")
@MainActor
struct OnlineMatchTests {
    private func makePair() -> (OnlineMatch<Omok>, OnlineMatch<Omok>, InMemoryTurnTransport, InMemoryTurnTransport) {
        let (ta, tb) = InMemoryTurnTransport.pair()
        let seatsA: [Participant] = [.human(name: "A"), .remote(playerID: "b", name: "B")]
        let seatsB: [Participant] = [.remote(playerID: "a", name: "A"), .human(name: "B")]
        let a = OnlineMatch(game: Omok.self, mode: .online(matchID: "m"), participants: seatsA, log: MoveLog<Omok>(), transport: ta)
        let b = OnlineMatch(game: Omok.self, mode: .online(matchID: "m"), participants: seatsB, log: MoveLog<Omok>(), transport: tb)
        a.startListening(); b.startListening()
        return (a, b, ta, tb)
    }

    @Test("내 수가 상대에게 재생되고 차례가 넘어간다")
    func 한_수_전파() async throws {
        let (a, b, ta, _) = makePair()
        var replayed: [Omok.Move] = []
        b.onRemoteMove = { move, _ in replayed.append(move) }
        #expect(a.isLocalTurn && !b.isLocalTurn)
        #expect(await a.play(Omok.Move(x: 7, y: 7)))
        await b.waitForIncoming()
        #expect(replayed == [Omok.Move(x: 7, y: 7)])
        #expect(b.state.stone(x: 7, y: 7) == 1 && b.isLocalTurn && !a.isLocalTurn)
        #expect(ta.lastPayload?.turnSeat == 1 && ta.lastPayload?.eventCount == 1)
        #expect(b.lastRemoteMove?.seat == 0)
    }

    @Test("내 차례가 아니거나 규칙에 어긋나면 두지 않는다")
    func 거부() async {
        let (a, b, ta, _) = makePair()
        #expect(await b.play(Omok.Move(x: 0, y: 0)) == false)
        #expect(await a.play(Omok.Move(x: 99, y: 0)) == false)
        #expect(ta.sent.isEmpty)
    }

    @Test("5목이면 끝나고 승자가 실린다")
    func 완주() async throws {
        let (a, b, ta, _) = makePair()
        let moves: [(OnlineMatch<Omok>, Int, Int)] = [(a,0,0),(b,0,1),(a,1,0),(b,1,1),(a,2,0),(b,2,1),(a,3,0),(b,3,1),(a,4,0)]
        for (m, x, y) in moves {
            #expect(await m.play(Omok.Move(x: x, y: y)), "\(x),\(y)")
            await (m === a ? b : a).waitForIncoming()
        }
        #expect(a.outcome == .win(seat: 0) && b.outcome == .win(seat: 0))
        #expect(ta.lastPayload?.finished == true && ta.lastPayload?.winnerSeat == 0 && ta.lastPayload?.turnSeat == nil)
        #expect(!a.isLocalTurn && !b.isLocalTurn)
    }

    @Test("조작된 로그는 거부하고 이유를 남긴다")
    func 조작_거부() async throws {
        let (a, b, ta, _) = makePair()
        _ = await a.play(Omok.Move(x: 7, y: 7))
        await b.waitForIncoming()
        // B의 전송 대신 A가 자기 차례가 아닌 수를 로그에 끼워 넣는다
        var forged = a.log
        _ = forged.append(Omok.Move(x: 8, y: 8))   // 백 차례라 규칙상은 유효하지만 좌석이 다르다: 두 수 연속
        _ = forged.append(Omok.Move(x: 9, y: 9))
        try await ta.publish(TurnPayload(log: try forged.encoded(), eventCount: forged.moves.count, hints: [], turnSeat: 1, winnerSeat: nil, finished: false))
        await b.waitForIncoming()
        // 8,8은 백(좌석 1 = B) 수로 해석되지만 B는 두지 않았으므로 B 화면에서는 상대가 내 차례에 둔 것 — 거부한다
        #expect(b.lastTransportError != nil && b.log.moves.count == 1)
    }

    @Test("로컬 2인은 전송 없이 같은 객체에서 좌석이 번갈아 바뀐다")
    func 로컬_2인() async {
        let m = OnlineMatch(game: Omok.self, mode: .passAndPlay(names: ["갑", "을"]),
                            participants: [.human(name: "갑"), .human(name: "을")], log: MoveLog<Omok>(), transport: nil)
        #expect(m.localSeat == 0 && m.isLocalTurn)
        #expect(await m.play(Omok.Move(x: 7, y: 7)))
        #expect(m.localSeat == 1 && m.isLocalTurn)
        var saved: Data?
        m.onLogChanged = { saved = $0 }
        #expect(await m.play(Omok.Move(x: 8, y: 8)))
        #expect(saved != nil && m.localSeat == 0)
    }
}
```

`MatchStoreTests.swift`에 더한다:
```swift
    @Test("오목 기록은 moveLog로 저장되고 그대로 돌아온다")
    func 오목_왕복() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        var log = MoveLog<Omok>()
        _ = log.append(Omok.Move(x: 7, y: 7))
        let record = MatchRecord(game: Omok.id, mode: .passAndPlay(names: ["갑", "을"]),
                                 participants: [.human(name: "갑"), .human(name: "을")], moveLog: try log.encoded())
        try store.save(record)
        let loaded = try #require(store.load())
        #expect(loaded.game == "omok" && loaded.moveLog == record.moveLog && loaded.log.events.isEmpty)
    }

    @Test("v2 파일은 game이 yacht로 읽힌다")
    func v2_호환() throws {
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let v2 = """
        {"formatVersion":2,"mode":{"solo":{}},"participants":[{"human":{"name":"나"}}],"log":{"playerCount":1,"events":[]}}
        """
        try Data(v2.utf8).write(to: dir.appending(path: "match.json"))
        let loaded = try #require(store.load())
        #expect(loaded.game == "yacht" && loaded.mode == .solo)
    }
```
(`MatchStoreTests`에 `import GameCore`를 더한다. v2 JSON의 enum 인코딩 모양은 `JSONEncoder`가 `GameMode.solo`를 `{"solo":{}}`로 쓰는 것과 같다 — 다르면 기존 테스트 `왕복`이 저장한 파일을 `cat`해 맞춘다.)

- [ ] **Step 2: 실패 확인** — `OnlineMatch` 없음으로 빌드 실패.

- [ ] **Step 3: MatchRecord v3와 MatchStore**

`App/Game/Participant.swift`의 `MatchRecord`:
```swift
struct MatchRecord: Codable, Equatable, Sendable {
    static let formatVersion = 3

    var formatVersion: Int
    /// "yacht", "omok", "cuppong", "alkkagi".
    var game: String
    var mode: GameMode
    var participants: [Participant]
    /// 요트 로그. 다른 게임이면 빈 로그다.
    var log: MatchLog
    /// 요트가 아닌 게임의 `MoveLog` JSON.
    var moveLog: Data?

    init(mode: GameMode) { ...기존과 같고 game = "yacht"... }

    init(mode: GameMode, participants: [Participant], log: MatchLog) {
        self.init(game: "yacht", mode: mode, participants: participants, log: log, moveLog: nil)
    }

    init(game: String, mode: GameMode, participants: [Participant], moveLog: Data) {
        self.init(game: game, mode: mode, participants: participants, log: MatchLog(playerCount: participants.count), moveLog: moveLog)
    }

    private init(game: String, mode: GameMode, participants: [Participant], log: MatchLog, moveLog: Data?) {
        formatVersion = Self.formatVersion; self.game = game; self.mode = mode
        self.participants = participants; self.log = log; self.moveLog = moveLog
    }

    var isYacht: Bool { game == "yacht" }
    /// 끝났는가. 요트는 로그가, 다른 게임은 저장 전에 호출자가 `finished`를 판단해 `moveLog`를 nil로 두므로 여기서는 요트만 본다.
    var isFinished: Bool { isYacht ? log.isFinished : false }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        game = try c.decodeIfPresent(String.self, forKey: .game) ?? "yacht"
        mode = try c.decode(GameMode.self, forKey: .mode)
        participants = try c.decode([Participant].self, forKey: .participants)
        log = try c.decode(MatchLog.self, forKey: .log)
        moveLog = try c.decodeIfPresent(Data.self, forKey: .moveLog)
    }
}
```
(합성 `encode`는 그대로 쓴다. `CodingKeys`는 `formatVersion, game, mode, participants, log, moveLog`.)

`MatchStore.load()`에서 `record.formatVersion == MatchRecord.formatVersion` 검사를 `(2...3).contains(record.formatVersion)`으로 넓히고, 요트가 아니면 로그 재생 검증을 건너뛰고 `moveLog != nil`만 요구한다:
```swift
        if let record = try? JSONDecoder().decode(MatchRecord.self, from: data) {
            guard (2...MatchRecord.formatVersion).contains(record.formatVersion) else { return nil }
            if !record.isYacht {
                return record.moveLog == nil ? nil : record
            }
            guard record.participants.count == record.log.playerCount, ... 기존 검증 ... else { return nil }
            return MatchRecord(mode: record.mode, participants: record.participants, log: log)
        }
```
`save`는 그대로다(`isFinished`가 참이면 지운다). `OnlineMatch`는 끝난 판을 저장하지 않고 `clear`를 부른다(Step 4).

- [ ] **Step 4: OnlineMatch<G>**

`App/Game/OnlineMatch.swift`:
```swift
import Foundation
import GameCore
import Observation

/// 요트가 아닌 게임의 세션. 로그·검증·전송·원격 재생·접속 상태를 맡고, 화면은 `onRemoteMove`로 상대 수를 그린다.
/// 로컬 2인은 전송이 nil인 같은 객체이며 수마다 좌석이 바뀐다.
@MainActor
@Observable
final class OnlineMatch<G: Game> {
    let mode: GameMode
    let participants: [Participant]
    private(set) var log: MoveLog<G>
    var state: G.State { log.state }
    var outcome: Outcome? { G.outcome(state) }

    /// 원격 재생 중이면 참. 입력을 잠근다.
    private(set) var isReplaying = false
    private(set) var opponentPresent = false
    private(set) var isConnected = true
    private(set) var lastTransportError: String?

    struct RemoteMove: Equatable {
        let id = UUID()
        let seat: Int
        let move: G.Move
    }
    /// 상대가 방금 둔 수. 화면이 팝업으로 알린다.
    private(set) var lastRemoteMove: RemoteMove?

    /// 상대 수를 화면에서 재생한다. 끝날 때까지 다음 수를 넘기지 않는다.
    var onRemoteMove: (@MainActor (G.Move, ThrowHint?) async -> Void)?
    /// 로그가 바뀌었다. 로컬 판은 저장하고, 끝났으면 nil을 준다.
    var onLogChanged: (@MainActor (Data?) -> Void)?

    private let transport: (any TurnTransport)?
    private var listenTask: Task<Void, Never>?
    private var presenceTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var replayTask: Task<Void, Never>?
    private var hints: [ThrowHint] = []

    init(game: G.Type, mode: GameMode, participants: [Participant], log: MoveLog<G>, transport: (any TurnTransport)?) {
        precondition(participants.count == G.seatCount)
        self.mode = mode
        self.participants = participants
        self.log = log
        self.transport = transport
    }

    /// 온라인이면 내 좌석, 로컬이면 지금 둘 좌석.
    var localSeat: Int? {
        if transport == nil { return G.currentSeat(state) }
        return participants.firstIndex(where: \.isHuman)
    }

    var isLocalTurn: Bool {
        guard !isReplaying, let seat = G.currentSeat(state), let mine = localSeat else { return false }
        return seat == mine
    }

    /// 수를 둔다. 내 차례가 아니거나 규칙에 어긋나면 거짓.
    @discardableResult
    func play(_ move: G.Move, hint: ThrowHint? = nil) async -> Bool {
        guard isLocalTurn, G.canApply(move, to: state) else { return false }
        if let hint { hints.append(ThrowHint(event: log.moves.count, trajectory: hint.trajectory, direction: hint.direction, yaws: hint.yaws)) }
        log.append(move)
        onLogChanged?(outcome == nil ? try? log.encoded() : nil)
        await publish()
        return true
    }

    func encodedLog() throws -> Data { try log.encoded() }

    private func publish() async {
        guard let transport else { return }
        do {
            let finished = outcome != nil
            var winner: Int? = nil
            if case .win(let seat) = outcome { winner = seat }
            try await transport.publish(TurnPayload(log: try log.encoded(), eventCount: log.moves.count, hints: hints,
                                                    turnSeat: G.currentSeat(state), winnerSeat: winner, finished: finished))
            lastTransportError = nil
        } catch {
            lastTransportError = "서버에 보내지 못해 다시 시도하는 중이다"
        }
    }

    func startListening() {
        guard let transport, listenTask == nil else { return }
        listenTask = Task { [weak self] in
            for await update in transport.incoming {
                guard let self else { return }
                let previous = replayTask
                replayTask = Task { @MainActor in
                    await previous?.value
                    await self.replay(update)
                }
            }
        }
        let remoteID = participants.compactMap { if case .remote(let id, _) = $0 { id } else { nil } }.first
        presenceTask = Task { [weak self] in
            for await present in transport.presence {
                self?.opponentPresent = remoteID.map { present.contains($0) } ?? !present.isEmpty
            }
        }
        connectionTask = Task { [weak self] in
            for await connected in transport.connection { self?.isConnected = connected }
        }
    }

    func resync() async { await transport?.refresh() }

    /// 상대 로그에서 내가 모르는 수만 검증하며 하나씩 재생한다.
    private func replay(_ update: RemoteUpdate) async {
        for hint in update.hints where !hints.contains(where: { $0.event == hint.event }) { hints.append(hint) }
        guard let theirs = try? MoveLog<G>.decoded(from: update.log) else {
            lastTransportError = "상대의 기록을 읽을 수 없다"
            return
        }
        let mine = log.moves
        guard theirs.moves.count > mine.count, Array(theirs.moves.prefix(mine.count)) == mine else {
            if theirs.moves.count > mine.count { lastTransportError = "상대의 기록이 내 기록과 어긋난다" }
            return
        }
        isReplaying = true
        defer { isReplaying = false }
        for (offset, move) in theirs.moves.dropFirst(mine.count).enumerated() {
            // 상대가 보낸 수는 상대 좌석의 것이어야 한다. 내 좌석 차례의 수가 오면 조작이다.
            guard let seat = G.currentSeat(state), seat != localSeat, G.canApply(move, to: state) else {
                lastTransportError = "상대가 보낸 수가 규칙에 맞지 않는다"
                return
            }
            let hint = hints.first { $0.event == mine.count + offset }
            await onRemoteMove?(move, hint)
            log.append(move)
            lastRemoteMove = RemoteMove(seat: seat, move: move)
        }
        lastTransportError = nil
        onLogChanged?(outcome == nil ? try? log.encoded() : nil)
    }

    /// 테스트용: 도착한 로그를 전부 재생할 때까지 기다린다(최대 2초).
    func waitForIncoming() async {
        let before = log.moves.count
        let deadline = ContinuousClock.now + .seconds(2)
        while replayTask == nil || log.moves.count == before {
            if ContinuousClock.now > deadline || lastTransportError != nil { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        await replayTask?.value
    }
}
```
`ThrowHint`의 `event`는 이 게임에서 "몇 번째 수"다. `hint` 인자의 `event`는 무시하고 `log.moves.count`로 바꿔 넣는다.

- [ ] **Step 5: 통과 확인** — `-only-testing:YachtDiceTests/OnlineMatchTests -only-testing:YachtDiceTests/MatchStoreTests`. `조작_거부`에서 두 수 연속 로그의 두 번째 수는 좌석 0 차례(내 좌석 = B의 상대… B 기준 localSeat = 1, 8,8은 좌석 1 차례라 `seat != localSeat`가 거짓) → 첫 수(8,8)부터 거부되어 `moves.count == 1`이어야 한다. 아니면 검증 순서를 살핀다.

- [ ] **Step 6: 커밋** — `git add -A && git commit -m "feat(game): 게임에 무관한 OnlineMatch 세션과 v3 기록 형식을 더한다"`

---

### Task 5: 게임 허브, 게임별 메뉴, 오목 매치 열기

**Files:**
- Create: `App/Views/HubScreen.swift`, `App/Games/GameCatalog.swift`
- Modify: `App/AppContainer.swift`, `App/YachtDiceApp.swift`, `App/Views/MenuScreen.swift`, `App/Views/OnlineMenu.swift`, `App/Views/GameScreen.swift:171`
- Test: `Tests/YachtDiceTests/AppContainerTests.swift`, `Tests/YachtDiceTests/OnlineMatchOpenTests.swift`, `Tests/YachtDiceUITests/MenuUITests.swift`, `FullGameUITests.swift`, `AccessibilityUITests.swift`, `LaunchUITests.swift`

**Interfaces:**
- Consumes: Task 4 `OnlineMatch<G>`, `MatchRecord(game:mode:participants:moveLog:)`; Task 3 `MatchRow.game`, `SupabaseService.createRoom(name:game:player:)`.
- Produces:
```swift
enum GameID: String, CaseIterable { case yacht, omok, cuppong, alkkagi; var title: String; var subtitle: String; var icon: String; var isAvailable: Bool /* yacht, omok만 참 */ }
// AppContainer
enum Status { case hub; case menu(GameID); case playing(GameSession); case playingOmok(OnlineMatch<Omok>); case failed(String) }
func showMenu(_ game: GameID); func returnToHub(); func returnToMenu()  // playing → menu(그 게임)
func startOmokLocal(names: [String]); func resumeSavedGame()
@discardableResult func openSupabaseMatch(_ row: MatchRow) -> Bool   // row.game으로 갈래
var currentGame: GameID?
```
  식별자: 허브 타일 `hub.<game>`(예 `hub.yacht`, `hub.omok`), 허브 전적 카드 `hub.records`, 게임 메뉴 뒤로가기 `menu.back`, 오목 메뉴 `menu.omok.local`, `menu.omok.online`, 오목 로컬 시작 `menu.omok.local.start`. 요트 메뉴의 기존 식별자(`menu.solo`, `menu.bot`, `menu.local`, `menu.online`, `menu.resume`, `menu.settings`)는 그대로다.

- [ ] **Step 1: 실패하는 단위 테스트**

`Tests/YachtDiceTests/AppContainerTests.swift`에 더한다(기존 `case .menu`를 기대하는 테스트는 `.hub`로 바꾼다 — 저장된 판이 없으면 허브에서 시작한다. `resumeSavedGame` 테스트는 허브에서 이어하기가 열리므로 그대로 `.playing`을 기대한다):
```swift
    @Test("허브에서 게임을 고르면 그 게임의 메뉴가 열리고 뒤로 가면 허브다")
    func 허브_메뉴() throws {
        let (container, dir) = try makeContainer()
        defer { try? FileManager.default.removeItem(at: dir) }
        guard case .hub = container.status else { Issue.record("허브가 아니다"); return }
        container.showMenu(.omok)
        guard case .menu(.omok) = container.status else { Issue.record("오목 메뉴가 아니다"); return }
        container.returnToHub()
        guard case .hub = container.status else { Issue.record("허브로 돌아오지 않았다"); return }
    }

    @Test("오목 로컬 2인을 시작하면 OnlineMatch가 만들어지고 수를 두면 저장된다")
    func 오목_로컬() async throws {
        let (container, dir) = try makeContainer()
        defer { try? FileManager.default.removeItem(at: dir) }
        container.startOmokLocal(names: ["갑", "을"])
        guard case .playingOmok(let match) = container.status else { Issue.record("오목이 아니다"); return }
        #expect(await match.play(Omok.Move(x: 7, y: 7)))
        let saved = try #require(MatchStore(directory: dir).load())
        #expect(saved.game == "omok" && saved.mode == .passAndPlay(names: ["갑", "을"]))
        container.returnToMenu()
        guard case .menu(.omok) = container.status else { Issue.record("오목 메뉴가 아니다"); return }
        container.resumeSavedGame()
        guard case .playingOmok(let resumed) = container.status else { Issue.record("이어하기 실패"); return }
        #expect(resumed.state.stone(x: 7, y: 7) == 1)
    }
```
`OnlineMatchOpenTests.swift`에 더한다:
```swift
    @Test("오목 행을 열면 OnlineMatch<Omok>가 되고 내 좌석이 맞는다")
    func 오목_행_열기() throws {
        let (container, dir) = try makeContainer()
        defer { try? FileManager.default.removeItem(at: dir) }
        let me = UUID(), them = UUID()
        var log = MoveLog<Omok>(); _ = log.append(Omok.Move(x: 7, y: 7))
        let row = MatchRow(id: UUID(), code: "111111", hostUid: them, guestUid: me, hostName: "A", guestName: "B",
                           log: try log.encoded(), eventCount: 1, status: "playing", totals: nil, game: "omok", turnSeat: 1)
        #expect(container.openSupabaseMatch(row, localUid: me, transport: InMemoryTurnTransport.pair().0))
        guard case .playingOmok(let match) = container.status else { Issue.record("오목이 아니다: \(container.status)"); return }
        #expect(match.localSeat == 1 && match.isLocalTurn && match.state.stone(x: 7, y: 7) == 1)
    }
```
(`openSupabaseMatch(_:localUid:transport:)`는 테스트용 오버로드다 — 아래 Step 3.)

- [ ] **Step 2: 실패 확인** — `GameID`, `showMenu` 없음.

- [ ] **Step 3: GameCatalog와 AppContainer**

`App/Games/GameCatalog.swift`:
```swift
import Foundation

/// 허브에 보이는 게임 넷. rawValue는 서버 `matches.game`과 같다.
enum GameID: String, CaseIterable, Sendable {
    case yacht, omok, cuppong, alkkagi

    var title: String {
        switch self { case .yacht: "요트 다이스"; case .omok: "오목"; case .cuppong: "컵퐁"; case .alkkagi: "알까기" }
    }
    var subtitle: String {
        switch self {
        case .yacht: "주사위 다섯, 12턴"
        case .omok: "다섯을 먼저 잇는다"
        case .cuppong: "컵을 먼저 비운다"
        case .alkkagi: "돌을 튕겨 밀어낸다"
        }
    }
    var icon: String {
        switch self { case .yacht: "dice"; case .omok: "circle.grid.3x3"; case .cuppong: "cup.and.saucer"; case .alkkagi: "circle.circle" }
    }
    /// 아직 만들지 않은 게임은 타일이 흐리고 "준비 중"이다.
    var isAvailable: Bool { self == .yacht || self == .omok }
}
```

`App/AppContainer.swift`:
- `Status`를 `case hub, menu(GameID), playing(GameSession), playingOmok(OnlineMatch<Omok>), failed(String)`으로. `import GameCore`.
- `init`: `status = .hub`(실패 시 `.failed`). `savedRecord = store.load()`는 그대로.
- `var currentGame: GameID? { switch status { case .menu(let g): g; case .playing: .yacht; case .playingOmok: .omok; default: nil } }`
- `func showMenu(_ game: GameID) { savedRecord = store.load(); status = .menu(game) }`, `func returnToHub() { savedRecord = store.load(); status = .hub }`, `returnToMenu()`는 `status = .menu(currentGame ?? .yacht)`.
- `startGame(mode:)`·`resumeSavedGame`: 요트는 기존대로 `launch(record)`; `resumeSavedGame`은 `record.game == "omok"`이면 `launchOmok(record, transport: nil)`.
- 오목:
```swift
    func startOmokLocal(names: [String]) {
        try? store.clear()
        savedRecord = nil
        let participants: [Participant] = names.map { .human(name: $0) }
        let record = MatchRecord(game: Omok.id, mode: .passAndPlay(names: names), participants: participants,
                                 moveLog: (try? MoveLog<Omok>().encoded()) ?? Data())
        launchOmok(record, transport: nil)
    }

    private func launchOmok(_ record: MatchRecord, transport: (any TurnTransport)?) {
        guard let data = record.moveLog, let log = try? MoveLog<Omok>.decoded(from: data) else {
            onlineError = "오목 기록을 읽을 수 없다"
            return
        }
        let match = OnlineMatch(game: Omok.self, mode: record.mode, participants: record.participants, log: log, transport: transport)
        if transport == nil {
            let store = store
            var saved = record
            match.onLogChanged = { data in
                if let data { saved.moveLog = data; try? store.save(saved) } else { try? store.clear() }
            }
        } else {
            match.startListening()
        }
        status = .playingOmok(match)
    }
```
- `openSupabaseMatch(_ row: MatchRow) -> Bool`은 `guard let uid = supabase.uid ...` 뒤 `openSupabaseMatch(row, localUid: uid, transport: SupabaseTurnTransport(client: supabase.client, matchID: row.id))`를 부르고, 새 오버로드:
```swift
    /// 테스트가 전송을 바꿔 끼울 수 있는 핵심. `row.game`으로 요트와 오목을 가른다.
    @discardableResult
    func openSupabaseMatch(_ row: MatchRow, localUid: UUID, transport: any TurnTransport) -> Bool {
        guard row.guestUid != nil else { onlineError = "상대가 아직 들어오지 않았다"; return false }
        switch GameID(rawValue: row.game) {
        case .yacht:
            return openOnlineMatch(matchID: row.id.uuidString, localID: localUid.uuidString,
                                   players: row.seats(localUid: localUid), matchData: row.log, transport: transport)
        case .omok:
            if case .playingOmok(let match) = status, match.mode == .online(matchID: row.id.uuidString) { return true }
            let participants = seatParticipants(localID: localUid.uuidString, players: row.seats(localUid: localUid))
            guard participants.contains(where: \.isHuman) else { onlineError = "이 매치에 내 자리가 없습니다"; return false }
            onlineError = nil
            launchOmok(MatchRecord(game: Omok.id, mode: .online(matchID: row.id.uuidString), participants: participants, moveLog: row.log),
                       transport: transport)
            return true
        default:
            onlineError = "아직 지원하지 않는 게임이다: \(row.game)"
            return false
        }
    }
```
- `PushRegistration.shared.currentMatchID` 클로저는 `.playingOmok(let m)`도 본다(`case .online(let id) = m.mode`).

- [ ] **Step 4: 허브·메뉴 화면**

`App/Views/HubScreen.swift`:
```swift
import SwiftUI

/// 시작 화면. 게임 타일 넷과 진행 중인 판·전적 카드.
struct HubScreen: View {
    let container: AppContainer
    @Environment(\.theme) private var theme
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                WoodBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(spacing: 6) {
                            Text("게임 테이블").font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(theme.ivory)
                            Text("GAME TABLE").font(.caption.weight(.semibold)).tracking(4).foregroundStyle(theme.brass)
                        }
                        .padding(.top, 8).padding(.bottom, 6)
                        .accessibilityElement(children: .combine)

                        if let saved = container.savedRecord, let game = GameID(rawValue: saved.game) {
                            ModeCard(icon: "bookmark.fill", title: "이어하기 · \(game.title)", subtitle: saved.mode.title,
                                     identifier: "hub.resume") { container.resumeSavedGame() }
                        }

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(GameID.allCases, id: \.self) { game in
                                Button { container.showMenu(game) } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: game.icon).font(.system(size: 30)).foregroundStyle(theme.brass)
                                        Text(game.title).font(.system(.headline, design: .serif)).foregroundStyle(theme.ink)
                                        Text(game.isAvailable ? game.subtitle : "준비 중").font(.caption).foregroundStyle(theme.inkSecondary)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                                    .paperCard(padding: 12)
                                    .opacity(game.isAvailable ? 1 : 0.55)
                                }
                                .buttonStyle(.plain)
                                .disabled(!game.isAvailable)
                                .accessibilityIdentifier("hub.\(game.rawValue)")
                                .accessibilityLabel("\(game.title)\(game.isAvailable ? "" : ", 준비 중")")
                            }
                        }

                        RecordsCard(container: container)   // Task 7이 만든다. 그 전에는 빈 카드 자리 표시자 뷰를 둔다(아래 참고)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape").foregroundStyle(theme.ivory) }
                        .accessibilityIdentifier("menu.settings").accessibilityLabel("설정")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) { SettingsSheet() }
        }
    }
}
```
이 Task에서는 `RecordsCard`를 같은 파일에 임시로 둔다: `struct RecordsCard: View { let container: AppContainer; var body: some View { Text("전적은 곧 보인다").font(.caption).paperCard(padding: 14).accessibilityIdentifier("hub.records") } }`. Task 7이 채운다.

`App/Views/MenuScreen.swift`를 요트 메뉴로 다듬는다: `titleLockup`은 그대로, 툴바에 뒤로가기(`.topBarLeading`, `chevron.left`, `container.returnToHub()`, 식별자 `menu.back`)를 두고 설정 버튼은 허브로 옮겼으므로 지운다(`SettingsSheet`는 허브가 연다; 기존 UI 테스트 `test_설정_시트가_열린다`는 허브에서 누르게 된다). 온라인 카드는 `OnlineMenu(container: container, game: .yacht)`.

`App/Views/OmokMenu.swift`(새 파일, `App/Games/Omok/OmokMenu.swift`):
```swift
import SwiftUI

struct OmokMenu: View {
    let container: AppContainer
    @Environment(\.theme) private var theme
    @State private var names = ["흑", "백"]
    @State private var showingLocalSetup = false
    @State private var showingOnline = false

    var body: some View {
        NavigationStack {
            ZStack {
                WoodBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(spacing: 6) {
                            Text("오목").font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(theme.ivory)
                            Text("15×15 · 다섯을 먼저 잇는다").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(theme.brass)
                        }.padding(.top, 8).padding(.bottom, 10)
                        if let saved = container.savedRecord, saved.game == "omok" {
                            ModeCard(icon: "bookmark.fill", title: "이어하기", subtitle: saved.mode.title, identifier: "menu.resume") {
                                container.resumeSavedGame()
                            }
                        }
                        ModeCard(icon: "person.2", title: "로컬 2인", subtitle: "한 기기에서 번갈아 둔다", identifier: "menu.omok.local") {
                            showingLocalSetup = true
                        }
                        ModeCard(icon: "network", title: "온라인 대전", subtitle: "방 코드로 친구와 겨룬다", identifier: "menu.omok.online") {
                            showingOnline = true
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { container.returnToHub() } label: { Image(systemName: "chevron.left").foregroundStyle(theme.ivory) }
                        .accessibilityIdentifier("menu.back").accessibilityLabel("허브로")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingOnline) { OnlineMenu(container: container, game: .omok) }
            .sheet(isPresented: $showingLocalSetup) {
                NavigationStack {
                    Form {
                        TextField("흑", text: $names[0]).accessibilityIdentifier("menu.omok.name.0")
                        TextField("백", text: $names[1]).accessibilityIdentifier("menu.omok.name.1")
                    }
                    .navigationTitle("로컬 2인")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("시작") {
                                showingLocalSetup = false
                                container.startOmokLocal(names: names.map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? "플레이어" : $0 })
                            }.accessibilityIdentifier("menu.omok.local.start")
                        }
                        ToolbarItem(placement: .cancellationAction) { Button("취소") { showingLocalSetup = false } }
                    }
                }
            }
        }
    }
}
```

`App/Views/OnlineMenu.swift`: `let game: GameID`를 더하고(`init(container:game:)`), `createRoom`이 `service.createRoom(name: trimmedName, game: game.rawValue, player: container.gameCenter.playerID)`를 부른다(`playerID`는 Task 7이 채우는 `String?`; 이 Task에서는 `GameCenterService`에 `var playerID: String? { nil }`을 임시로 둔다). `joinRoom`도 `player:`를 넘긴다. 진행 중 목록의 행에는 `GameID(rawValue: row.game)?.title ?? row.game`을 상대 이름 앞에 작은 글씨로 보인다. 제목은 `"온라인 대전 · \(game.title)"`.

`App/YachtDiceApp.swift`의 `switch`: `.hub → HubScreen`, `.menu(.yacht) → MenuScreen`, `.menu(.omok) → OmokMenu`, `.menu → HubScreen`(준비 중 게임은 허브가 막는다), `.playing → GameScreen`, `.playingOmok(let match) → OmokScreen(match: match, onReturn: { container.returnToMenu() })`. `OmokScreen`은 Task 6이 만들므로 이 Task에서는 `App/Games/Omok/OmokScreen.swift`에 최소 화면을 둔다: 상단에 `PlayerStrip`은 `GameSession`에 묶여 있어 못 쓰므로 `Text("오목")`와 "메뉴로" 버튼(`header.menu`)만 둔 자리 표시자이며 Task 6이 교체한다.

- [ ] **Step 5: UI 테스트 갱신**

모든 UI 테스트에서 요트 메뉴에 들어가기 전에 허브 타일을 누른다. 공통 도우미를 `Tests/YachtDiceUITests/FullGameUITests.swift`의 `XCUIElement` 확장 옆에 둔다:
```swift
extension XCUIApplication {
    /// 허브에서 요트 다이스 메뉴로 들어간다.
    @MainActor
    func openYachtMenu() {
        let tile = buttons["hub.yacht"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "허브에 요트 타일이 없다")
        tile.tap()
    }
}
```
`MenuUITests`·`FullGameUITests`·`AccessibilityUITests`의 각 테스트에서 `app.launch()` 뒤에 `app.openYachtMenu()`를 넣는다. `test_메뉴로_돌아가면_이어하기가_있다`는 게임에서 `header.menu`를 누르면 요트 메뉴(`.menu(.yacht)`)로 오므로 `menu.resume`을 그대로 기대한다. `test_설정_시트가_열린다`는 허브에서 `menu.settings`를 누르므로 `openYachtMenu()`를 넣지 않는다. `LaunchUITests`는 `hub.yacht`가 존재하는지로 바꾼다. 새 테스트를 `MenuUITests`에 더한다:
```swift
    func test_허브에서_오목_메뉴가_열리고_돌아온다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch", "-noPush"]
        app.launch()
        let omok = app.buttons["hub.omok"]
        XCTAssertTrue(omok.waitForExistence(timeout: 10))
        omok.tap()
        XCTAssertTrue(app.buttons["menu.omok.local"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["hub.cuppong"].isEnabled == true && app.buttons["hub.cuppong"].exists, "준비 중 타일이 눌린다")
        app.buttons["menu.back"].tap()
        XCTAssertTrue(app.buttons["hub.yacht"].waitForExistence(timeout: 5))
    }
```

- [ ] **Step 6: 단위·UI 테스트 통과** — 단위 전체와 `-only-testing:YachtDiceUITests`.

- [ ] **Step 7: 커밋** — `git add -A && git commit -m "feat(hub): 게임 허브와 게임별 메뉴를 두고 오목 매치를 연다"`

---

### Task 6: 오목 화면

**Files:**
- Create: `App/Games/Omok/OmokBoardView.swift`, `App/Games/Omok/OmokScreen.swift`(Task 5의 자리 표시자를 교체)
- Test: `Tests/YachtDiceTests/OmokBoardTests.swift`, `Tests/YachtDiceUITests/OmokUITests.swift`

**Interfaces:**
- Consumes: Task 4 `OnlineMatch<Omok>`(`state`, `play`, `isLocalTurn`, `onRemoteMove`, `lastRemoteMove`, `outcome`, `opponentPresent`, `isConnected`, `lastTransportError`, `participants`, `localSeat`).
- Produces: `struct OmokBoardView: View { let state: Omok.State; let preview: Omok.Move?; let highlight: Omok.Move?; let animating: Omok.Move?; var onTap: (Omok.Move) -> Void }`, `enum OmokGeometry { static func move(at point: CGPoint, in size: CGSize) -> Omok.Move?; static func point(of move: Omok.Move, in size: CGSize) -> CGPoint }`.

- [ ] **Step 1: 실패하는 기하 테스트**

`Tests/YachtDiceTests/OmokBoardTests.swift`:
```swift
import Testing
import Foundation
import GameCore
@testable import YachtDice

@Suite("오목 판 기하")
struct OmokBoardTests {
    @Test("교차점 좌표와 탭 좌표가 서로 맞는다")
    func 왕복() {
        let size = CGSize(width: 300, height: 300)
        for (x, y) in [(0, 0), (14, 14), (7, 7), (3, 11)] {
            let p = OmokGeometry.point(of: Omok.Move(x: x, y: y), in: size)
            #expect(OmokGeometry.move(at: p, in: size) == Omok.Move(x: x, y: y))
        }
        // 교차점 사이 중간은 가까운 쪽으로
        let between = OmokGeometry.point(of: Omok.Move(x: 2, y: 2), in: size)
        #expect(OmokGeometry.move(at: CGPoint(x: between.x + 4, y: between.y - 4), in: size) == Omok.Move(x: 2, y: 2))
        // 판 밖은 nil
        #expect(OmokGeometry.move(at: CGPoint(x: -20, y: 10), in: size) == nil)
    }
}
```

- [ ] **Step 2: 실패 확인** — `OmokGeometry` 없음.

- [ ] **Step 3: 판 뷰**

`App/Games/Omok/OmokBoardView.swift`:
```swift
import SwiftUI
import GameCore

/// 판 위 교차점 ↔ 화면 좌표. 판은 정사각형이고 바깥 여백은 칸 하나의 절반이다.
enum OmokGeometry {
    static let n = Omok.size
    static func cell(_ size: CGSize) -> CGFloat { min(size.width, size.height) / CGFloat(n) }
    static func point(of move: Omok.Move, in size: CGSize) -> CGPoint {
        let c = cell(size)
        return CGPoint(x: c * (CGFloat(move.x) + 0.5), y: c * (CGFloat(move.y) + 0.5))
    }
    static func move(at point: CGPoint, in size: CGSize) -> Omok.Move? {
        let c = cell(size)
        let x = Int((point.x / c).rounded(.down)), y = Int((point.y / c).rounded(.down))
        guard (0..<n).contains(x), (0..<n).contains(y) else { return nil }
        return Omok.Move(x: x, y: y)
    }
}

/// 나무 판·격자·화점·돌·미리보기·마지막 수 표식. 상태만 받아 그린다.
struct OmokBoardView: View {
    let state: Omok.State
    var preview: Omok.Move?
    var previewSeat: Int = 0
    var animating: Omok.Move?
    var onTap: (Omok.Move) -> Void = { _ in }
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: min(proxy.size.width, proxy.size.height), height: min(proxy.size.width, proxy.size.height))
            Canvas { context, _ in
                let c = OmokGeometry.cell(size)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.86, green: 0.70, blue: 0.44)))
                var grid = Path()
                for i in 0..<OmokGeometry.n {
                    let p = c * (CGFloat(i) + 0.5)
                    grid.move(to: CGPoint(x: c / 2, y: p)); grid.addLine(to: CGPoint(x: size.width - c / 2, y: p))
                    grid.move(to: CGPoint(x: p, y: c / 2)); grid.addLine(to: CGPoint(x: p, y: size.height - c / 2))
                }
                context.stroke(grid, with: .color(.black.opacity(0.65)), lineWidth: 1)
                for (x, y) in [(3, 3), (3, 11), (11, 3), (11, 11), (7, 7)] {
                    let p = OmokGeometry.point(of: Omok.Move(x: x, y: y), in: size)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(.black.opacity(0.7)))
                }
                for y in 0..<OmokGeometry.n {
                    for x in 0..<OmokGeometry.n {
                        let stone = state.stone(x: x, y: y)
                        guard stone != 0 else { continue }
                        let move = Omok.Move(x: x, y: y)
                        let scale: CGFloat = animating == move ? 1.25 : 1
                        drawStone(context, at: OmokGeometry.point(of: move, in: size), radius: c * 0.45 * scale, black: stone == 1, alpha: 1)
                    }
                }
                if let preview, state.stone(x: preview.x, y: preview.y) == 0 {
                    drawStone(context, at: OmokGeometry.point(of: preview, in: size), radius: c * 0.45, black: previewSeat == 0, alpha: 0.45)
                }
                if let last = state.lastMove {
                    let p = OmokGeometry.point(of: last, in: size)
                    context.stroke(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                                   with: .color(state.stone(x: last.x, y: last.y) == 1 ? .white : .black), lineWidth: 1.5)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture { location in
                if let move = OmokGeometry.move(at: location, in: size) { onTap(move) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityIdentifier("omok.board")
        .accessibilityLabel("오목판, 흑 \(state.cells.filter { $0 == 1 }.count)개, 백 \(state.cells.filter { $0 == 2 }.count)개")
    }

    private func drawStone(_ context: GraphicsContext, at p: CGPoint, radius: CGFloat, black: Bool, alpha: Double) {
        let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
        let shading: GraphicsContext.Shading = .radialGradient(
            Gradient(colors: black ? [Color(white: 0.35), .black] : [.white, Color(white: 0.78)]),
            center: CGPoint(x: p.x - radius * 0.35, y: p.y - radius * 0.35), startRadius: 0, endRadius: radius * 1.4)
        context.opacity = alpha
        context.fill(Path(ellipseIn: rect.offsetBy(dx: 1, dy: 2)), with: .color(.black.opacity(0.25 * alpha)))
        context.fill(Path(ellipseIn: rect), with: shading)
        context.opacity = 1
    }
}
```
(`GraphicsContext`는 값 형식이라 `drawStone`에서 `var context = context`로 받아 `opacity`를 바꾼다.)

- [ ] **Step 4: 화면**

`App/Games/Omok/OmokScreen.swift`:
```swift
import SwiftUI
import GameCore

struct OmokScreen: View {
    let match: OnlineMatch<Omok>
    var onReturn: () -> Void = {}
    @Environment(\.theme) private var theme
    @State private var preview: Omok.Move?
    @State private var animating: Omok.Move?
    @State private var turnBanner: String?
    @State private var moveToast: String?
    @State private var showDisconnected = false
    @State private var disconnectTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    private var seatNames: [String] { match.participants.map(\.displayName) }

    var body: some View {
        ZStack {
            WoodBackground()
            VStack(spacing: 12) {
                header
                seats
                OmokBoardView(state: match.state, preview: preview, previewSeat: match.localSeat ?? 0, animating: animating) { move in
                    guard match.isLocalTurn, Omok.canApply(move, to: match.state) else { return }
                    preview = move
                    Haptics.shared.play(.selection)
                }
                .padding(.horizontal, 12)
                actionBar
                Spacer(minLength: 0)
            }
            .overlay(alignment: .top) {
                if showDisconnected {
                    Label("연결 끊김 — 재연결 중", systemImage: "wifi.slash").font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6).background(theme.ink.opacity(0.85), in: Capsule())
                        .foregroundStyle(theme.paper).padding(.top, 118).accessibilityIdentifier("online.connection")
                }
            }
            .overlay(alignment: .top) {
                if let error = match.lastTransportError {
                    Text(error).font(.caption).padding(8).background(.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white).padding(.top, 48).accessibilityIdentifier("online.error")
                }
            }
            .overlay { if let turnBanner { TurnBanner(text: turnBanner).transition(.scale(scale: 0.9).combined(with: .opacity)) } }
            .overlay(alignment: .top) {
                if let moveToast { ScoreToast(text: moveToast).padding(.top, 118).transition(.move(edge: .top).combined(with: .opacity)) }
            }
        }
        .task { match.onRemoteMove = { move, _ in await replayRemote(move) } }
        .onChange(of: match.log.moves.count, initial: true) { _, _ in
            preview = nil
            if match.outcome == nil, let seat = Omok.currentSeat(match.state), match.mode.isOnline || true {
                showBanner(match.isLocalTurn ? "내 차례" : "\(seatNames[seat]) 차례")
            }
        }
        .onChange(of: match.lastRemoteMove?.id) { _, _ in
            guard let remote = match.lastRemoteMove else { return }
            showToast("\(seatNames[remote.seat]): \(remote.move.x + 1)열 \(remote.move.y + 1)행")
        }
        .onChange(of: match.isConnected, initial: true) { _, connected in
            disconnectTask?.cancel()
            if connected { withAnimation { showDisconnected = false } }
            else { disconnectTask = Task { try? await Task.sleep(for: .seconds(3)); guard !Task.isCancelled else { return }; withAnimation { showDisconnected = true } } }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await match.resync() } } }
    }

    private var header: some View {
        HStack {
            Button(action: onReturn) { Image(systemName: "chevron.left").foregroundStyle(theme.ivory) }
                .accessibilityIdentifier("header.menu").accessibilityLabel("메뉴로")
            Spacer()
            Text("오목").font(.system(.title3, design: .serif, weight: .semibold)).foregroundStyle(theme.ivory)
            Spacer()
            Text("\(match.log.moves.count)수").font(.caption).monospacedDigit().foregroundStyle(theme.brass).accessibilityIdentifier("header.status")
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    /// 명패 둘. 현재 차례는 황동, 원격 상대는 접속 점.
    private var seats: some View {
        HStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { seat in
                let current = Omok.currentSeat(match.state) == seat
                HStack(spacing: 6) {
                    Circle().fill(seat == 0 ? .black : .white).frame(width: 12, height: 12).overlay(Circle().stroke(.black.opacity(0.4)))
                    if case .remote = match.participants[seat] {
                        Circle().fill(match.opponentPresent ? Color.green : theme.inkSecondary.opacity(0.5)).frame(width: 7, height: 7)
                            .accessibilityIdentifier("players.presence.\(seat)")
                    }
                    Text(seatNames[seat]).font(.caption).lineLimit(1)
                }
                .foregroundStyle(current ? theme.brassInk : theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(current ? theme.brass : theme.paper))
                .accessibilityIdentifier("players.seat.\(seat)")
                .accessibilityLabel("\(seatNames[seat])\(current ? ", 현재 차례" : "")")
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var actionBar: some View {
        if let outcome = match.outcome {
            VStack(spacing: 10) {
                Text(resultText(outcome)).font(.system(.title2, design: .serif, weight: .semibold)).foregroundStyle(theme.ink)
                    .accessibilityIdentifier("omok.result")
                Button(action: onReturn) { Label("메뉴로", systemImage: "chevron.left").frame(maxWidth: .infinity).brassButton(prominent: true) }
                    .buttonStyle(.plain).accessibilityIdentifier("omok.back")
            }
            .paperCard(padding: 14).padding(.horizontal, 16)
        } else {
            Button {
                guard let move = preview else { return }
                Task {
                    if await match.play(move) {
                        SoundPlayer.shared.play(SoundSynth.stamp(), key: "stamp")
                        Haptics.shared.play(.impactRigid)
                    }
                }
            } label: {
                Text(preview == nil ? "교차점을 탭해 자리를 고른다" : "놓기").frame(maxWidth: .infinity)
                    .brassButton(prominent: preview != nil)
            }
            .buttonStyle(.plain)
            .disabled(preview == nil || !match.isLocalTurn)
            .accessibilityIdentifier("omok.place")
            .padding(.horizontal, 16)
        }
    }

    private func resultText(_ outcome: Outcome) -> String {
        switch outcome {
        case .draw: "무승부"
        case .win(let seat):
            if match.mode.isOnline { match.localSeat == seat ? "승리!" : "패배" } else { "\(seatNames[seat]) 승리" }
        }
    }

    private func replayRemote(_ move: Omok.Move) async {
        withAnimation(.easeOut(duration: 0.25)) { animating = move }
        SoundPlayer.shared.play(SoundSynth.stamp(), key: "stamp")
        try? await Task.sleep(for: .milliseconds(250))
        animating = nil
    }

    private func showBanner(_ text: String) {
        withAnimation(.spring(duration: 0.3)) { turnBanner = text }
        Task { try? await Task.sleep(for: .seconds(1.2)); withAnimation(.easeOut(duration: 0.3)) { if turnBanner == text { turnBanner = nil } } }
    }

    private func showToast(_ text: String) {
        withAnimation { moveToast = text }
        Task { try? await Task.sleep(for: .seconds(2)); withAnimation { if moveToast == text { moveToast = nil } } }
    }
}
```
`animating`은 `onRemoteMove`가 로그에 더해지기 전에 불리므로 그 자리에 돌이 아직 없다 — `OmokBoardView`에 `animating` 돌을 `state`와 별개로 그리도록 `if let animating, state.stone(...) == 0 { drawStone(... black: Omok.currentSeat(state) == 0, radius * 1.25) }`를 더한다. `GameMode`에 `var isOnline: Bool { if case .online = self { true } else { false } }`를 더한다(`App/Game/Participant.swift`). `.onChange(of: match.log.moves.count)`의 `match.mode.isOnline || true`는 지우고 항상 배너를 보인다.

- [ ] **Step 5: UI 테스트**

`Tests/YachtDiceUITests/OmokUITests.swift`:
```swift
import XCTest

final class OmokUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// 판의 교차점 (x, y)를 탭한다. 판은 정사각형이고 칸은 변/15다.
    @MainActor
    private func tap(_ app: XCUIApplication, x: Int, y: Int) {
        let board = app.otherElements["omok.board"].exists ? app.otherElements["omok.board"] : app.descendants(matching: .any)["omok.board"]
        let cell = board.frame.width / 15
        board.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: cell * (CGFloat(x) + 0.5), dy: cell * (CGFloat(y) + 0.5))).tap()
        let place = app.buttons["omok.place"]
        XCTAssertTrue(place.waitForExistence(timeout: 3))
        place.tap()
    }

    @MainActor
    func test_로컬_2인_다섯_수로_흑이_이긴다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch", "-noPush"]
        app.launch()
        app.buttons["hub.omok"].tap()
        app.buttons["menu.omok.local"].tap()
        XCTAssertTrue(app.buttons["menu.omok.local.start"].waitForExistence(timeout: 5))
        app.buttons["menu.omok.local.start"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["omok.board"].waitForExistence(timeout: 10))
        for (x, y) in [(0,0),(0,1),(1,0),(1,1),(2,0),(2,1),(3,0),(3,1),(4,0)] { tap(app, x: x, y: y) }
        let result = app.staticTexts["omok.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("승리"))
        app.buttons["omok.back"].tap()
        XCTAssertTrue(app.buttons["menu.omok.local"].waitForExistence(timeout: 5))
    }
}
```

- [ ] **Step 6: 통과 확인** — 단위(`OmokBoardTests`) + `-only-testing:YachtDiceUITests/OmokUITests`. 탭 좌표가 어긋나면 `omok.board`의 프레임이 정사각형인지(`aspectRatio`) 스크린샷으로 본다.

- [ ] **Step 7: 커밋** — `git add -A && git commit -m "feat(omok): 오목 판과 화면, 로컬 2인 완주"`

---

### Task 7: Game Center 신원·profiles·전적·리더보드

**Files:**
- Modify: `App/Online/GameCenterService.swift`(다시 쓴다), `App/Online/SupabaseService.swift`, `App/AppContainer.swift`, `App/Views/HubScreen.swift`, `App/Views/OnlineMenu.swift`, `App/YachtDice.entitlements`, `App/Game/OnlineMatch.swift`, `App/Game/GameSession.swift`
- Create: `App/Views/RecordsScreen.swift`, `App/Online/RecordsStore.swift`
- Test: `Tests/YachtDiceTests/GameCenterServiceTests.swift`, `Tests/YachtDiceTests/RecordsStoreTests.swift`

**Interfaces:**
- Consumes: Task 2 `profiles`, `records`, `matches.host_player/guest_player/winner_seat`; Task 5 `HubScreen.RecordsCard`, `OnlineMenu(game:)`.
- Produces:
```swift
@MainActor @Observable final class GameCenterService {
    enum AuthState: Equatable { case unknown, authenticated(playerID: String, name: String), unavailable(String) }
    private(set) var authState: AuthState
    var playerID: String?; var displayName: String?
    init(authenticator: any GameCenterAuthenticating = LiveAuthenticator())
    func authenticate() async
    func submit(wins: Int, game: GameID) async   // 리더보드 wins.<game>
    func presentLeaderboards()
}
protocol GameCenterAuthenticating: Sendable { func authenticate() async throws -> (playerID: String, name: String); func submitScore(_:leaderboardID:) async throws }
struct RecordRow: Decodable, Equatable { let player: String; let game: String; let wins: Int; let losses: Int; let draws: Int }
struct RecentMatch: Equatable { let id: UUID; let game: String; let opponent: String; let result: String /* 승·패·무 */; let finishedAt: Date }
@MainActor @Observable final class RecordsStore { init(service: SupabaseService, gameCenter: GameCenterService); private(set) var records: [RecordRow]; private(set) var recent: [RecentMatch]; func reload() async; static func summarize(rows: [MatchRow], me: String, myUid: UUID) -> [RecentMatch] }
```
  `SupabaseService.upsertProfile(player:name:)`, `SupabaseService.fetchRecords(player:)`, `SupabaseService.fetchFinished(limit:)`.

- [ ] **Step 1: 실패하는 테스트**

`Tests/YachtDiceTests/GameCenterServiceTests.swift`:
```swift
import Testing
@testable import YachtDice

@Suite("Game Center 신원")
@MainActor
struct GameCenterServiceTests {
    final class Fake: GameCenterAuthenticating, @unchecked Sendable {
        var result: Result<(playerID: String, name: String), any Error>
        var submitted: [(Int, String)] = []
        init(_ result: Result<(playerID: String, name: String), any Error>) { self.result = result }
        func authenticate() async throws -> (playerID: String, name: String) { try result.get() }
        func submitScore(_ score: Int, leaderboardID: String) async throws { submitted.append((score, leaderboardID)) }
    }
    struct Nope: Error {}

    @Test("인증되면 playerID와 이름이 생기고 리더보드에 제출한다")
    func 인증() async {
        let fake = Fake(.success((playerID: "G:42", name: "정헌")))
        let service = GameCenterService(authenticator: fake)
        await service.authenticate()
        #expect(service.authState == .authenticated(playerID: "G:42", name: "정헌"))
        #expect(service.playerID == "G:42" && service.displayName == "정헌")
        await service.submit(wins: 3, game: .omok)
        #expect(fake.submitted.map { $0.1 } == ["wins.omok"] && fake.submitted.first?.0 == 3)
    }

    @Test("인증에 실패하면 unavailable이고 제출은 조용히 건너뛴다")
    func 실패() async {
        let fake = Fake(.failure(Nope()))
        let service = GameCenterService(authenticator: fake)
        await service.authenticate()
        guard case .unavailable = service.authState else { Issue.record("unavailable이 아니다"); return }
        #expect(service.playerID == nil)
        await service.submit(wins: 1, game: .yacht)
        #expect(fake.submitted.isEmpty)
    }
}
```

`Tests/YachtDiceTests/RecordsStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import YachtDice

@Suite("전적 요약")
struct RecordsStoreTests {
    @Test("끝난 행에서 내 결과와 상대 이름을 뽑는다")
    func 요약() throws {
        let me = UUID(), them = UUID()
        func row(_ host: UUID, _ guest: UUID, hostName: String, guestName: String, winner: Int?, game: String, hostPlayer: String? = nil) -> MatchRow {
            MatchRow(id: UUID(), code: "000000", hostUid: host, guestUid: guest, hostName: hostName, guestName: guestName,
                     log: Data("{}".utf8), eventCount: 0, status: "finished", totals: nil, game: game,
                     hostPlayer: hostPlayer, guestPlayer: nil, winnerSeat: winner)
        }
        let rows = [
            row(me, them, hostName: "나", guestName: "상대", winner: 0, game: "omok"),
            row(them, me, hostName: "상대", guestName: "나", winner: 0, game: "yacht"),
            row(them, me, hostName: "상대", guestName: "나", winner: nil, game: "omok"),
            row(UUID(), me, hostName: "GC", guestName: "나", winner: 1, game: "omok", hostPlayer: "G:9"),
        ]
        let recent = RecordsStore.summarize(rows: rows, me: me.uuidString, myUid: me)
        #expect(recent.map(\.result) == ["승", "패", "무", "승"])
        #expect(recent.map(\.opponent) == ["상대", "상대", "상대", "GC"])
        #expect(recent.map(\.game) == ["omok", "yacht", "omok", "omok"])
    }
}
```

- [ ] **Step 2: 실패 확인** — `GameCenterAuthenticating`, `RecordsStore` 없음.

- [ ] **Step 3: GameCenterService 다시 쓰기**

`App/Online/GameCenterService.swift` 전체:
```swift
import Foundation
import GameKit
import Observation
import UIKit

/// GameKit 인증과 점수 제출. 테스트는 가짜를 끼운다.
protocol GameCenterAuthenticating: Sendable {
    func authenticate() async throws -> (playerID: String, name: String)
    func submitScore(_ score: Int, leaderboardID: String) async throws
}

/// 실제 GameKit. 로그인 창은 GameKit이 주는 뷰 컨트롤러를 최상단에 띄운다.
struct LiveAuthenticator: GameCenterAuthenticating {
    func authenticate() async throws -> (playerID: String, name: String) {
        let player = GKLocalPlayer.local
        if player.isAuthenticated { return (player.gamePlayerID, player.displayName) }
        return try await withCheckedThrowingContinuation { continuation in
            let done = Mutex(false)
            player.authenticateHandler = { viewController, error in
                let presented = UncheckedSendable(viewController)
                Task { @MainActor in
                    if let vc = presented.value {
                        Self.topViewController()?.present(vc, animated: true)
                        return   // 사용자가 창을 닫으면 핸들러가 다시 불린다
                    }
                    guard done.withLock({ let was = $0; $0 = true; return !was }) else { return }
                    if GKLocalPlayer.local.isAuthenticated {
                        continuation.resume(returning: (GKLocalPlayer.local.gamePlayerID, GKLocalPlayer.local.displayName))
                    } else {
                        continuation.resume(throwing: error ?? CocoaError(.userCancelled))
                    }
                }
            }
        }
    }

    func submitScore(_ score: Int, leaderboardID: String) async throws {
        try await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [leaderboardID])
    }

    @MainActor static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Game Center 신원. 로그인은 선택이라 실패해도 앱은 익명으로 돈다.
@MainActor
@Observable
final class GameCenterService {
    enum AuthState: Equatable {
        case unknown
        case authenticated(playerID: String, name: String)
        case unavailable(String)
    }

    private(set) var authState: AuthState = .unknown
    private let authenticator: any GameCenterAuthenticating

    init(authenticator: any GameCenterAuthenticating = LiveAuthenticator()) {
        self.authenticator = authenticator
    }

    var playerID: String? { if case .authenticated(let id, _) = authState { id } else { nil } }
    var displayName: String? { if case .authenticated(_, let name) = authState { name } else { nil } }

    func authenticate() async {
        do {
            let (id, name) = try await authenticator.authenticate()
            authState = .authenticated(playerID: id, name: name)
        } catch {
            authState = .unavailable(error.localizedDescription)
        }
    }

    /// 게임별 승수를 리더보드 `wins.<game>`에 올린다. 미로그인이면 아무것도 하지 않는다.
    func submit(wins: Int, game: GameID) async {
        guard playerID != nil else { return }
        try? await authenticator.submitScore(wins, leaderboardID: "wins.\(game.rawValue)")
    }

    func presentLeaderboards() {
        let vc = GKGameCenterViewController(state: .leaderboards)
        vc.gameCenterDelegate = Dismisser.shared
        LiveAuthenticator.topViewController()?.present(vc, animated: true)
    }

    private final class Dismisser: NSObject, GKGameCenterControllerDelegate {
        static let shared = Dismisser()
        func gameCenterViewControllerDidFinish(_ vc: GKGameCenterViewController) { vc.dismiss(animated: true) }
    }
}

/// GameKit 객체는 Sendable이 아니다. 델리게이트 콜백에서 메인 액터로 넘길 때만 감싼다.
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
```
`Mutex`는 `import Synchronization`(iOS 18)으로 쓴다. `Dismisser`의 delegate 메서드는 `nonisolated`가 필요하면 `MainActor.assumeIsolated`로 감싼다.

- [ ] **Step 4: 서버 연결과 전적 저장소**

`App/Online/SupabaseService.swift`에 더한다:
```swift
    /// Game Center 로그인 뒤 gamePlayerID ↔ 내 uid를 잇는다.
    func upsertProfile(player: String, name: String) async {
        guard let uid else { return }
        struct Profile: Encodable { let player: String; let uid: UUID; let name: String }
        _ = try? await client.from("profiles").upsert(Profile(player: player, uid: uid, name: name), onConflict: "player").execute()
    }

    func fetchRecords(player: String) async -> [RecordRow] {
        (try? await client.from("records").select().eq("player", value: player).execute().value) ?? []
    }

    /// 끝난 내 매치를 최근 순으로.
    func fetchFinished(limit: Int = 10) async -> [MatchRow] {
        (try? await client.from("matches").select().eq("status", value: "finished")
            .order("updated_at", ascending: false).limit(limit).execute().value) ?? []
    }
```
`MatchRow`에 `updatedAt: Date?`(키 `updated_at`, ISO8601 — `JSONDecoder`의 `dateDecodingStrategy`를 못 바꾸므로 `String?`로 받아 `ISO8601DateFormatter`로 바꾼다)를 더한다.

`App/Online/RecordsStore.swift`:
```swift
import Foundation
import Observation

struct RecordRow: Decodable, Equatable, Sendable {
    let player: String
    let game: String
    let wins: Int
    let losses: Int
    let draws: Int
}

struct RecentMatch: Equatable, Sendable {
    let id: UUID
    let game: String
    let opponent: String
    let result: String
    let finishedAt: Date?
}

/// 허브 전적 카드의 데이터. 서버 `records` 뷰와 최근 매치를 읽고 리더보드에 승수를 올린다.
@MainActor
@Observable
final class RecordsStore {
    private let service: SupabaseService
    private let gameCenter: GameCenterService
    private(set) var records: [RecordRow] = []
    private(set) var recent: [RecentMatch] = []

    init(service: SupabaseService, gameCenter: GameCenterService) {
        self.service = service
        self.gameCenter = gameCenter
    }

    /// 내 식별자: Game Center면 gamePlayerID, 아니면 uid.
    var me: String? { gameCenter.playerID ?? service.uid?.uuidString }

    func reload() async {
        guard let me, let uid = service.uid else { return }
        records = await service.fetchRecords(player: me)
        recent = Self.summarize(rows: await service.fetchFinished(), me: me, myUid: uid)
        for row in records { if let game = GameID(rawValue: row.game) { await gameCenter.submit(wins: row.wins, game: game) } }
    }

    static func summarize(rows: [MatchRow], me: String, myUid: UUID) -> [RecentMatch] {
        rows.compactMap { row in
            let mySeat: Int
            if row.hostPlayer == me || row.hostUid == myUid { mySeat = 0 }
            else if row.guestPlayer == me || row.guestUid == myUid { mySeat = 1 }
            else { return nil }
            let opponent = mySeat == 0 ? (row.guestName ?? "상대") : row.hostName
            let result = row.winnerSeat == nil ? "무" : (row.winnerSeat == mySeat ? "승" : "패")
            return RecentMatch(id: row.id, game: row.game, opponent: opponent, result: result, finishedAt: row.updatedAt)
        }
    }
}
```

- [ ] **Step 5: 앱에 잇기**

- `AppContainer`: `let records: RecordsStore`를 `init`에서 `RecordsStore(service: supabase, gameCenter: gameCenter)`로 만들고, `func bootstrap() async { await supabase.signIn(); await gameCenter.authenticate(); if let id = gameCenter.playerID, let name = gameCenter.displayName { await supabase.upsertProfile(player: id, name: name); if supabase.nickname.isEmpty { supabase.nickname = name } }; await records.reload() }`. `HubScreen`의 `.task { await container.bootstrap() }`. UI 테스트(`-noPush`) 때는 Game Center 로그인 창이 뜨지 않도록 `arguments.contains("-noGameCenter")`이면 `gameCenter.authenticate()`를 건너뛴다 — UI 테스트 `launchArguments`에 `"-noGameCenter"`를 더한다.
- `OnlineMenu`: `createRoom`·`joinRoom`에 `player: container.gameCenter.playerID`를 넘긴다(Task 5의 임시 `playerID`는 이 Task에서 실제 값이 된다).
- `OnlineMatch`·`GameSession`: 게임이 끝난 뒤(`outcome != nil` / `phase == .finished`) `onFinished?()`를 부르고, `AppContainer`가 `launchOmok`·`launch`에서 `onFinished = { [weak self] in Task { await self?.records.reload() } }`를 건다.
- `HubScreen.RecordsCard`를 채운다: 게임별 `승 x · 패 y · 무 z` 줄(`records`가 비면 "아직 전적이 없다"), 최근 매치 셋(`recent.prefix(3)`: `게임 · 상대 · 결과`), "전체 보기" 버튼이 `RecordsScreen`을 `navigationDestination`으로 열고, Game Center 로그인 상태 한 줄(`authenticated`면 이름, `unavailable`이면 "Game Center 미로그인 — 전적은 이 기기에만 남는다"). 식별자 `hub.records`.
- `App/Views/RecordsScreen.swift`: 게임별 카드(승·패·무·승률)와 최근 열 개 목록, 툴바 "리더보드" 버튼(`container.gameCenter.presentLeaderboards()`, 미로그인이면 비활성). 식별자 `records.leaderboard`.
- `App/YachtDice.entitlements`에 `com.apple.developer.game-center` `<true/>`를 되살린다(`aps-environment`와 함께).

- [ ] **Step 6: App Store Connect — Game Center와 리더보드**

`Tools/Release/asc.swift`로 시도한다(`ASC_KEY_PATH=~/Downloads/AuthKey_5G83CW4V3P.p8 ASC_KEY_ID=5G83CW4V3P ASC_ISSUER_ID=837de746-ac77-4806-801d-9765067971fa`):
1. App ID 기능: `post /v1/bundleIdCapabilities '{"data":{"type":"bundleIdCapabilities","attributes":{"capabilityType":"GAME_CENTER"},"relationships":{"bundleId":{"data":{"type":"bundleIds","id":"5SNA4TBXJ9"}}}}}'`.
2. 앱의 Game Center 상세: `post /v1/gameCenterDetails '{"data":{"type":"gameCenterDetails","relationships":{"app":{"data":{"type":"apps","id":"6809640357"}}}}}'` → 응답의 `id`를 `<detail>`로 둔다.
3. 리더보드 넷(각각): `post /v1/gameCenterLeaderboards '{"data":{"type":"gameCenterLeaderboards","attributes":{"referenceName":"<게임> 승수","vendorIdentifier":"wins.<game>","defaultFormatter":"INTEGER","scoreSortType":"DESC","submissionRateLimit":0,"scoreRangeStart":"0","scoreRangeEnd":"1000000"},"relationships":{"gameCenterDetail":{"data":{"type":"gameCenterDetails","id":"<detail>"}}}}}'` → 응답 `id`로 현지화: `post /v1/gameCenterLeaderboardLocalizations '{"data":{"type":"gameCenterLeaderboardLocalizations","attributes":{"locale":"ko","name":"<게임> 승수","formatterOverride":"INTEGER"},"relationships":{"gameCenterLeaderboard":{"data":{"type":"gameCenterLeaderboards","id":"<lb>"}}}}}'`.
4. 리더보드를 라이브로: `post /v1/gameCenterLeaderboardReleases '{"data":{"type":"gameCenterLeaderboardReleases","relationships":{"gameCenterDetail":{...<detail>},"gameCenterLeaderboard":{...<lb>}}}}'`.
어느 단계든 403이면 App Manager 권한 밖이므로 남은 단계를 사용자 작업으로 적는다: App Store Connect → 앱 → 서비스 → Game Center에서 리더보드 `wins.yacht`·`wins.omok`·`wins.cuppong`·`wins.alkkagi`(정수, 내림차순)를 만든다.

- [ ] **Step 7: 통과 확인** — 단위 전체. `DEVELOPMENT_TEAM=9P8KX3RJRR xcodegen generate` 뒤 시뮬레이터 빌드가 엔타이틀먼트로 실패하지 않아야 한다(시뮬레이터는 무시한다).

- [ ] **Step 8: 커밋** — `git add -A && git commit -m "feat(records): Game Center 신원과 profiles, 전적 화면, 리더보드 제출"`

---

### Task 8: 통합 테스트, 문서, 전체 검증, TestFlight

**Files:**
- Modify: `Tests/YachtDiceTests/SupabaseE2ETests.swift`, `README.md`, `docs/superpowers/specs/2026-09-10-p7-game-hub-omok-design.md`, `project.yml`(`CURRENT_PROJECT_VERSION: 5`)

- [ ] **Step 1: 오목 통합 테스트**

`SupabaseE2ETests.swift`에 더한다(`import GameCore`):
```swift
    @Test("오목 방을 만들고 들어가 다섯 수로 끝내면 winner_seat와 records가 남는다")
    func 오목_한_판() async throws {
        let host = SupabaseService(client: makeClient())
        let guest = SupabaseService(client: makeClient())
        await host.signIn(); await guest.signIn()
        let hostUid = try #require(host.uid), guestUid = try #require(guest.uid)
        let room = try await host.createRoom(name: "A", game: "omok", player: nil)
        #expect(room.game == "omok")
        let joined = try await guest.joinRoom(code: room.code, name: "B", player: nil)
        let refreshed = try await host.fetchMatch(id: room.id)
        let ta = SupabaseTurnTransport(client: host.client, matchID: room.id)
        let tb = SupabaseTurnTransport(client: guest.client, matchID: room.id)
        let a = OnlineMatch(game: Omok.self, mode: .online(matchID: room.id.uuidString),
                            participants: seatParticipants(localID: hostUid.uuidString, players: refreshed.seats(localUid: hostUid)),
                            log: MoveLog<Omok>(), transport: ta)
        let b = OnlineMatch(game: Omok.self, mode: .online(matchID: room.id.uuidString),
                            participants: seatParticipants(localID: guestUid.uuidString, players: joined.seats(localUid: guestUid)),
                            log: MoveLog<Omok>(), transport: tb)
        a.startListening(); b.startListening()
        let deadline = ContinuousClock.now + .seconds(8)
        while !(ta.isSubscribed && tb.isSubscribed), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        let moves: [(OnlineMatch<Omok>, Int, Int)] = [(a,0,0),(b,0,1),(a,1,0),(b,1,1),(a,2,0),(b,2,1),(a,3,0),(b,3,1),(a,4,0)]
        for (m, x, y) in moves {
            #expect(await m.play(Omok.Move(x: x, y: y)), "\(x),\(y) 실패: \(m.lastTransportError ?? "")")
            let other = m === a ? b : a
            let d = ContinuousClock.now + .seconds(10)
            while other.log.moves.count != m.log.moves.count, ContinuousClock.now < d { try await Task.sleep(for: .milliseconds(50)) }
            #expect(other.log.moves.count == m.log.moves.count, "상대에게 수가 가지 않았다")
        }
        #expect(a.outcome == .win(seat: 0) && b.outcome == .win(seat: 0))
        let final = try await host.fetchMatch(id: room.id)
        #expect(final.status == "finished" && final.winnerSeat == 0)
        // 끝난 판은 더 못 바꾼다
        await #expect(throws: (any Error).self) {
            try await ta.publish(TurnPayload(log: final.log, eventCount: 9, hints: [], turnSeat: 1, winnerSeat: nil, finished: false))
        }
        let records = await host.fetchRecords(player: hostUid.uuidString)
        #expect(records.first { $0.game == "omok" }?.wins == 1)
        let theirs = await guest.fetchRecords(player: guestUid.uuidString)
        #expect(theirs.first { $0.game == "omok" }?.losses == 1)
    }
```
`SupabaseTurnTransport.publish`는 재시도 3회 뒤 던지므로 마지막 `#expect(throws:)`는 약 2.4초 걸린다.

- [ ] **Step 2: 통합 실행** — `TEST_RUNNER_YACHT_SUPABASE_E2E=1 ... -only-testing:YachtDiceTests/SupabaseE2ETests`. 요트 8개 + 오목 1개 통과. 익명 가입 한도(시간당 30회)에 걸리면 한 시간 뒤 다시 돈다.

- [ ] **Step 3: 문서** — README에 "게임 허브" 절을 더해 `GameCore`·`OnlineMatch`·`records`·Game Center(선택 로그인, 리더보드 ID 넷) 구조를 적고, 온라인 절의 `matches` 열 목록에 `game`·`host_player`·`guest_player`·`winner_seat`를 더하며, 새 게임을 붙이는 세 조각(규칙 파일·화면·`AppContainer` 갈래)을 적는다. 스펙 상태를 "구현 완료 (날짜)"로 바꾼다.

- [ ] **Step 4: 전체 검증** — 단위 전체, UI 전체(`-only-testing:YachtDiceUITests`), 통합. 셋 다 통과.

- [ ] **Step 5: TestFlight** — `project.yml`의 `CURRENT_PROJECT_VERSION`을 5로 올리고 `DEVELOPMENT_TEAM=9P8KX3RJRR ASC_KEY_PATH=... Tools/Release/upload.sh`. 처리가 끝나면 `asc.swift`로 외부 그룹 `5bcb4a46-f292-4704-b255-c286a8bdcbc5`에 붙이고 이전 빌드를 만료한 뒤 `betaAppReviewSubmissions`에 제출한다(P6과 같은 절차).

- [ ] **Step 6: 커밋** — `git add -A && git commit -m "docs: P7 완료 반영과 빌드 5"` 뒤 `git push origin main`.
