import Foundation
import YachtCore

/// 컴퓨터 상대. 상태를 보고 "다음 굴림 또는 기록까지"의 Intent 열을 돌려준다.
///
/// 한 번에 하나씩 돌려주지 않는 이유: 쉬움 난이도의 무작위 고정을 호출마다 새로 뽑으면
/// 고정을 켰다 껐다 반복할 수 있다. 목표 고정 집합을 한 번 정하고 거기까지의 토글을 다 돌려준다.
public struct BotPlayer: Sendable {
    public let difficulty: BotDifficulty

    public init(difficulty: BotDifficulty) {
        self.difficulty = difficulty
    }

    public func plan(_ state: GameState, using rng: inout some RandomNumberGenerator) -> [Intent] {
        guard state.phase != .finished else { return [] }
        if state.phase == .awaitingFirstRoll { return [.roll] }

        let card = state.scorecards[state.currentPlayer]
        if state.rollsRemaining == 0 {
            return [.commit(HandEvaluator.bestCommit(dice: state.dice, card: card).category)]
        }

        let target = holdSet(dice: state.dice, card: card, using: &rng)
        if target.count == state.dice.count {
            return [.commit(HandEvaluator.bestCommit(dice: state.dice, card: card).category)]
        }
        var intents: [Intent] = state.dice.indices
            .filter { state.held.contains($0) != target.contains($0) }
            .map { .toggleHold($0) }
        intents.append(.roll)
        return intents
    }

    // MARK: - 고정 집합

    func holdSet(dice: [Int], card: ScoreCard, using rng: inout some RandomNumberGenerator) -> Set<Int> {
        switch difficulty {
        case .hard:
            return HandEvaluator.bestHoldSet(dice: dice, card: card)
        case .normal:
            return Self.heuristicHold(dice: dice)
        case .easy:
            if Int(rng.next() % 100) < 40 {
                return Set(dice.indices.filter { _ in rng.next() % 2 == 0 })
            }
            return Self.mostFrequentHold(dice: dice)
        }
    }

    /// 보통: 4연속이 있으면 그것을, 아니면 가장 많은 눈을 고정한다.
    static func heuristicHold(dice: [Int]) -> Set<Int> {
        if let straight = straightHold(dice: dice) { return straight }
        return mostFrequentHold(dice: dice)
    }

    /// 가장 많이 나온 눈을 고정한다. 개수가 같으면 큰 눈.
    static func mostFrequentHold(dice: [Int]) -> Set<Int> {
        var counts = [Int](repeating: 0, count: 7)
        for face in dice { counts[face] += 1 }
        let face = (1...6).max { (counts[$0], $0) < (counts[$1], $1) }!
        return Set(dice.indices.filter { dice[$0] == face })
    }

    /// 1234 / 2345 / 3456 중 하나가 서로 다른 주사위로 채워지면 그 네 개를 고정한다.
    static func straightHold(dice: [Int]) -> Set<Int>? {
        for start in [2, 1, 3] {
            var chosen: Set<Int> = []
            for face in start..<(start + 4) {
                guard let index = dice.indices.first(where: { dice[$0] == face && !chosen.contains($0) }) else { break }
                chosen.insert(index)
            }
            if chosen.count == 4 { return chosen }
        }
        return nil
    }
}
