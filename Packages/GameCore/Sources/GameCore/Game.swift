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
    static func initial() -> State
    static func canApply(_ move: Move, to state: State) -> Bool
    static func apply(_ move: Move, to state: State) -> State
    /// 다음에 둘 좌석. 끝났으면 nil.
    static func currentSeat(_ state: State) -> Int?
    static func outcome(_ state: State) -> Outcome?
}
