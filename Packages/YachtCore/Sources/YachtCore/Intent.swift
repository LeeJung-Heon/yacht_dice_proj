import Foundation

/// 플레이어가 하고 싶은 것. 출처(터치 / AI / 네트워크)를 코어는 모른다.
public enum Intent: Equatable, Sendable {
    case roll
    case toggleHold(Int)
    case commit(Category)
}

public enum RuleError: Error, Equatable, Sendable {
    case gameFinished
    case noRollsRemaining
    case allDiceHeld
    case mustRollFirst
    case categoryAlreadyUsed(Category)
    case indexOutOfRange(Int)
}

extension Result where Success == Void, Failure == RuleError {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success):
            return true
        case (.failure(let a), .failure(let b)):
            return a == b
        default:
            return false
        }
    }
}
