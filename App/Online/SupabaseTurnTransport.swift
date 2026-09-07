import Foundation
import Supabase
import YachtCore

/// `matches` 행 하나를 `TurnTransport`로 감싼다. 내 턴이 끝나면 행을 갱신하고,
/// 상대 턴은 Realtime Postgres Changes로 그 행의 UPDATE를 받아 흘린다.
final class SupabaseTurnTransport: TurnTransport, @unchecked Sendable {
    private let client: SupabaseClient
    private let matchID: UUID
    let incomingLogs: AsyncStream<MatchLog>
    private let continuation: AsyncStream<MatchLog>.Continuation
    private var listenTask: Task<Void, Never>?
    /// 구독이 실패했을 때의 이유. 진단용.
    private(set) var subscribeError: String?

    init(client: SupabaseClient, matchID: UUID) {
        self.client = client
        self.matchID = matchID
        var continuation: AsyncStream<MatchLog>.Continuation!
        incomingLogs = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation
        // 필터 값은 소문자 uuid여야 한다 — Realtime은 WAL의 텍스트 값과 문자열로 비교한다.
        let idText = matchID.uuidString.lowercased()
        listenTask = Task { [client, continuation, weak self] in
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
                do {
                    let row = try update.decodeRecord(as: MatchRow.self, decoder: JSONDecoder())
                    continuation!.yield(row.log)
                } catch {
                    self?.subscribeError = "decode: \(error)"
                }
            }
        }
    }

    deinit {
        listenTask?.cancel()
        continuation.finish()
    }

    func endTurn(log: MatchLog) async throws {
        try await client.from("matches")
            .update(TurnUpdate(log: log, eventCount: log.events.count, status: "playing", totals: nil))
            .eq("id", value: matchID.uuidString)
            .execute()
    }

    func endMatch(log: MatchLog, totals: [Int]) async throws {
        try await client.from("matches")
            .update(TurnUpdate(log: log, eventCount: log.events.count, status: "finished", totals: totals))
            .eq("id", value: matchID.uuidString)
            .execute()
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
