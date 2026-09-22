import Foundation

/// 승부의 결말. 진행 중이면 nil을 쓴다.
public enum Outcome: Codable, Equatable, Sendable {
    case win(seat: Int)
    case draw
}

/// 턴제 게임 하나의 규칙. 상태는 값이고 수는 그대로 로그에 남는다.
public protocol Game {
    associatedtype State: Codable & Equatable & Sendable
    associatedtype Move: Codable & Equatable & Sendable
    /// 서버 `matches.game` 열과 같은 문자열.
    static var id: String { get }
    static var displayName: String { get }
    static var seatCount: Int { get }
    /// 판 크기·물리·라운드 규칙이 바뀌면 올린다. 서로 다른 버전의 수는 재생하지 않는다.
    static var rulesVersion: Int { get }
    static func initial() -> State
    static func canApply(_ move: Move, to state: State) -> Bool
    static func apply(_ move: Move, to state: State) -> State
    /// 다음에 둘 좌석. 끝났으면 nil.
    static func currentSeat(_ state: State) -> Int?
    static func outcome(_ state: State) -> Outcome?
}

public extension Game {
    static var rulesVersion: Int { 2 }
}

public struct RulesVersionError: LocalizedError, Equatable, Sendable {
    public let expected: Int
    public let actual: Int

    public var errorDescription: String? {
        "게임 규칙 버전이 달라 이 판을 이어할 수 없습니다. 두 기기 모두 최신 버전으로 업데이트한 뒤 새 방을 만들어 주세요."
    }
}
