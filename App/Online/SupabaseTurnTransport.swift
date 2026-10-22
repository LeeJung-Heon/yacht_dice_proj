import Foundation
import Supabase

/// `matches` 행 하나를 `TurnTransport`로 감싼다.
///
/// 상대 턴은 세 길로 받는다. 상대가 수를 두면 DB를 기다리지 않고 비공개 채널 `match:<id>`에 클라이언트 브로드캐스트
/// `move`로 로그를 먼저 보내고(빠른 길), 이어서 행을 갱신하면 DB 트리거가 같은 채널로 행 전체를 쏘며(Broadcast from Database),
/// iOS가 앱을 뒤로 보내거나 화면을 잠그면 소켓이 끊기고 그 사이의 변경은 다시 오지 않으므로 몇 초마다 행을 직접 읽는 폴링이
/// 항상 같이 돈다. 여러 길이 같은 로그를 거듭 주더라도 `lastSeenCount`로 걸러 한 번만 흘린다.
/// 같은 채널의 Presence로 상대가 붙어 있는지를, 채널 상태로 연결이 살아 있는지를, `live`로 확정 전의 손놀림을 흘린다.
/// 내 갱신이 실패하면 재시도하고, 그래도 안 되면 폴링 주기마다 다시 보낸다. 갱신은 서버의 `event_count`가 더 작을 때만
/// 걸려, 빠른 길로 내 수를 먼저 받은 상대가 그 위에 둔 새 로그를 늦게 도착한 내 옛 갱신이 덮지 못한다.
final class SupabaseTurnTransport: TurnTransport, @unchecked Sendable {
    static let pollInterval: Duration = .seconds(3)

    private let client: SupabaseClient
    private let matchID: UUID
    let incoming: AsyncStream<RemoteUpdate>
    let presence: AsyncStream<Set<String>>
    let connection: AsyncStream<Bool>
    let live: AsyncStream<LiveFrame>
    let reactions: AsyncStream<Reaction>
    private let continuation: AsyncStream<RemoteUpdate>.Continuation
    private let presenceContinuation: AsyncStream<Set<String>>.Continuation
    private let connectionContinuation: AsyncStream<Bool>.Continuation
    private let liveContinuation: AsyncStream<LiveFrame>.Continuation
    private let reactionContinuation: AsyncStream<Reaction>.Continuation
    /// 구독 중인 채널. 빠른 길과 순간 상태는 이 채널이 `subscribed`일 때만 보낸다.
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private let lock = NSLock()
    private var lastSeenCount = 0
    /// presence ref → uid. 같은 uid가 기기 둘로 들어와도 한 사람으로 센다.
    private var present: [String: String] = [:]
    /// 보내지 못한 마지막 갱신. 폴링 주기마다 다시 보낸다.
    private var pending: TurnUpdate?
    /// 구독이나 전송이 실패했을 때의 이유. 진단용.
    private(set) var subscribeError: String?
    private(set) var lastSendError: String?
    /// 채널이 구독된 상태인가. 진단용.
    private(set) var isSubscribed = false
    /// 빠른 길로 들어와 새 것으로 인정된 갱신의 수. 진단용.
    var fastPathDeliveries: Int { lock.withLock { _fastPathDeliveries } }
    private var _fastPathDeliveries = 0
    /// 빠른 길이나 순간 상태를 보내지 못한 이유. 진단용이며, 보내지 못해도 DB 경로가 받친다.
    private(set) var lastBroadcastError: String?

