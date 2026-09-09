import Foundation
import YachtCore

/// 상대에게서 온 것. 로그와, 그 로그의 굴림들을 같은 던지기로 보여 주기 위한 힌트.
struct RemoteUpdate: Sendable, Equatable {
    let log: MatchLog
    let hints: [ThrowHint]
}

/// 온라인 대전의 전송 계층. 매치 데이터는 `MatchLog` 그대로다 — 이벤트 소싱이라 로그가 곧 상태다.
///
/// `GameSession`은 이 프로토콜만 안다. Supabase 어댑터는 `App/Online`에, 테스트는 메모리 쌍을 쓴다.
protocol TurnTransport: Sendable {
    /// 내 턴 도중 이벤트가 하나 생겼다(굴림·고정). 상대가 실시간으로 보도록 로그를 올리되 차례는 넘기지 않는다.
    func publishProgress(log: MatchLog, hints: [ThrowHint]) async throws
    /// 내 턴이 끝났다. 전체 로그를 올리고 다음 좌석에게 넘긴다.
    func endTurn(log: MatchLog, hints: [ThrowHint], nextSeat: Int) async throws
    /// 게임이 끝났다. 결과를 올린다. `totals[i]`는 좌석 i의 총점.
    func endMatch(log: MatchLog, hints: [ThrowHint], totals: [Int]) async throws
    /// 상대의 새 로그가 도착하면 흐른다.
    var incoming: AsyncStream<RemoteUpdate> { get }
    /// 채널에 함께 있는 참가자의 uid 집합. 기본은 빈 스트림.
    var presence: AsyncStream<Set<String>> { get }
    /// 채널이 구독된 상태인가. 기본은 빈 스트림(항상 연결된 것으로 본다).
    var connection: AsyncStream<Bool> { get }
    /// 지금 서버 상태를 한 번 읽어 새 이벤트가 있으면 `incoming`으로 흘린다. 앱이 앞으로 돌아왔을 때 부른다.
    func refresh() async
}

extension TurnTransport {
    var presence: AsyncStream<Set<String>> { AsyncStream { $0.finish() } }
    var connection: AsyncStream<Bool> { AsyncStream { $0.finish() } }
    func refresh() async {}
}

/// 같은 프로세스 안의 두 세션을 잇는다. 테스트와 디버깅용.
final class InMemoryTurnTransport: TurnTransport, @unchecked Sendable {
    private let lock = NSLock()
    private weak var peer: InMemoryTurnTransport?
    private var continuation: AsyncStream<RemoteUpdate>.Continuation?
    private var presenceContinuation: AsyncStream<Set<String>>.Continuation?
    let incoming: AsyncStream<RemoteUpdate>
    let presence: AsyncStream<Set<String>>
    private var _sent: [RemoteUpdate] = []
    private var _finishedTotals: [Int]?
    private var _lastNextSeat: Int?

    var sent: [RemoteUpdate] { lock.withLock { _sent } }
    var sentLogs: [MatchLog] { sent.map(\.log) }
    var finishedTotals: [Int]? { lock.withLock { _finishedTotals } }
    var lastNextSeat: Int? { lock.withLock { _lastNextSeat } }

    private init() {
        var continuation: AsyncStream<RemoteUpdate>.Continuation!
        incoming = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation
        var presenceContinuation: AsyncStream<Set<String>>.Continuation!
        presence = AsyncStream(bufferingPolicy: .unbounded) { presenceContinuation = $0 }
        self.presenceContinuation = presenceContinuation
    }

    /// 두 전송을 잇고 서로의 uid를 presence로 흘린다. a는 b가, b는 a가 함께 있는 것으로 본다.
    static func pair(uidA: String = "a", uidB: String = "b") -> (InMemoryTurnTransport, InMemoryTurnTransport) {
        let a = InMemoryTurnTransport(), b = InMemoryTurnTransport()
        a.peer = b
        b.peer = a
        a.presenceContinuation?.yield([uidB])
        b.presenceContinuation?.yield([uidA])
        return (a, b)
    }

    func publishProgress(log: MatchLog, hints: [ThrowHint]) async throws {
        forward(RemoteUpdate(log: log, hints: hints))
    }

    func endTurn(log: MatchLog, hints: [ThrowHint], nextSeat: Int) async throws {
        lock.withLock { _lastNextSeat = nextSeat }
        forward(RemoteUpdate(log: log, hints: hints))
    }

    func endMatch(log: MatchLog, hints: [ThrowHint], totals: [Int]) async throws {
        lock.withLock { _finishedTotals = totals }
        forward(RemoteUpdate(log: log, hints: hints))
    }

    private func forward(_ update: RemoteUpdate) {
        lock.withLock { _sent.append(update) }
        peer?.continuation?.yield(update)
    }
}
