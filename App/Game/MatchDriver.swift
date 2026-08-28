import Foundation
import YachtCore

/// 눈의 출처와 상대 행동의 통로. P2는 AIDriver, P3는 OnlineDriver를 여기 끼운다.
/// 이 프로토콜이 있으면 뷰와 코어는 온라인 대전이 붙어도 바뀌지 않는다.
protocol MatchDriver: Sendable {
    func requestRoll(count: Int) async throws -> [Int]
    func submit(_ event: Event) async throws
    var incoming: AsyncStream<Event> { get }
}

/// P1의 유일한 드라이버. 눈을 로컬에서 굴린다.
struct LocalDriver: MatchDriver {
    func requestRoll(count: Int) async throws -> [Int] {
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in Int.random(in: 1...6, using: &generator) }
    }

    func submit(_ event: Event) async throws {}

    /// 로컬 게임에는 상대가 없다.
    var incoming: AsyncStream<Event> { AsyncStream { $0.finish() } }
}