    init(client: SupabaseClient, matchID: UUID, realtimeEnabled: Bool = true) {
        self.client = client
        self.matchID = matchID
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
        // 반응은 쌓아 둘 까닭이 없다 — 조작된 상대가 퍼부어도 최근 몇 개만 남긴다.
        var reactionContinuation: AsyncStream<Reaction>.Continuation!
        reactions = AsyncStream(bufferingPolicy: .bufferingNewest(8)) { reactionContinuation = $0 }
        self.reactionContinuation = reactionContinuation

        if realtimeEnabled {
            listenTask = Task { [weak self] in await self?.listen() }
        } else {
            connectionContinuation.finish()
            presenceContinuation.finish()
            liveContinuation.finish()
            reactionContinuation.finish()
        }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self else { return }
                await self.retryPendingIfAny()
                await self.refresh()
            }
        }
    }

    deinit {
        listenTask?.cancel()
        pollTask?.cancel()
        continuation.finish()
        presenceContinuation.finish()
        connectionContinuation.finish()
        liveContinuation.finish()
        reactionContinuation.finish()
    }

    /// 비공개 채널을 열어 브로드캐스트·Presence·상태를 받는다. 참가자가 아니면 정책이 구독을 거부한다.
    private func listen() async {
        let topic = "match:\(matchID.uuidString.lowercased())"
        guard let session = try? await client.auth.session else {
            subscribeError = "로그인되지 않았다"
            return
        }
        await client.realtimeV2.setAuth(session.accessToken)
        let channel = client.channel(topic) { $0.isPrivate = true }
        let updates = channel.broadcastStream(event: "UPDATE")
        let moves = channel.broadcastStream(event: "move")
        let lives = channel.broadcastStream(event: "live")
        let emojis = channel.broadcastStream(event: "emoji")
        let presences = channel.presenceChange()
        let statuses = channel.statusChange
        lock.withLock { self.channel = channel }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                for await json in updates {
                    guard let self else { return }
                    if let record = json["payload"]?.objectValue?["record"],
                       let row = try? record.decode(as: MatchRow.self, decoder: JSONDecoder()) {
                        self.deliver(RemoteUpdate(log: row.log, eventCount: row.eventCount, hints: row.hints), fastPath: false)
                    }
                }
            }
            group.addTask { [weak self] in
                for await json in moves {
                    guard let self else { return }
                    if let payload = json["payload"],
                       let update = try? payload.decode(as: MoveMessage.self, decoder: JSONDecoder()).remoteUpdate() {
                        self.deliver(update, fastPath: true)
                    }
                }
            }
            group.addTask { [weak self] in
                for await json in lives {
                    guard let self else { return }
                    if let payload = json["payload"],
                       let frame = try? payload.decode(as: LiveMessage.self, decoder: JSONDecoder()).frame() {
                        self.liveContinuation.yield(frame)
                    }
                }
            }
            group.addTask { [weak self] in
                for await json in emojis {
                    guard let self else { return }
                    if let payload = json["payload"],
                       let message = try? payload.decode(as: ReactionMessage.self, decoder: JSONDecoder()) {
                        self.reactionContinuation.yield(message.reaction)
                    }
                }
            }
            group.addTask { [weak self] in
                for await action in presences {
                    guard let self else { return }
                    self.apply(action)
                }
            }
            group.addTask { [weak self] in
                var wasSubscribed = false
                for await status in statuses {
                    guard let self else { return }
                    let subscribed = status == .subscribed
                    self.isSubscribed = subscribed
                    self.connectionContinuation.yield(subscribed)
                    if subscribed {
                        // 다시 붙으면 자기 상태를 올리고 끊긴 사이의 변경을 따라잡는다
                        try? await channel.track(PresenceState(uid: session.user.id.uuidString))
                        if wasSubscribed { await self.refresh() }
                        wasSubscribed = true
                    } else if wasSubscribed {
                        self.lock.withLock { self.present.removeAll() }
                        self.presenceContinuation.yield([])
                    }
                }
            }
            do {
                try await channel.subscribeWithError()
            } catch {
                subscribeError = "\(error)"
                connectionContinuation.yield(false)
                group.cancelAll()
            }
            await group.waitForAll()
        }
        lock.withLock { self.channel = nil }
        await channel.unsubscribe()
    }

    /// 구독 중인 채널. 구독 전이면 SDK가 REST로 대신 보내는 길을 타지 않도록 nil을 준다 — 그때는 DB 경로가 받친다.
    private func subscribedChannel() -> RealtimeChannelV2? {
        guard let channel = lock.withLock({ self.channel }), channel.status == .subscribed else { return nil }
        return channel
    }

    private func apply(_ action: any PresenceAction) {
        let set: Set<String> = lock.withLock {
            for (ref, presence) in action.joins {
                if let state = try? presence.decodeState(as: PresenceState.self) { present[ref] = state.uid }
            }
            for ref in action.leaves.keys { present[ref] = nil }
            return Set(present.values)
        }
        presenceContinuation.yield(set)
    }

    /// 행을 한 번 읽어 새 이벤트가 있으면 흘린다. 앱이 앞으로 돌아왔을 때도 부른다.
    func refresh() async {
        guard let row: MatchRow = try? await client.from("matches").select()
            .eq("id", value: matchID.uuidString).single().execute().value else { return }
        deliver(RemoteUpdate(log: row.log, eventCount: row.eventCount, hints: row.hints), fastPath: false)
    }

    private func deliver(_ update: RemoteUpdate, fastPath: Bool) {
        let isNew: Bool = lock.withLock {
            guard update.eventCount > lastSeenCount else { return false }
            lastSeenCount = update.eventCount
            if fastPath { _fastPathDeliveries += 1 }
            return true
        }
        if isNew { continuation.yield(update) }
    }

    /// 채널로 먼저 보내고 DB를 갱신한다. 채널로 보내지 못해도 DB 경로가 받치므로 이유만 남긴다.
    func publish(_ payload: TurnPayload) async throws {
        if let channel = subscribedChannel() {
            do {
                try await channel.broadcast(event: "move", message: MoveMessage(payload))
            } catch {
                lock.withLock { lastBroadcastError = "\(error)" }
            }
        }
        try await send(TurnUpdate(log: payload.log, hints: payload.hints, eventCount: payload.eventCount,
                                  status: payload.finished ? "finished" : "playing",
                                  turnSeat: payload.turnSeat, winnerSeat: payload.winnerSeat))
    }

    func sendReaction(_ reaction: Reaction) async {
        guard let channel = subscribedChannel() else { return }
        do {
            try await channel.broadcast(event: "emoji", message: ReactionMessage(reaction))
        } catch {
            lock.withLock { lastBroadcastError = "\(error)" }
        }
    }

    func sendLive(_ frame: LiveFrame) async {
        guard let channel = subscribedChannel() else { return }
        do {
            try await channel.broadcast(event: "live", message: LiveMessage(frame))
        } catch {
            lock.withLock { lastBroadcastError = "\(error)" }
        }
    }

    /// 세 번까지 바로 다시 보내고, 그래도 안 되면 보류해 두고 던진다. 보류분은 폴링이 이어서 보낸다.
    /// 보류분은 더 큰 `eventCount`로만 바뀌고, 성공한 갱신은 그보다 크지 않은 보류분만 지운다 — 앞서 실패한 옛 갱신이
    /// 뒤에 성공한 새 갱신의 보류를 지우거나 덮지 않게 하기 위해서다.
    ///
    /// 다만 서버가 판단해 되돌려보낸 거절(`PostgrestError`)은 다시 보내도 결과가 같다 — 끝난 매치를
    /// 고치려 하거나 정책에 막힌 갱신은 트리거·RLS가 언제 보내도 같은 오류를 낸다. 그런 응답은 한 번에
    /// 접어 이유만 남기고 던지며, 보류에도 넣지 않아 폴링이 3초마다 같은 오류를 되풀이하지 않게 한다.
    /// 망이 끊겨 응답조차 못 받은 오류만 재시도와 보류의 대상이다.
    private func send(_ update: TurnUpdate) async throws {
        lock.withLock { lastSeenCount = max(lastSeenCount, update.eventCount) }
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                try await conditionalUpdate(update)
                lock.withLock { clearPending(upTo: update.eventCount); lastSendError = nil }
                return
            } catch {
                if error is PostgrestError {
                    lock.withLock { lastSendError = "\(error)" }
                    throw error
                }
                lastError = error
                try? await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
            }
        }
        lock.withLock {
            if (pending?.eventCount ?? -1) < update.eventCount { pending = update }
            lastSendError = "\(lastError!)"
        }
        throw lastError!
    }

    /// 서버의 `event_count`가 보낼 값보다 작을 때만 고친다. 이미 같거나 더 새 로그면 아무 행도 바뀌지 않고 성공한다.
    private func conditionalUpdate(_ update: TurnUpdate) async throws {
        try await client.from("matches").update(update)
            .eq("id", value: matchID.uuidString).lt("event_count", value: update.eventCount).execute()
    }

    /// 잠금 안에서 부른다.
    private func clearPending(upTo eventCount: Int) {
        if let pending, pending.eventCount <= eventCount { self.pending = nil }
    }

    private func retryPendingIfAny() async {
        guard let update = lock.withLock({ pending }) else { return }
        if (try? await conditionalUpdate(update)) != nil {
            lock.withLock { clearPending(upTo: update.eventCount); lastSendError = nil }
        }
    }

    private struct PresenceState: Codable {
        let uid: String
    }

    private struct TurnUpdate: Encodable {
        let log: Data
        let hints: [ThrowHint]
        let eventCount: Int
        let status: String
        let turnSeat: Int?
        let winnerSeat: Int?
        enum CodingKeys: String, CodingKey {
            case log, status
            case hints = "throws"
            case eventCount = "event_count"
            case turnSeat = "turn_seat"
            case winnerSeat = "winner_seat"
        }
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(JSONDecoder().decode(JSONValue.self, from: log), forKey: .log)
            try container.encode(hints, forKey: .hints)
            try container.encode(eventCount, forKey: .eventCount)
            try container.encode(status, forKey: .status)
            try container.encode(turnSeat, forKey: .turnSeat)   // nil이면 null로 지운다
            try container.encode(winnerSeat, forKey: .winnerSeat)
        }
    }
}
