# P8: 컵퐁 설계

- 작성일: 2026-09-10
- 상태: 구현 완료 (2026-09-10). 통합 테스트로 컵퐁 온라인 한 판을 열 번 맞혀 `winner_seat`까지 확인했고, 실기기 두 대로 주고받는 온라인 대전의 체감(특히 스와이프 세기 감도)은 실기기 확인이 남았다
- 선행: P7 게임 허브·공통 온라인 코어 (`2026-09-10-p7-game-hub-omok-design.md`)
- 범위: 허브의 두 번째 새 게임. `Game`·`MoveLog`·`OnlineMatch`·허브·전적은 P7 것을 그대로 쓰고 규칙·화면·재생만 더한다.

## 1. 목표

iMessage 컵퐁처럼 상대 진영의 컵 10개를 번갈아 던져 먼저 비우는 턴제 게임을 온라인·로컬 2인으로 붙이되, 던진 힘만 수로 보내고 규칙이 정해진 수식으로 착지를 계산하여 두 화면이 같은 공과 같은 결과를 보게 하고, 결과를 클라이언트가 적을 수 없게 한다.

## 2. 결정

| 항목 | 결정 |
|---|---|
| 규칙 | 양쪽 컵 10개, 좌석 0(호스트) 선, 턴마다 공 하나, 넣으면 한 번 더, 못 넣으면 차례가 넘어간다. 상대 컵을 다 비우면 승리, 무승부 없음, 리랙·튕겨 넣기 없음 |
| 수 | `Shot { dx: Int(-1000…1000), power: Int(0…1000) }` — 스와이프의 좌우·세기. 힌트(`throws` 열)는 쓰지 않는다 |
| 재현 | `apply`가 사칙연산만으로 착지점과 맞힌 컵을 정한다(`sin`·`tan`·`sqrt`·난수 없음). 상대는 같은 수로 같은 궤적을 재생한다 |
| 시점 | 화면은 항상 던지는 사람의 시점이다. 먼 쪽 삼각형이 지금 맞혀야 할 컵이고 상대 차례에는 상대의 수를 같은 시점에서 재생한다 |
| 모드 | 온라인 대전과 로컬 2인. 컴퓨터 상대 없음 |
| 그리기 | RealityKit 실제 3D(나무 테두리·초록 테이블·속이 열린 빨간 컵·공), 컵별 사진 커스텀은 `2026-09-14-cuppong-3d-customization.md` |

## 3. 규칙 (`Packages/GameCore/Sources/GameCore/CupPong.swift`)

```swift
public enum CupPong: Game {
    public static let id = "cuppong", displayName = "컵퐁", seatCount = 2, cupCount = 10
    public struct Shot: Codable, Equatable, Sendable { public let dx: Int; public let power: Int }   // Move
    public struct Landing: Codable, Equatable, Sendable { public let x: Int; public let y: Int; public let cup: Int? }
    public struct State: Codable, Equatable, Sendable {
        public var cups: [[Bool]]          // [좌석][컵 0…9] 남아 있으면 true. cups[s]는 좌석 s의 컵이다
        public var nextSeat: Int?
        public var lastShot: Landing?      // 마지막 던지기의 착지점과 맞힌 컵. 화면이 재생에 쓴다
        public var outcome: Outcome?
    }
}
```

- 좌표계는 테이블 위 정수 격자다. 테이블은 폭 `-1000…1000`(x), 길이 `0…3000`(y, 던지는 쪽이 0)이며 컵 삼각형은 `y = 2200…2800`에 놓인다. 컵 중심은 규칙의 상수 `cupCenters: [(x, y)]` 열 개(맨 뒤 4개, 3개, 2개, 1개 순으로 인덱스 0…9), 컵 반지름은 `cupRadius = 120`이다.
- 착지: `L = 1200 + power * 2` 에 `power * power / 400`을 더해 세기가 클수록 더 멀리 가게 하고(`power = 0`이면 1200, `1000`이면 5700으로 테이블 밖), `X = dx * L / 1500`이다. `L > 3000`이면 테이블을 넘긴 빗나감, `X`가 `-1000…1000` 밖이면 옆으로 빗나감이다. 정수 나눗셈만 쓴다.
- 맞힘: 상대 좌석의 남은 컵 중 `(X - cx)² + (L - cy)² < cupRadius²`인 첫 컵(인덱스 순)이다.
- `canApply`: `nextSeat != nil`이고 `dx`·`power`가 범위 안이다.
- `apply`: 착지를 계산해 `lastShot`에 적고, 맞혔으면 그 컵을 비우고 `nextSeat`를 유지하며 상대 컵이 모두 비면 `.win(seat)`, 빗나갔으면 `nextSeat = 1 - seat`.
- 예상 궤적 점선과 착지 표시는 없다. 실제 던진 공의 포물선 높이만 화면에서 연출한다.

## 4. 앱

