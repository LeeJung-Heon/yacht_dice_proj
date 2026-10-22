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

/// 게임 중에 보내는 이모지 반응. 저장하지 않으며 놓쳐도 판에 영향이 없다.
struct Reaction: Sendable, Equatable {
    let emoji: String
    /// 보낸 순간 보낸 사람 로그의 수·이벤트 개수. 배지를 지울 때를 두 화면이 같게 정한다.
    let eventCount: Int
}

/// 확정 전의 손놀림 한 장. 저장하지 않으며 놓쳐도 판에 영향이 없다.
struct LiveFrame: Sendable, Equatable {
    /// 보낸 쪽 로그의 수·이벤트 개수. 받는 쪽은 자기 것과 같을 때만 그린다.
    let eventCount: Int
    /// 게임별 JSON. nil이면 손을 뗐다는 뜻이다.
    let state: Data?
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
    /// 확정 전의 손놀림을 상대에게 흘린다. 기본은 아무것도 하지 않는다.
    func sendLive(_ frame: LiveFrame) async
    /// 상대의 손놀림. 기본은 빈 스트림.
    var live: AsyncStream<LiveFrame> { get }
    /// 이모지 반응을 상대에게 보낸다. 기본은 아무것도 하지 않는다.
    func sendReaction(_ reaction: Reaction) async
    /// 상대의 이모지 반응. 기본은 빈 스트림.
    var reactions: AsyncStream<Reaction> { get }
}

extension TurnTransport {
    var presence: AsyncStream<Set<String>> { AsyncStream { $0.finish() } }
    var connection: AsyncStream<Bool> { AsyncStream { $0.finish() } }
    func refresh() async {}
    func sendLive(_ frame: LiveFrame) async {}
    var live: AsyncStream<LiveFrame> { AsyncStream { $0.finish() } }
    func sendReaction(_ reaction: Reaction) async {}
    var reactions: AsyncStream<Reaction> { AsyncStream { $0.finish() } }
}

/// 같은 프로세스 안의 두 세션을 잇는다. 테스트와 디버깅용.
final class InMemoryTurnTransport: TurnTransport, @unchecked Sendable {
    private let lock = NSLock()
    private weak var peer: InMemoryTurnTransport?
    private var continuation: AsyncStream<RemoteUpdate>.Continuation?
    private var presenceContinuation: AsyncStream<Set<String>>.Continuation?
    private var connectionContinuation: AsyncStream<Bool>.Continuation?
    private var liveContinuation: AsyncStream<LiveFrame>.Continuation?
    private var reactionContinuation: AsyncStream<Reaction>.Continuation?
    let incoming: AsyncStream<RemoteUpdate>
    let presence: AsyncStream<Set<String>>
    let connection: AsyncStream<Bool>
    let live: AsyncStream<LiveFrame>
    let reactions: AsyncStream<Reaction>
    private var _sent: [TurnPayload] = []
    private var _sentLive: [LiveFrame] = []
    private var _sentReactions: [Reaction] = []

    var sent: [TurnPayload] { lock.withLock { _sent } }
    var sentLive: [LiveFrame] { lock.withLock { _sentLive } }
    var sentReactions: [Reaction] { lock.withLock { _sentReactions } }
    var sentLogs: [Data] { sent.map(\.log) }
    var lastPayload: TurnPayload? { sent.last }

    private init() {
        var continuation: AsyncStream<RemoteUpdate>.Continuation!
        incoming = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation
        var presenceContinuation: AsyncStream<Set<String>>.Continuation!
        presence = AsyncStream(bufferingPolicy: .unbounded) { presenceContinuation = $0 }
        self.presenceContinuation = presenceContinuation
        var connectionContinuation: AsyncStream<Bool>.Continuation!
        connection = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { connectionContinuation = $0 }
        self.connectionContinuation = connectionContinuation
        var liveContinuation: AsyncStream<LiveFrame>.Continuation!
        live = AsyncStream(bufferingPolicy: .unbounded) { liveContinuation = $0 }
        self.liveContinuation = liveContinuation
        var reactionContinuation: AsyncStream<Reaction>.Continuation!
        reactions = AsyncStream(bufferingPolicy: .unbounded) { reactionContinuation = $0 }
        self.reactionContinuation = reactionContinuation
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

    func sendLive(_ frame: LiveFrame) async {
        lock.withLock { _sentLive.append(frame) }
        peer?.liveContinuation?.yield(frame)
    }

    func sendReaction(_ reaction: Reaction) async {
        lock.withLock { _sentReactions.append(reaction) }
        peer?.reactionContinuation?.yield(reaction)
    }

    /// 테스트용: 이 쪽이 보는 채널 참가자를 바꾼다.
    func emitPresence(_ uids: Set<String>) { presenceContinuation?.yield(uids) }
    /// 테스트용: 이 쪽의 연결 상태를 바꾼다.
    func emitConnection(_ connected: Bool) { connectionContinuation?.yield(connected) }
}
