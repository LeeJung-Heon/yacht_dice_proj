import Foundation

/// 컵퐁. 상대 진영의 컵 열 개를 번갈아 던져 먼저 비운다. 비행과 충돌은 고정 간격 정수 물리로 재현한다.
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
        /// 저장하지 않는 재생 정보. 던진 수에서 다시 계산한다.
        public var lastSimulation: Simulation? = nil

        enum CodingKeys: String, CodingKey { case cups, nextSeat, lastShot, outcome }

        public static func == (lhs: State, rhs: State) -> Bool {
            lhs.cups == rhs.cups && lhs.nextSeat == rhs.nextSeat && lhs.lastShot == rhs.lastShot && lhs.outcome == rhs.outcome
        }
        public func remaining(seat: Int) -> Int { cups[seat].filter { $0 }.count }
    }

    public static func initial() -> State {
        State(cups: Array(repeating: Array(repeating: true, count: cupCount), count: seatCount),
              nextSeat: 0, lastShot: nil, outcome: nil)
    }

    public static func canApply(_ move: Shot, to state: State) -> Bool {
        state.nextSeat != nil && (-1000...1000).contains(move.dx) && (0...1000).contains(move.power)
    }

    /// 실제 비행과 충돌을 끝까지 계산한 결과. 화면 재생도 같은 시뮬레이션을 사용한다.
    public static func landing(of shot: Shot, against cups: [Bool]) -> Landing {
        simulate(shot, against: cups).landing
    }

    public static func apply(_ move: Shot, to state: State) -> State {
        guard canApply(move, to: state), let seat = state.nextSeat else { return state }
        var next = state
        let target = 1 - seat
        let simulation = simulate(move, against: state.cups[target])
        let result = simulation.landing
        next.lastSimulation = simulation
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