| 파일 | 책임 |
|---|---|
| `App/Games/CupPong/CupPongTableView.swift` | `CupPongScene`의 실제 3D 테이블·컵·공을 `RealityView`에 연결한다. 컵 상태·실제 공 위치·소유자의 사진을 받는다 |
| `App/Games/CupPong/CupPongScreen.swift` | 헤더(`header.menu`, 남은 컵 수 `header.status`), 명패 둘(`players.seat.<i>`, 접속 점), 스와이프 제스처 → `Shot` → `match.play`, 0.9초 공 애니메이션과 컵 소멸, 상대 수 재생(`onRemoteMove`), "한 번 더!"·차례 배너, 연결 띠, 결과 카드(`cuppong.result`, `cuppong.back`), `scenePhase` resync |
| `App/Games/CupPong/CupPongMenu.swift` | 로컬 2인(이름 둘)·온라인(`OnlineMenu(container:game: .cuppong)`)·이어하기, `menu.cuppong.local`, `menu.cuppong.online`, `menu.cuppong.local.start`, `menu.back` |
| `App/Games/GameCatalog.swift` | `cuppong.isAvailable = true` |
| `App/AppContainer.swift` | `Status.playingCupPong(OnlineMatch<CupPong>)`, `startCupPongLocal(names:)`, `launchCupPong`, `openSupabaseMatch`의 `cuppong` 갈래, `resumeSavedGame`, `currentGame`, `stopCurrentGame`, `PushRegistration.currentMatchID` |
| `App/YachtDiceApp.swift` | `.menu(.cuppong) → CupPongMenu`, `.playingCupPong → CupPongScreen` |
| `App/Feedback/SoundSynth.swift` | `pong()` — 공이 컵에 들어가는 짧은 "퐁"(물 튀는 노이즈 + 낮은 공진) |

### 4.1 흐름

1. 허브 → 컵퐁 타일 → 메뉴 → 로컬 2인 또는 온라인. 온라인 방 만들기·입장·열기는 P7과 같고 `row.game == "cuppong"`이면 `OnlineMatch<CupPong>`와 `CupPongScreen`이 열린다.
2. 내 차례에 아래 중앙의 공을 위로 끌어 놓으면 끈 벡터를 `dx`(좌우, -1000…1000)·`power`(길이·속도, 0…1000)로 바꿔 `match.play(Shot)`을 부른다. 화면은 `state.lastShot`으로 공을 0.9초 날리고 컵을 맞혔으면 지운 뒤 "한 번 더!" 또는 차례 배너를 보인다.
3. 상대 수는 `onRemoteMove`로 같은 애니메이션을 재생한다. 화면은 던지는 사람의 시점이라 먼 쪽 삼각형은 상대 차례에 내 컵이 되며, 명패 아래 한 줄(`cuppong.owner`)이 "상대가 내 컵 N개를 노린다"고 알리고 테이블의 접근성 라벨도 "내 컵 N개 남음"으로 뒤집힌다.
4. 상대 컵이 모두 비면 `endMatch(winnerSeat)`가 나가고 결과 카드가 보이며 `records`가 갱신되어 `wins.cuppong`에 제출된다.
5. 로컬 2인은 같은 화면에서 차례가 바뀔 때 "OO 차례" 배너로 기기를 넘긴다.

### 4.2 스와이프 → 수

끌기 시작점에서 끝점까지의 벡터 `(vx, vy)`(위가 양수)와 놓기 직전 구간의 속도 `s`(마지막 두 표본 사이의 초당 이동 거리, 시간 간격은 1/120초에서 막는다)로 `power = clamp(길이 / 화면 높이 * 1400 * (1 + 0.15 * min(1, s / (화면 높이 * 4))), 0, 1000)`, `dx = clamp(vx / max(|vy|, 1) * 1000, -1000, 1000)`을 만든다. 세기는 끈 길이가 정하고 속도는 최대 15%만 얹으므로 화면 가운데를 향해 끈 손이 테이블 밖으로 넘어가지 않으며, 예상 궤적을 표시하지 않고 놓을 때 마지막 속도 표본을 반영한다. 위로 끌지 않으면(`vy <= 0`) 던지지 않는다. 값은 정수로 반올림하여 그대로 수가 된다.

## 5. 테스트

| 대상 | 테스트 |
|---|---|
| `CupPong` 단위 | 같은 수는 같은 착지·같은 결과(결정성); 특정 `Shot`이 컵 9(맨 앞)를 맞히고 차례를 유지한다; 빗나가면 차례가 넘어간다; 테이블을 넘기거나 옆으로 벗어나는 힘은 빗나감이다; 열 번 맞히면 `.win`; 범위 밖 수 거부; 로그 왕복 |
| 기하 단위 | `CupPongGeometry.project`가 먼 쪽을 좁게 사상하고 스와이프 → `Shot` 변환이 범위를 지킨다 |
| `OnlineMatch<CupPong>` | 메모리 쌍으로 정해진 수 목록을 주고받아 완주하고 상대 수가 순서대로 재생된다 |
| 서버 통합 | `game = 'cuppong'` 방에서 수를 주고받고 끝까지 가면 `winner_seat`가 남는다 |
| UI | 허브 → 컵퐁 로컬 2인 → 스와이프 한 번 → `lastShot` 결과 표시(`cuppong.table`) |

## 6. 치르는 값

- 힘만 보내므로 결과 조작은 막히지만, 완벽한 힘 값을 계산해 보내는 클라이언트는 막지 못한다.
- 물리는 단순 수식이라 튕김·회전이 없고, 실제 비어퐁 변형 규칙은 없다.
- 연속 성공 동안은 `turn_seat`가 같아 푸시가 가지 않고 차례가 넘어갈 때만 간다.
