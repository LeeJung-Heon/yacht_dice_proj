import Foundation

/// 알까기. 각자 제 진영에 돌 다섯을 놓은 다음, 13줄 판에서 번갈아 튕겨 상대 돌을 판 밖으로 밀어낸다.
/// 수는 배치 한 번과 튕긴 힘이고, 움직임은 1/120초 정수 시뮬레이션이라 어느 기기에서나 같다.
public enum Alkkagi: Game {
    public static let id = "alkkagi"
    public static let displayName = "알까기"
    public static let seatCount = 2
    public static let lines = 13
    public static let spacing = 1000
    public static let boardMax = 12000
    public static let stoneRadius = 400
    public static let stonesPerSeat = 5
    public static let stepsPerSecond = 120
    /// 스텝 상한. 최대 속력 30000이 마찰 100/스텝에 300스텝 안에 멎고 반발 9/10은 속력을 키우지 못해, 실제로는 닿지 않는 여유다.
    public static let maxSteps = 600
    public static let frameEvery = 4
    /// 낙하 경계. 중심이 이 밖이면 떨어진 것이다.
    static let dropMin = -400, dropMax = 12400
    /// 마찰: 스텝마다 속력이 이만큼 준다(초당 12000).
    static let frictionPerStep = 100
    static let contact = 800

    public struct Point: Codable, Equatable, Sendable {
        public var x: Int
        public var y: Int
        public init(x: Int, y: Int) { self.x = x; self.y = y }
    }

    /// 튕긴 힘. stone은 내 돌 번호, dx·dy는 방향(-1000…1000), power는 세기(1…1000).
    public struct Flick: Codable, Equatable, Sendable {
        public let stone: Int
        public let dx: Int
        public let dy: Int
        public let power: Int
        public init(stone: Int, dx: Int, dy: Int, power: Int) { self.stone = stone; self.dx = dx; self.dy = dy; self.power = power }
    }

    /// 한 수. 판이 열리면 좌석마다 배치를 한 번 두고, 그다음부터는 튕김만 둔다.
    public enum Move: Codable, Equatable, Sendable {
        case setup([Point])
        case flick(Flick)
    }

    /// 판의 단계. 두 좌석이 다 놓기 전까지가 배치다.
    public enum Phase: Codable, Equatable, Sendable { case setup, play }

    public struct StoneRef: Equatable, Sendable {
        public let seat: Int
        public let stone: Int
        public init(seat: Int, stone: Int) { self.seat = seat; self.stone = stone }
    }

    public struct Frame: Equatable, Sendable {
        public let stones: [[Point?]]
        public init(stones: [[Point?]]) { self.stones = stones }
    }

