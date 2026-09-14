# P9: 알까기 설계

- 작성일: 2026-09-11
- 상태: 구현 완료 (2026-09-14). 통합 테스트로 알까기 온라인 한 판을 아홉 수로 끝내 `winner_seat`까지 확인했고, 실기기 두 대로 주고받는 온라인 대전의 체감(새총 당김 감도, 재생 속도감)은 실기기 확인이 남았다
- 선행: P7 게임 허브 (`2026-09-10-p7-game-hub-omok-design.md`), P8 컵퐁 (`2026-09-10-p8-cuppong-design.md`)
- 범위: 허브의 마지막 게임. 규칙·화면·재생만 더하고 코어·전송·허브·전적은 그대로 쓴다.

## 1. 목표

13줄 바둑판 위에서 돌 다섯 개씩을 번갈아 튕겨 상대 돌을 판 밖으로 밀어내는 알까기를 온라인·로컬 2인으로 붙이되, 튕긴 힘만 수로 보내고 규칙이 정수 고정소수점 시뮬레이션으로 돌들의 움직임·충돌·낙하를 정하여 두 기기가 비트까지 같은 결과와 같은 재생을 보게 한다.

## 2. 결정

| 항목 | 결정 |
|---|---|
| 판·돌 | 13줄 판(줄 간격 1000, 좌표 `0…12000`), 돌 반지름 400, 좌석당 5개. 좌석 0(흑)은 `y = 2000`, 좌석 1(백)은 `y = 10000`, x는 `4000, 5000, 6000, 7000, 8000` |
| 규칙 | 좌석 0 선, 턴마다 한 번 튕기고 결과와 상관없이 차례가 넘어간다. 중심이 판 밖으로 400 넘게 나간 돌은 누구 것이든 사라진다. 상대 돌이 0이면 승리, 한 튕김에 양쪽 마지막 돌이 함께 떨어지면 무승부, 내 돌만 0이 되면 상대 승리 |
| 수 | `Flick { stone: 0…4, dx: -1000…1000, dy: -1000…1000 (둘 다 0 불가), power: 1…1000 }`. 힌트 미사용 |
| 재현 | 1/120초 고정 간격 정수 시뮬레이션(사칙연산과 정수 제곱근만). 최대 600스텝. 4스텝마다 프레임을 기록해 30fps 재생 목록을 돌려준다 |
| 입력 | 새총식: 내 돌을 누른 채 끌면 당김 선과 화살표, 놓으면 끈 반대 방향으로 끈 길이(최대 돌 지름의 4배 = 3200)에 비례한 힘 |
| 시점 | 판은 뒤집지 않되 온라인의 좌석 1은 180° 돌려 내 돌이 아래에 오게 한다. 로컬 2인은 그대로 둔다 |
| 모드 | 온라인 대전과 로컬 2인. 컴퓨터 없음 |

## 3. 규칙 (`Packages/GameCore/Sources/GameCore/Alkkagi.swift`)

```swift
public enum Alkkagi: Game {
    public static let id = "alkkagi", displayName = "알까기", seatCount = 2
    public static let lines = 13, spacing = 1000, boardMax = 12000, stoneRadius = 400, stonesPerSeat = 5
    public static let stepsPerSecond = 120, maxSteps = 600, frameEvery = 4
    public struct Point: Codable, Equatable, Sendable { public var x: Int; public var y: Int }
    public struct Flick: Codable, Equatable, Sendable { public let stone: Int; public let dx: Int; public let dy: Int; public let power: Int }   // Move
    public struct Frame: Equatable, Sendable { public let stones: [[Point?]] }        // [좌석][돌]
    public struct StoneRef: Equatable, Sendable { public let seat: Int; public let stone: Int }
    public struct Event: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case collision(a: StoneRef, b: StoneRef); case dropped(StoneRef) }
        public let step: Int
        public let kind: Kind
    }
    public struct Simulation: Equatable, Sendable { public let frames: [Frame]; public let events: [Event]; public let final: [[Point?]]; public let steps: Int }
    public struct State: Codable, Equatable, Sendable {
        public var stones: [[Point?]]          // 떨어진 돌은 nil
        public var nextSeat: Int?
        public var outcome: Outcome?
        public var lastSimulation: Simulation?  // Codable에서 제외한다(재생용, 상태는 수에서 다시 만든다)
        public func remaining(seat: Int) -> Int
    }
    public static func simulate(_ state: State, _ flick: Flick) -> Simulation   // 순수 함수. 화면의 예상 궤적과 재생도 이것을 쓴다
}
```

