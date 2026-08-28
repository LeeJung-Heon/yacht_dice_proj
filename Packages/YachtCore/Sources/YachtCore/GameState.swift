import Foundation

/// 게임의 전체 상태. applying(_:)은 순수 함수여야 한다 —
/// 랜덤이나 시간이 새어들면 P3의 재접속 리플레이가 깨진다.
public struct GameState: Equatable, Codable, Sendable {
    public private(set) var playerCount: Int
    public private(set) var scorecards: [ScoreCard]
    public private(set) var currentPlayer: Int
    public private(set) var turnIndex: Int
    public private(set) var dice: [Int]
    public private(set) var held: Set<Int>
    public private(set) var rollsUsed: Int
    public private(set) var phase: Phase

    public init(playerCount: Int = 1) {
        precondition(playerCount >= 1, "플레이어는 최소 1명이다")
        self.playerCount = playerCount
        self.scorecards = Array(repeating: ScoreCard(), count: playerCount)
        self.currentPlayer = 0
        self.turnIndex = 1
        self.dice = Array(repeating: 0, count: YachtCore.diceCount)
        self.held = []
        self.rollsUsed = 0
        self.phase = .awaitingFirstRoll
    }

    public var rollsRemaining: Int { YachtCore.maxRollsPerTurn - rollsUsed }

    /// keep되지 않은 슬롯. rolled(_:)의 값이 이 순서대로 채워진다.
    public var rollableIndices: [Int] {
        (0..<YachtCore.diceCount).filter { !held.contains($0) }
    }

    public var isAllScored: Bool { scorecards.allSatisfy(\.isComplete) }

    public func applying(_ event: Event) -> GameState {
        var next = self
        switch event {
        case .rolled(let values):
            let slots = next.rollableIndices
            precondition(values.count == slots.count,
                         "rolled(_:) 길이 \(values.count)가 굴릴 수 있는 주사위 \(slots.count)개와 다르다")
            precondition(values.allSatisfy { (1...6).contains($0) }, "주사위 눈은 1...6이어야 한다")
            for (slot, value) in zip(slots, values) { next.dice[slot] = value }
            next.rollsUsed += 1
            next.phase = .rolling

        case .holdToggled(let index):
            precondition((0..<YachtCore.diceCount).contains(index), "주사위 인덱스는 0...4다")
            if next.held.contains(index) { next.held.remove(index) } else { next.held.insert(index) }

        case .committed(let category, let points):
            next.scorecards[next.currentPlayer].record(category, points)

        case .turnAdvanced:
            next.dice = Array(repeating: 0, count: YachtCore.diceCount)
            next.held = []
            next.rollsUsed = 0
            next.phase = .awaitingFirstRoll
            next.currentPlayer = (next.currentPlayer + 1) % next.playerCount
            // 모든 플레이어가 이번 턴을 마쳐야 턴 번호가 오른다.
            if next.currentPlayer == 0 {
                next.turnIndex = min(next.turnIndex + 1, YachtCore.turnCount)
            }

        case .gameEnded:
            next.phase = .finished
        }
        return next
    }

    public static func replaying(_ events: [Event], playerCount: Int) -> GameState {
        events.reduce(GameState(playerCount: playerCount)) { $0.applying($1) }
    }
}
