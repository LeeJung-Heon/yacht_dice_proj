import Foundation
import Supabase
import YachtCore

/// `matches` 행 하나를 `TurnTransport`로 감싼다.
///
/// 상대 턴은 두 길로 받는다. Realtime Postgres Changes가 빠르지만 iOS가 앱을 뒤로 보내거나 화면을 잠그면
/// 소켓이 끊기고 그 사이의 변경은 다시 오지 않으므로, 몇 초마다 행을 직접 읽는 폴링이 항상 같이 돈다.
/// 두 길이 같은 로그를 두 번 주더라도 `lastSeenCount`로 걸러 한 번만 흘린다.
/// 내 갱신이 실패하면 재시도하고, 그래도 안 되면 폴링 주기마다 다시 보낸다.
final class SupabaseTurnTransport: TurnTransport, @unchecked Sendable {
    static let pollInterval: Duration = .seconds(3)

    private let client: SupabaseClient
    private let matchID: UUID
    let incomingLogs: AsyncStream<MatchLog>
    private let continuation: AsyncStream<MatchLog>.Continuation
    private var listenTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private let lock = NSLock()
    private var lastSeenCount = 0
    /// 보내지 못한 마지막 갱신. 폴링 주기마다 다시 보낸다.
    private var pending: TurnUpdate?
    /// 구독이나 전송이 실패했을 때의 이유. 진단용.
    private(set) var subscribeError: String?
    private(set) var lastSendError: String?

    init(client: SupabaseClient, matchID: UUID, realtimeEnabled: Bool = true) {
        self.client = client
        self.matchID = matchID
        var continuation: AsyncStream<MatchLog>.Continuation!
        incomingLogs = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation

        if realtimeEnabled {
            // 필터 값은 소문자 uuid여야 한다 — Realtime은 WAL의 텍스트 값과 문자열로 비교한다.
            let idText = matchID.uuidString.lowercased()
            listenTask = Task { [client, weak self] in
                let channel = client.channel("match-\(idText)")
                let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "matches",
                                                     filter: "id=eq.\(idText)")
                do {
                    try await channel.subscribeWithError()
                } catch {
                    self?.subscribeError = "\(error)"
                    return
                }
                for await update in updates {
                    guard let self else { return }
                    if let row = try? update.decodeRecord(as: MatchRow.self, decoder: JSONDecoder()) {
                        self.deliver(row.log)
                    }
                }
            }
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
    }

    /// 행을 한 번 읽어 새 이벤트가 있으면 흘린다. 앱이 앞으로 돌아왔을 때도 부른다.
    func refresh() async {
        guard let row: MatchRow = try? await client.from("matches").select()
            .eq("id", value: matchID.uuidString).single().execute().value else { return }
        deliver(row.log)
    }

    private func deliver(_ log: MatchLog) {
        let isNew: Bool = lock.withLock {
            guard log.events.count > lastSeenCount else { return false }
            lastSeenCount = log.events.count
            return true
        }
        if isNew { continuation.yield(log) }
    }

    /// 턴 도중에도 같은 행을 갱신한다. 상대는 Realtime이나 폴링으로 굴림 하나하나를 받아 재생한다.
    func publishProgress(log: MatchLog) async throws {
        try await send(TurnUpdate(log: log, eventCount: log.events.count, status: "playing", totals: nil))
    }

    func endTurn(log: MatchLog) async throws {
        try await send(TurnUpdate(log: log, eventCount: log.events.count, status: "playing", totals: nil))
    }

    func endMatch(log: MatchLog, totals: [Int]) async throws {
        try await send(TurnUpdate(log: log, eventCount: log.events.count, status: "finished", totals: totals))
    }

    /// 세 번까지 바로 다시 보내고, 그래도 안 되면 보류해 두고 던진다. 보류분은 폴링이 이어서 보낸다.
    private func send(_ update: TurnUpdate) async throws {
        lock.withLock { lastSeenCount = max(lastSeenCount, update.eventCount) }
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                try await client.from("matches").update(update).eq("id", value: matchID.uuidString).execute()
                lock.withLock { pending = nil; lastSendError = nil }
                return
            } catch {
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

    private struct TurnUpdate: Encodable {
        let log: MatchLog
        let eventCount: Int
        let status: String
        let totals: [Int]?
        enum CodingKeys: String, CodingKey {
            case log, status, totals
            case eventCount = "event_count"
        }
    }
}