- **초기 속도**: `len = isqrt(dx² + dy²)`, 단위 벡터 성분 `ux = dx * 1000 / len`, `uy = dy * 1000 / len`, 속도 `vx = ux * power * 30 / 1000`, `vy = uy * power * 30 / 1000`(단위/초, 최대 30000 = 초당 30칸).
- **스텝**: 모든 돌에 대해 `x += vx / 120`, `y += vy / 120`(정수 나눗셈). 마찰은 등감속 초당 12000이라 스텝마다 속력을 100 줄인다: `speed = isqrt(vx² + vy²)`, `next = max(0, speed - 100)`, `vx = vx * next / speed`, `vy = vy * next / speed`(속력 0이면 그대로 0). 속력이 100 아래로 떨어지면 0으로 둔다.
- **충돌**: 서로 다른 두 돌의 중심 거리 제곱이 `800²` 미만이면 법선 `n = (bx - ax, by - ay)`, `d = isqrt(n·n)`(0이면 `(1000, 0)`)이고 단위 법선 성분은 `nx = n.x * 1000 / d`, `ny = n.y * 1000 / d`다. 법선 속도 `van = (vax * nx + vay * ny) / 1000`, `vbn`도 같고, `van - vbn > 0`(접근 중)일 때만 반발 9/10로 교환한다: `van' = (van + vbn) / 2 + 9 * (vbn - van) / 20`, `vbn' = (van + vbn) / 2 + 9 * (van - vbn) / 20`이며 접선 성분은 그대로 두어 `va += n̂ * (van' - van)`, `vb += n̂ * (vbn' - vbn)`. 겹침 `800 - d`는 양쪽에 절반씩 법선 방향으로 밀어 뗀다. 한 스텝에서 모든 쌍을 인덱스 순으로 한 번씩 본다.
- **낙하**: 스텝 끝에 중심이 `x < -400`, `x > 12400`, `y < -400`, `y > 12400` 중 하나면 그 돌을 nil로 두고 `dropped` 이벤트를 남긴다.
- **종료**: 모든 남은 돌의 속력이 0이거나 600스텝에 이르면 끝낸다. 4스텝마다(0, 4, 8, …)와 마지막 스텝의 배치를 `frames`에 넣는다.
- `canApply`: `nextSeat != nil`, `stone` 범위 안이고 그 좌석의 돌이 남아 있으며, `dx`·`dy`가 범위 안이고 둘 다 0이 아니며, `power`가 1…1000이다.
- `apply`: `simulate`로 `final`을 얻어 `stones`에 넣고 `lastSimulation`에 두며, 상대 돌이 0이고 내 돌이 남았으면 `.win(seat)`, 둘 다 0이면 `.draw`, 내 돌만 0이면 `.win(1 - seat)`, 아니면 `nextSeat = 1 - seat`.
- `State`의 `Codable`은 `stones`·`nextSeat`·`outcome`만 다룬다(`lastSimulation`은 제외). `MoveLog`는 수만 저장한다.

## 4. 앱

| 파일 | 책임 |
|---|---|
| `App/Games/Alkkagi/AlkkagiGeometry.swift` | `project(_ p: Point, in size: CGSize, flipped: Bool) -> CGPoint`(판을 정사각형에 맞추고 `flipped`면 180°), `point(at: CGPoint, in:flipped:) -> Point`, `stone(at:stones:in:flipped:) -> Int?`(여유 안에서 가장 가까운 돌), `clampPull(from:to:) -> Point`(최대 당김에서 끊는다), `flick(stone: Int, from origin: Point, to finger: Point) -> Flick?`(격자 점 둘을 받아 끈 길이 3200 = power 1000, 방향은 끈 반대) |
| `App/Games/Alkkagi/AlkkagiBoardView.swift` | `Canvas`: 나무 판·13×13 격자·화점 5개·돌(흑백, 그림자·하이라이트)·당김 선과 화살표·예상 궤적 점선(시뮬레이션 앞 40프레임의 그 돌 위치)·재생 중 프레임의 돌 위치. 식별자 `alkkagi.board`, 라벨 "흑 n · 백 m" |
| `App/Games/Alkkagi/AlkkagiScreen.swift` | 헤더(`header.menu`, `header.status` = "내 돌 N · 상대 돌 M", `header.turn`), 명패 둘(`players.seat.<i>`, `players.presence.<i>`), 드래그(내 돌 위에서 시작한 것만) → 놓으면 `match.play(Flick)`, 프레임 재생(30fps, 충돌 프레임에 `SoundSynth.clack`·햅틱, 낙하에 `drop`), 상대 수 재생(`onRemoteMove`가 `simulate`로 프레임을 만들어 같은 재생), 차례 배너·토스트·연결 띠·결과 카드(`alkkagi.result`, `alkkagi.back`), `scenePhase` resync |
| `App/Games/Alkkagi/AlkkagiMenu.swift` | 로컬 2인(이름 기본값 흑·백)·온라인·이어하기, `menu.alkkagi.local`, `menu.alkkagi.online`, `menu.alkkagi.local.start`, `menu.alkkagi.name.0/1`, `menu.back` |
| `App/Games/GameCatalog.swift` | `alkkagi.isAvailable = true`(전부 활성) |
| `App/AppContainer.swift`, `App/YachtDiceApp.swift` | `Status.playingAlkkagi(OnlineMatch<Alkkagi>)`, `startAlkkagiLocal(names:)`, `launchAlkkagi`, `openSupabaseMatch`의 `alkkagi` 갈래, `resumeSavedGame`, `currentGame`, `stopCurrentGame`, `PushRegistration.currentMatchID`, 화면 분기 |
| `App/Feedback/SoundSynth.swift` | `clack()`(돌끼리 딱, 0.08초), `drop()`(판에서 떨어지는 툭, 0.12초) |

