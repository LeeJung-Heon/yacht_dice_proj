import Foundation

/// 내가 서버에 올리는 것. 로그는 게임별 JSON 원문이라 전송은 게임을 모른다.
struct TurnPayload: Sendable, Equatable {
    let log: Data
    /// 로그 안의 수·이벤트 개수. 서버 `event_count`이며 상대는 이 값으로 새 것을 가린다.
    let eventCount: Int
    let hints: [ThrowHint]
    /// 다음에 둘 좌석. 끝났으면 nil. 바뀌면 서버가 그 좌석에게 푸시를 보낸다.
    let turnSeat: Int?
    /// 끝났을 때의 승자. 무승부나 진행 중이면 nil.
    let winnerSeat: Int?
    let finished: Bool
}

/// 상대에게서 온 것.
struct RemoteUpdate: Sendable, Equatable {
    let log: Data
    let eventCount: Int
    let hints: [ThrowHint]
}

/// 온라인 대전의 전송 계층. `GameSession`(요트)과 `OnlineMatch<G>`(그 외)가 같은 것을 쓴다.
protocol TurnTransport: Sendable {
    /// 로그를 올린다. 턴 도중·턴 끝·게임 끝을 payload의 turnSeat·finished가 구분한다.
    func publish(_ payload: TurnPayload) async throws
    var incoming: AsyncStream<RemoteUpdate> { get }
    /// 채널에 함께 있는 참가자의 uid 집합. 기본은 빈 스트림.
    var presence: AsyncStream<Set<String>> { get }
    /// 채널이 구독된 상태인가. 기본은 빈 스트림(항상 연결된 것으로 본다).
    var connection: AsyncStream<Bool> { get }
    /// 서버 상태를 한 번 읽어 새 것이 있으면 `incoming`으로 흘린다.
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
    private var _sent: [TurnPayload] = []

    var sent: [TurnPayload] { lock.withLock { _sent } }
    var sentLogs: [Data] { sent.map(\.log) }
    var lastPayload: TurnPayload? { sent.last }

    private init() {
        var continuation: AsyncStream<RemoteUpdate>.Continuation!
        incoming = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation
        var presenceContinuation: AsyncStream<Set<String>>.Continuation!
        presence = AsyncStream(bufferingPolicy: .unbounded) { presenceContinuation = $0 }
        self.presenceContinuation = presenceContinuation
    }

    static func pair(uidA: String = "a", uidB: String = "b") -> (InMemoryTurnTransport, InMemoryTurnTransport) {
        let a = InMemoryTurnTransport(), b = InMemoryTurnTransport()
        a.peer = b
        b.peer = a
        a.presenceContinuation?.yield([uidB])
        b.presenceContinuation?.yield([uidA])
        return (a, b)
    }

    func publish(_ payload: TurnPayload) async throws {
        lock.withLock { _sent.append(payload) }
        peer?.continuation?.yield(RemoteUpdate(log: payload.log, eventCount: payload.eventCount, hints: payload.hints))
    }
}
