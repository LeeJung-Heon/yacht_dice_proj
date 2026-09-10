import Foundation

/// 컵퐁. 상대 진영의 컵 열 개를 번갈아 던져 먼저 비운다. 수는 던진 힘뿐이고 착지는 정수 수식이라 어디서나 같다.
public enum CupPong: Game {
    public static let id = "cuppong"
    public static let displayName = "컵퐁"
    public static let seatCount = 2
    public static let cupCount = 10
    /// 테이블은 x가 -1000…1000, y가 0…3000(던지는 쪽이 0)이다.
    public static let tableHalfWidth = 1000
    public static let tableLength = 3000
    public static let cupRadius = 120
    /// 뒤에서부터 4·3·2·1개. 인덱스 0…9.
    public static let cupCenters: [(x: Int, y: Int)] = [
        (-390, 2800), (-130, 2800), (130, 2800), (390, 2800),
        (-260, 2600), (0, 2600), (260, 2600),
        (-130, 2400), (130, 2400),
        (0, 2200),
    ]

    /// 던진 힘. dx는 좌우(-1000…1000), power는 세기(0…1000).
    public struct Shot: Codable, Equatable, Sendable {
        public let dx: Int
        public let power: Int
        public init(dx: Int, power: Int) { self.dx = dx; self.power = power }
    }

    /// 착지점과 맞힌 컵.
    public struct Landing: Codable, Equatable, Sendable {
        public let x: Int
        public let y: Int
        public let cup: Int?
        public init(x: Int, y: Int, cup: Int?) { self.x = x; self.y = y; self.cup = cup }
    }

    public struct State: Codable, Equatable, Sendable {
        /// cups[좌석][컵]. 남아 있으면 true.
        public var cups: [[Bool]]
        public var nextSeat: Int?
        public var lastShot: Landing?
        public var outcome: Outcome?
        public func remaining(seat: Int) -> Int { cups[seat].filter { $0 }.count }
    }

    public static func initial() -> State {
        State(cups: Array(repeating: Array(repeating: true, count: cupCount), count: seatCount),
              nextSeat: 0, lastShot: nil, outcome: nil)
    }

    public static func canApply(_ move: Shot, to state: State) -> Bool {
        state.nextSeat != nil && (-1000...1000).contains(move.dx) && (0...1000).contains(move.power)
    }

    /// 착지: 세기가 클수록 멀리, 좌우는 거리에 비례해 벌어진다. 정수 나눗셈만 쓴다.
    public static func landing(of shot: Shot, against cups: [Bool]) -> Landing {
        let l = 1200 + shot.power * 2 + shot.power * shot.power / 400
        let x = shot.dx * l / 1500
        guard l <= tableLength, abs(x) <= tableHalfWidth else { return Landing(x: x, y: l, cup: nil) }
        let r2 = cupRadius * cupRadius
        let hit = cupCenters.indices.first { i in
            cups[i] && (x - cupCenters[i].x) * (x - cupCenters[i].x) + (l - cupCenters[i].y) * (l - cupCenters[i].y) < r2
        }
        return Landing(x: x, y: l, cup: hit)
    }

    public static func apply(_ move: Shot, to state: State) -> State {
        guard canApply(move, to: state), let seat = state.nextSeat else { return state }
        var next = state
        let target = 1 - seat
        let result = landing(of: move, against: state.cups[target])
        next.lastShot = result
        if let cup = result.cup {
            next.cups[target][cup] = false
            if next.remaining(seat: target) == 0 {
                next.outcome = .win(seat: seat)
                next.nextSeat = nil
            }
        } else {
            next.nextSeat = target
        }
        return next
    }

    public static func currentSeat(_ state: State) -> Int? { state.nextSeat }
    public static func outcome(_ state: State) -> Outcome? { state.outcome }
}