    public struct Event: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case collision(a: StoneRef, b: StoneRef)
            case dropped(StoneRef)
        }
        public let step: Int
        public let kind: Kind
        public init(step: Int, kind: Kind) { self.step = step; self.kind = kind }
    }

    /// 한 번의 튕김이 만든 움직임 전체. 화면은 frames를 30fps로 재생한다.
    public struct Simulation: Equatable, Sendable {
        public let frames: [Frame]
        public let events: [Event]
        public let final: [[Point?]]
        public let steps: Int
    }

    public struct State: Codable, Equatable, Sendable {
        /// stones[좌석][돌]. 아직 놓지 않은 돌과 떨어진 돌은 nil.
        public var stones: [[Point?]]
        /// 좌석이 배치를 마쳤는지. 둘 다 참이면 튕기기가 시작된다.
        public var placed: [Bool]
        public var nextSeat: Int?
        public var outcome: Outcome?
        /// 마지막 수의 재생. 저장·전송에는 넣지 않는다 — 수에서 다시 만든다.
        public var lastSimulation: Simulation?

        /// 두 좌석이 다 놓았으면 튕기는 단계다.
        public var phase: Phase { placed.allSatisfy { $0 } ? .play : .setup }

        public init(stones: [[Point?]], placed: [Bool] = [true, true], nextSeat: Int?, outcome: Outcome?) {
            self.stones = stones; self.placed = placed; self.nextSeat = nextSeat; self.outcome = outcome
            self.lastSimulation = nil
        }

        enum CodingKeys: String, CodingKey { case stones, placed, nextSeat, outcome }

        /// 재생은 수에서 다시 만드는 것이라 디코드한 상태에는 담기지 않는다.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(stones: try container.decode([[Point?]].self, forKey: .stones),
                      placed: try container.decode([Bool].self, forKey: .placed),
                      nextSeat: try container.decodeIfPresent(Int.self, forKey: .nextSeat),
                      outcome: try container.decodeIfPresent(Outcome.self, forKey: .outcome))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(stones, forKey: .stones)
            try container.encode(placed, forKey: .placed)
            try container.encodeIfPresent(nextSeat, forKey: .nextSeat)
            try container.encodeIfPresent(outcome, forKey: .outcome)
        }

        public func remaining(seat: Int) -> Int { stones[seat].compactMap { $0 }.count }
    }

    /// 판은 돌 하나 없이 열리고, 좌석 0이 먼저 놓는다.
    public static func initial() -> State {
        let empty = [Point?](repeating: nil, count: stonesPerSeat)
        return State(stones: [empty, empty], placed: [false, false], nextSeat: 0, outcome: nil)
    }

    /// 좌석의 진영. 가운데 줄(`y = 6000`)은 어느 쪽도 쓰지 못해 두 진영이 2000 떨어진다.
    public static func homeRange(seat: Int) -> ClosedRange<Int> { seat == 0 ? 0...5000 : 7000...12000 }

    /// 손대지 않으면 놓이는 한 줄.
    public static func defaultPlacement(seat: Int) -> [Point] {
        let y = seat == 0 ? 2000 : 10000
        return (0..<stonesPerSeat).map { Point(x: 4000 + $0 * spacing, y: y) }
    }

    /// 돌 다섯이 모두 제 진영의 교차점에 있고 서로 닿지 않아야 배치다.
    public static func placementIsValid(_ points: [Point], seat: Int) -> Bool {
        guard points.count == stonesPerSeat else { return false }
        let home = homeRange(seat: seat)
        for p in points {
            guard (0...boardMax).contains(p.x), home.contains(p.y) else { return false }
            guard p.x % spacing == 0, p.y % spacing == 0 else { return false }
        }
        for (i, a) in points.enumerated() {
            for b in points[(i + 1)...] {
                let dx = b.x - a.x, dy = b.y - a.y
                guard dx * dx + dy * dy >= contact * contact else { return false }
            }
        }
        return true
    }

    /// 두 기본 배치를 놓은 판. 테스트와 미리보기가 배치를 건너뛰고 쓴다.
    public static func standardStart() -> State {
        var state = initial()
        for seat in 0..<seatCount { state = apply(.setup(defaultPlacement(seat: seat)), to: state) }
        return state
    }

    public static func canApply(_ move: Move, to state: State) -> Bool {
        guard let seat = state.nextSeat else { return false }
        switch move {
        case .setup(let points):
            guard state.phase == .setup, !state.placed[seat] else { return false }
            return placementIsValid(points, seat: seat)
        case .flick(let flick):
            guard state.phase == .play else { return false }
            return canFlick(flick, seat: seat, in: state)
        }
    }

    private static func canFlick(_ flick: Flick, seat: Int, in state: State) -> Bool {
        guard (0..<stonesPerSeat).contains(flick.stone), state.stones[seat][flick.stone] != nil else { return false }
        guard (-1000...1000).contains(flick.dx), (-1000...1000).contains(flick.dy), flick.dx != 0 || flick.dy != 0 else { return false }
        return (1...1000).contains(flick.power)
    }

    public static func apply(_ move: Move, to state: State) -> State {
        guard canApply(move, to: state), let seat = state.nextSeat else { return state }
        switch move {
        case .setup(let points):
            var next = state
            next.stones[seat] = points
            next.placed[seat] = true
            next.lastSimulation = nil
            // 남은 좌석이 놓고, 둘 다 놓았으면 좌석 0부터 튕긴다.
            next.nextSeat = next.placed.allSatisfy { $0 } ? 0 : 1 - seat
            return next
        case .flick(let flick):
            let sim = simulate(state, flick)
            var next = state
            next.stones = sim.final
            next.lastSimulation = sim
            let verdict = resolve(stones: sim.final, seat: seat)
            next.outcome = verdict.outcome
            next.nextSeat = verdict.nextSeat
            return next
        }
    }

    /// 승패만 본다. 상대 돌이 0이면 내 승리, 둘 다 0이면 무승부, 내 돌만 0이면 상대 승리.
    public static func resolve(stones: [[Point?]], seat: Int) -> (outcome: Outcome?, nextSeat: Int?) {
        let mine = stones[seat].compactMap { $0 }.count
        let theirs = stones[1 - seat].compactMap { $0 }.count
        if theirs == 0 && mine == 0 { return (.draw, nil) }
        if theirs == 0 { return (.win(seat: seat), nil) }
        if mine == 0 { return (.win(seat: 1 - seat), nil) }
        return (nil, 1 - seat)
    }

    public static func currentSeat(_ state: State) -> Int? { state.nextSeat }
    public static func outcome(_ state: State) -> Outcome? { state.outcome }

    /// 정수 제곱근(내림). 0과 음수는 0으로 본다.
    /// 어림은 Double로 잡되 보정은 정수 나눗셈으로만 해 결과가 기기와 무관하게 같고, 제곱이 Int를 넘치지도 않는다.
    public static func isqrt(_ n: Int) -> Int {
        guard n > 0 else { return 0 }
        var x = max(1, Int(Double(n).squareRoot()))
        while x > n / x { x -= 1 }
        while x + 1 <= n / (x + 1) { x += 1 }
        return x
    }

    /// 움직이는 돌 하나.
    private struct Body {
        var pos: Point
        var vx: Int
        var vy: Int
        var alive: Bool
    }

    /// 규칙에 맞지 않는 수는 아무것도 움직이지 않은 시뮬레이션으로 돌려보내, 방향이 0인 수나 없는 돌에도 멎지 않는다.
    public static func simulate(_ state: State, _ flick: Flick) -> Simulation {
        guard canApply(.flick(flick), to: state), let seat = state.nextSeat else {
            return Simulation(frames: [Frame(stones: state.stones)], events: [], final: state.stones, steps: 0)
        }
        var bodies: [[Body?]] = state.stones.map { row in row.map { $0.map { Body(pos: $0, vx: 0, vy: 0, alive: true) } } }
        let len = isqrt(flick.dx * flick.dx + flick.dy * flick.dy)
        let ux = flick.dx * 1000 / len, uy = flick.dy * 1000 / len
        bodies[seat][flick.stone]?.vx = ux * flick.power * 30 / 1000
        bodies[seat][flick.stone]?.vy = uy * flick.power * 30 / 1000

        var frames: [Frame] = [Frame(stones: snapshot(bodies))]
        var events: [Event] = []
        var step = 0
        while step < maxSteps {
            step += 1
            // 이동과 마찰
            for s in 0..<seatCount { for i in 0..<stonesPerSeat {
                guard var b = bodies[s][i], b.alive else { continue }
                b.pos.x += b.vx / stepsPerSecond
                b.pos.y += b.vy / stepsPerSecond
                let speed = isqrt(b.vx * b.vx + b.vy * b.vy)
                if speed <= frictionPerStep { b.vx = 0; b.vy = 0 } else {
                    let next = speed - frictionPerStep
                    b.vx = b.vx * next / speed
                    b.vy = b.vy * next / speed
                }
                bodies[s][i] = b
            } }
            // 충돌: 모든 쌍을 인덱스 순으로 한 번씩
            let refs = (0..<seatCount).flatMap { s in (0..<stonesPerSeat).map { StoneRef(seat: s, stone: $0) } }
            for (ai, a) in refs.enumerated() {
                for b in refs[(ai + 1)...] {
                    guard var ba = bodies[a.seat][a.stone], var bb = bodies[b.seat][b.stone], ba.alive, bb.alive else { continue }
                    let nx0 = bb.pos.x - ba.pos.x, ny0 = bb.pos.y - ba.pos.y
                    let d2 = nx0 * nx0 + ny0 * ny0
                    guard d2 < contact * contact else { continue }
                    let d = isqrt(d2)
                    let nx = d == 0 ? 1000 : nx0 * 1000 / d, ny = d == 0 ? 0 : ny0 * 1000 / d
                    let van = (ba.vx * nx + ba.vy * ny) / 1000
                    let vbn = (bb.vx * nx + bb.vy * ny) / 1000
                    if van - vbn > 0 {
                        let van2 = (van + vbn) / 2 + 9 * (vbn - van) / 20
                        let vbn2 = (van + vbn) / 2 + 9 * (van - vbn) / 20
                        ba.vx += nx * (van2 - van) / 1000; ba.vy += ny * (van2 - van) / 1000
                        bb.vx += nx * (vbn2 - vbn) / 1000; bb.vy += ny * (vbn2 - vbn) / 1000
                        events.append(Event(step: step, kind: .collision(a: a, b: b)))
                    }
                    let overlap = contact - d
                    if overlap > 0 {
                        let push = overlap / 2
                        ba.pos.x -= nx * push / 1000; ba.pos.y -= ny * push / 1000
                        bb.pos.x += nx * (overlap - push) / 1000; bb.pos.y += ny * (overlap - push) / 1000
                    }
                    bodies[a.seat][a.stone] = ba
                    bodies[b.seat][b.stone] = bb
                }
            }
            // 낙하
            for s in 0..<seatCount { for i in 0..<stonesPerSeat {
                guard var b = bodies[s][i], b.alive else { continue }
                if b.pos.x < dropMin || b.pos.x > dropMax || b.pos.y < dropMin || b.pos.y > dropMax {
                    b.alive = false
                    bodies[s][i] = b
                    events.append(Event(step: step, kind: .dropped(StoneRef(seat: s, stone: i))))
                }
            } }
            let moving = bodies.joined().contains { $0.map { $0.alive && ($0.vx != 0 || $0.vy != 0) } ?? false }
            if step % frameEvery == 0 || !moving { frames.append(Frame(stones: snapshot(bodies))) }
            if !moving { break }
        }
        let final = snapshot(bodies)
        return Simulation(frames: frames, events: events, final: final, steps: step)
    }

    private static func snapshot(_ bodies: [[Body?]]) -> [[Point?]] {
        bodies.map { row in row.map { $0.flatMap { $0.alive ? $0.pos : nil } } }
    }
}
