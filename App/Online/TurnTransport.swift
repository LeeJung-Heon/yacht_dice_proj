import Foundation
import YachtCore

/// 온라인 대전의 전송 계층. 매치 데이터는 `MatchLog` 그대로다 — 이벤트 소싱이라 로그가 곧 상태다.
///
/// `GameSession`은 이 프로토콜만 안다. Game Center 어댑터는 `App/Online`에, 테스트는 메모리 쌍을 쓴다.
protocol TurnTransport: Sendable {
    /// 내 턴 도중 이벤트가 하나 생겼다(굴림·고정). 상대가 실시간으로 보도록 로그를 올리되 차례는 넘기지 않는다.
    func publishProgress(log: MatchLog) async throws
    /// 내 턴이 끝났다. 전체 로그를 올리고 다음 참가자에게 넘긴다.
    func endTurn(log: MatchLog) async throws
    /// 게임이 끝났다. 결과를 올린다. `totals[i]`는 좌석 i의 총점.
    func endMatch(log: MatchLog, totals: [Int]) async throws
    /// 상대 턴이 끝나 새 로그가 도착하면 흐른다.
    var incomingLogs: AsyncStream<MatchLog> { get }
    /// 지금 서버 상태를 한 번 읽어 새 이벤트가 있으면 `incomingLogs`로 흘린다. 앱이 앞으로 돌아왔을 때 부른다.
    func refresh() async
}

extension TurnTransport {
    func refresh() async {}
}

/// 같은 프로세스 안의 두 세션을 잇는다. 테스트와 디버깅용.
final class InMemoryTurnTransport: TurnTransport, @unchecked Sendable {
    private let lock = NSLock()
    private weak var peer: InMemoryTurnTransport?
    private var continuation: AsyncStream<MatchLog>.Continuation?
    let incomingLogs: AsyncStream<MatchLog>
    private var _sentLogs: [MatchLog] = []
    private var _finishedTotals: [Int]?

    var sentLogs: [MatchLog] { lock.withLock { _sentLogs } }
    var finishedTotals: [Int]? { lock.withLock { _finishedTotals } }

    private init() {
        var continuation: AsyncStream<MatchLog>.Continuation!
        incomingLogs = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation
    }

    static func pair() -> (InMemoryTurnTransport, InMemoryTurnTransport) {
        let a = InMemoryTurnTransport(), b = InMemoryTurnTransport()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    func publishProgress(log: MatchLog) async throws {
        lock.withLock { _sentLogs.append(log) }
        peer?.continuation?.yield(log)
    }

    func endTurn(log: MatchLog) async throws {
        lock.withLock { _sentLogs.append(log) }
        peer?.continuation?.yield(log)
    }

    func endMatch(log: MatchLog, totals: [Int]) async throws {
        lock.withLock {
            _sentLogs.append(log)
            _finishedTotals = totals
        }
        peer?.continuation?.yield(log)
    }
}
