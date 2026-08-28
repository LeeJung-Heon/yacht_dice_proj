import Foundation

/// 플레이어가 하고 싶은 것. 출처(터치 / AI / 네트워크)를 코어는 모른다.
public enum Intent: Equatable, Sendable {
    case roll
    case toggleHold(Int)
    case commit(ScoreCategory)
}

public enum RuleError: Error, Equatable, Sendable {
    case gameFinished
    case noRollsRemaining
    case allDiceHeld
    case mustRollFirst
    case categoryAlreadyUsed(ScoreCategory)
    case indexOutOfRange(Int)
}