### 4.1 흐름

1. 허브 → 알까기 → 로컬 2인 또는 온라인. 온라인은 P7과 같고 `row.game == "alkkagi"`면 `OnlineMatch<Alkkagi>`와 `AlkkagiScreen`이 열린다.
2. 내 차례에 내 돌을 누른 채 끌면 돌에서 손가락까지 당김 선과 반대 방향 화살표가 보이고 `simulate`의 앞 40프레임으로 그 돌의 예상 궤적 점선을 그린다. 놓으면 `AlkkagiGeometry.flick`으로 만든 `Flick`을 `match.play`에 보낸다.
3. 화면은 `state.lastSimulation.frames`를 30fps로 재생하며 `collision` 이벤트 프레임에 `clack`, `dropped`에 `drop`을 낸다. 재생 중 입력은 잠긴다.
4. 상대 수는 `onRemoteMove`에서 `simulate(match.state, flick)`로 프레임을 만들어 같은 재생을 한 뒤 로그에 더해진다.
5. 끝나면 `endMatch(winnerSeat)`(무승부는 nil)와 결과 카드, `records`·`wins.alkkagi`.

### 4.2 끌기 → 수

돌 중심에서 손가락까지의 화면 벡터를 격자 단위로 바꾼 `(gx, gy)`에서 `len = isqrt(gx² + gy²)`, `power = clamp(len * 1000 / 3200, 1, 1000)`, `dx = -gx * 1000 / len`, `dy = -gy * 1000 / len`(뒤집힌 판이면 부호가 함께 뒤집힌다). 끈 길이가 200 미만이면 던지지 않는다. 남의 돌이나 빈 곳에서 시작한 드래그는 무시한다.

## 5. 테스트

| 대상 | 테스트 |
|---|---|
| `Alkkagi` 단위 | 초기 배치; 같은 수는 같은 `Simulation`(결정성); 직진 튕김이 마찰로 멈추는 거리와 프레임 수; 정면 충돌에서 맞은 돌이 법선 방향으로 움직이고 친 돌이 느려진다; 세게 치면 상대 돌이 떨어져 nil이 되고 `dropped` 이벤트가 난다; 내 돌만 판 밖으로 나가면 내 돌만 준다; 마지막 돌을 떨어뜨리면 `.win`, 함께 떨어지면 `.draw`; 600스텝 상한; `canApply`가 남의 돌·범위 밖·`power 0`을 거부; 로그 왕복(`lastSimulation` 제외) |
| 기하 단위 | `project`/`point` 왕복과 뒤집기 대칭, 끌기 → `Flick` 범위와 방향 반전, 짧은 끌기 nil |
| `OnlineMatch<Alkkagi>` | 메모리 쌍으로 수 전파·재생·완주 |
| 서버 통합 | `game = 'alkkagi'` 방에서 정해진 수 목록으로 끝까지 가 `winner_seat` |
| UI | 허브 → 알까기 로컬 2인 → 내 돌을 당겨 놓기 → `header.turn`이 바뀐다 |

## 6. 치르는 값

- 물리는 회전·미끄러짐 없는 단순 모델이고 정수 시뮬레이션이라 미세한 떨림이 보일 수 있다.
- 완벽한 힘을 계산해 보내는 클라이언트는 막지 못한다.
- 600스텝 상한은 실제로는 닿지 않는 여유다 — 가장 센 튕김의 속력 30000도 스텝마다 100씩 깎는 마찰에 300스텝 안에 멎고 반발 9/10은 속력을 키우지 못하니, 시작 배치에서 세기까지 훑어 잰 최악이 175스텝(45프레임)이라 재생은 길어야 1.5초쯤에 끝난다.
