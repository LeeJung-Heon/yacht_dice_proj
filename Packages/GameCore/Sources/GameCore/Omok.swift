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
