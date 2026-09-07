import Foundation

public enum BotDifficulty: String, Codable, CaseIterable, Sendable {
    case easy, normal, hard

    public var displayName: String {
        switch self {
        case .easy: "쉬움"
        case .normal: "보통"
        case .hard: "어려움"
        }
    }
}
