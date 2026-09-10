import Foundation
import Supabase

/// `matches` 행 하나를 `TurnTransport`로 감싼다.
///
/// 상대 턴은 두 길로 받는다. 행이 바뀌면 DB 트리거가 비공개 채널 `match:<id>`로 행 전체를 쏘고(Broadcast from Database),
/// iOS가 앱을 뒤로 보내거나 화면을 잠그면 소켓이 끊기고 그 사이의 변경은 다시 오지 않으므로 몇 초마다 행을 직접 읽는 폴링이
/// 항상 같이 돈다. 두 길이 같은 로그를 두 번 주더라도 `lastSeenCount`로 걸러 한 번만 흘린다.
/// 같은 채널의 Presence로 상대가 붙어 있는지를, 채널 상태로 연결이 살아 있는지를 흘린다.
/// 내 갱신이 실패하면 재시도하고, 그래도 안 되면 폴링 주기마다 다시 보낸다.
final class SupabaseTurnTransport: TurnTransport, @unchecked Sendable {
    static let pollInterval: Duration = .seconds(3)

    private let client: SupabaseClient
    private let matchID: UUID
    let incoming: AsyncStream<RemoteUpdate>
    let presence: AsyncStream<Set<String>>
    let connection: AsyncStream<Bool>
    private let continuation: AsyncStream<RemoteUpdate>.Continuation
    private let presenceContinuation: AsyncStream<Set<String>>.Continuation
    private let connectionContinuation: AsyncStream<Bool>.Continuation
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

        if realtimeEnabled {
            listenTask = Task { [weak self] in await self?.listen() }
        } else {
            connectionContinuation.finish()
            presenceContinuation.finish()
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
        let presences = channel.presenceChange()
        let statuses = channel.statusChange

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                for await json in updates {
                    guard let self else { return }
                    if let record = json["payload"]?.objectValue?["record"],
                       let row = try? record.decode(as: MatchRow.self, decoder: JSONDecoder()) {
                        self.deliver(row)
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
        await channel.unsubscribe()
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
        deliver(row)
    }

    private func deliver(_ row: MatchRow) {
        let isNew: Bool = lock.withLock {
            guard row.eventCount > lastSeenCount else { return false }
            lastSeenCount = row.eventCount
            return true
        }
        if isNew { continuation.yield(RemoteUpdate(log: row.log, eventCount: row.eventCount, hints: row.hints)) }
    }

    func publish(_ payload: TurnPayload) async throws {
        try await send(TurnUpdate(log: payload.log, hints: payload.hints, eventCount: payload.eventCount,
                                  status: payload.finished ? "finished" : "playing",
                                  turnSeat: payload.turnSeat, winnerSeat: payload.winnerSeat))
    }

    /// 세 번까지 바로 다시 보내고, 그래도 안 되면 보류해 두고 던진다. 보류분은 폴링이 이어서 보낸다.
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
                try await client.from("matches").update(update).eq("id", value: matchID.uuidString).execute()
                lock.withLock { pending = nil; lastSendError = nil }
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
        lock.withLock { pending = update; lastSendError = "\(lastError!)" }
        throw lastError!
    }

    private func retryPendingIfAny() async {
        guard let update = lock.withLock({ pending }) else { return }
        if (try? await client.from("matches").update(update).eq("id", value: matchID.uuidString).execute()) != nil {
            lock.withLock { pending = nil; lastSendError = nil }
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
