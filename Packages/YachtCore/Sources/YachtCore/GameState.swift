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
        precondition((1...YachtCore.maxPlayers).contains(playerCount),
                     "플레이어는 1...\(YachtCore.maxPlayers)명이다: \(playerCount)")
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

    /// 부작용이 없다. 뷰가 버튼 활성화를 판단할 때 매 렌더마다 불러도 안전하다.
    public func validate(_ intent: Intent) -> Result<Void, RuleError> {
        guard phase != .finished else { return .failure(.gameFinished) }

        switch intent {
        case .roll:
            guard rollsRemaining > 0 else { return .failure(.noRollsRemaining) }
            guard !rollableIndices.isEmpty else { return .failure(.allDiceHeld) }
            return .success(())

        case .toggleHold(let index):
            guard (0..<YachtCore.diceCount).contains(index) else { return .failure(.indexOutOfRange(index)) }
            guard phase == .rolling else { return .failure(.mustRollFirst) }
            return .success(())

        case .commit(let category):
            guard phase == .rolling else { return .failure(.mustRollFirst) }
            guard !scorecards[currentPlayer].isFilled(category) else {
                return .failure(.categoryAlreadyUsed(category))
            }
            return .success(())
        }
    }

    public func allows(_ intent: Intent) -> Bool {
        if case .success = validate(intent) { return true }
        return false
    }

    /// 신뢰할 수 없는 출처(저장 파일, 나중에는 네트워크)에서 온 이벤트가 적용 가능한지 검사한다.
    ///
    /// `applying(_:)`의 precondition들은 신뢰하는 호출자를 위한 불변식이라 위반하면 트랩을 낸다.
    /// 트랩은 잡을 수 없으므로, 손상된 저장 파일이 앱을 실행 즉시 죽이는 것을 막으려면
    /// 신뢰 경계에서 먼저 이 검사를 통과시켜야 한다. 부작용은 없다.
    public func canApply(_ event: Event) -> Bool {
        switch event {
        case .rolled(let values):
            return values.count == rollableIndices.count
                && values.allSatisfy { (1...6).contains($0) }
        case .holdToggled(let index):
            return (0..<YachtCore.diceCount).contains(index)
        case .committed(let category, _):
            return !scorecards[currentPlayer].isFilled(category)
        case .turnAdvanced, .gameEnded:
            return true
        }
    }

    public static func replaying(_ events: [Event], playerCount: Int) -> GameState {
        events.reduce(GameState(playerCount: playerCount)) { $0.applying($1) }
    }
}
