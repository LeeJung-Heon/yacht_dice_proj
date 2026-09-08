import Testing
import Foundation
import Supabase
import YachtCore
import DiceTrajectory
@testable import YachtDice

/// 실제 Supabase 프로젝트를 상대로 방 만들기 → 들어가기 → 턴 전송 → Realtime 수신을 검증한다.
/// 네트워크와 익명 로그인 설정이 필요하므로 `YACHT_SUPABASE_E2E=1`일 때만 돈다.
@Suite("Supabase 통합 (네트워크)", .enabled(if: ProcessInfo.processInfo.environment["YACHT_SUPABASE_E2E"] == "1"))
@MainActor
struct SupabaseE2ETests {

    /// 한 프로세스에서 익명 계정 둘을 쓰기 위한 메모리 세션 저장소.
    final class MemoryStorage: AuthLocalStorage, @unchecked Sendable {
        private var values: [String: Data] = [:]
        func store(key: String, value: Data) throws { values[key] = value }
        func retrieve(key: String) throws -> Data? { values[key] }
        func remove(key: String) throws { values[key] = nil }
    }

    private func makeClient() -> SupabaseClient {
        SupabaseClient(supabaseURL: SupabaseConfig.url, supabaseKey: SupabaseConfig.publishableKey,
                       options: .init(auth: .init(storage: MemoryStorage())))
    }

    private struct ConstantDriver: MatchDriver {
        let face: Int
        func requestRoll(count: Int) async throws -> [Int] { Array(repeating: face, count: count) }
        func submit(_ event: Event) async throws {}
        var incoming: AsyncStream<Event> { AsyncStream { $0.finish() } }
    }

    @Test("호스트가 방을 만들고 게스트가 들어가 한 턴씩 주고받는다")
    func 한_판_시작() async throws {
        let host = SupabaseService(client: makeClient())
        let guest = SupabaseService(client: makeClient())
        await host.signIn()
        await guest.signIn()
        let hostUid = try #require(host.uid)
        let guestUid = try #require(guest.uid)
        #expect(hostUid != guestUid)

        let room = try await host.createRoom(name: "A")
        #expect(room.isWaiting && MatchRow.isValidCode(room.code))

        let joined = try await guest.joinRoom(code: room.code, name: "B")
        #expect(joined.status == "playing" && joined.guestUid == guestUid)

        // 호스트 쪽에서 방을 다시 읽으면 게스트가 보인다
        let refreshed = try await host.fetchMatch(id: room.id)
        #expect(refreshed.guestUid == guestUid)

        // 두 세션을 만든다. 호스트는 좌석 0, 게스트는 좌석 1.
        let library = try TrajectoryLibrary.bundled()
        let hostRecord = try #require(refreshed.record(localUid: hostUid))
        let guestRecord = try #require(joined.record(localUid: guestUid))
        let hostTransport = SupabaseTurnTransport(client: host.client, matchID: room.id)
        let guestTransport = SupabaseTurnTransport(client: guest.client, matchID: room.id)
        let hostSession = GameSession(driver: ConstantDriver(face: 3), stage: DiceStage(library: library),
                                      record: hostRecord, transport: hostTransport)
        let guestSession = GameSession(driver: ConstantDriver(face: 5), stage: DiceStage(library: library),
                                       record: guestRecord, transport: guestTransport)
        hostSession.reduceMotion = true
        guestSession.reduceMotion = true
        hostSession.startListening()
        guestSession.startListening()
        try await Task.sleep(for: .seconds(2))   // Realtime 구독이 붙을 시간

        #expect(hostSession.isLocalTurn && !guestSession.isLocalTurn)
        await hostSession.send(.roll)

        // 턴이 끝나기 전에도 게스트 화면에 굴림이 도착한다
        let midDeadline = ContinuousClock.now + .seconds(15)
        while guestSession.visibleState.rollsRemaining != 2, ContinuousClock.now < midDeadline {
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(guestSession.visibleState.dice == hostSession.visibleState.dice,
                "호스트의 첫 굴림이 실시간으로 오지 않았다. 구독 오류: \(guestTransport.subscribeError ?? "없음")")
        #expect(!guestSession.isLocalTurn)

        await hostSession.send(.commit(.threes))

        // 게스트가 Realtime으로 받는다
        let deadline = ContinuousClock.now + .seconds(15)
        while guestSession.visibleState.currentPlayer != 1, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(guestSession.visibleState.scorecards[0].entry(.threes) == 15,
                "게스트가 호스트의 턴을 받지 못했다. 구독 오류: \(guestTransport.subscribeError ?? "없음"), 세션 오류: \(guestSession.lastTransportError ?? "없음")")
        #expect(guestSession.isLocalTurn)

        await guestSession.send(.roll)
        await guestSession.send(.commit(.fives))
        let deadline2 = ContinuousClock.now + .seconds(15)
        while hostSession.visibleState.currentPlayer != 0 || hostSession.visibleState.turnIndex != 2,
              ContinuousClock.now < deadline2 {
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(hostSession.visibleState.scorecards[1].entry(.fives) == 25, "호스트가 게스트의 턴을 받지 못했다")
        #expect(hostSession.isLocalTurn)

        // 서버 행도 같은 로그를 갖는다
        let final = try await host.fetchMatch(id: room.id)
        #expect(final.log == hostSession.record.log)
        #expect(final.eventCount == hostSession.record.log.events.count)
    }

    @Test("Realtime 없이 폴링만으로도 상대의 턴이 도착한다")
    func 폴링_전달() async throws {
        let host = SupabaseService(client: makeClient())
        let guest = SupabaseService(client: makeClient())
        await host.signIn(); await guest.signIn()
        let room = try await host.createRoom(name: "A")
        let joined = try await guest.joinRoom(code: room.code, name: "B")
        let refreshed = try await host.fetchMatch(id: room.id)
        let library = try TrajectoryLibrary.bundled()
        let hostUid = try #require(host.uid)
        let guestUid = try #require(guest.uid)
        let hostRecord = try #require(refreshed.record(localUid: hostUid))
        let guestRecord = try #require(joined.record(localUid: guestUid))
        let hostSession = GameSession(driver: ConstantDriver(face: 3), stage: DiceStage(library: library),
                                      record: hostRecord,
                                      transport: SupabaseTurnTransport(client: host.client, matchID: room.id))
        // 게스트는 Realtime을 끄고 폴링만 쓴다
        let guestSession = GameSession(driver: ConstantDriver(face: 5), stage: DiceStage(library: library),
                                       record: guestRecord,
                                       transport: SupabaseTurnTransport(client: guest.client, matchID: room.id, realtimeEnabled: false))
        hostSession.reduceMotion = true; guestSession.reduceMotion = true
        hostSession.startListening(); guestSession.startListening()
        await hostSession.send(.roll)
        await hostSession.send(.commit(.threes))
        let deadline = ContinuousClock.now + .seconds(12)
        while !guestSession.isLocalTurn, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
        }
        #expect(guestSession.visibleState.scorecards[0].entry(.threes) == 15, "폴링으로 상대 턴이 오지 않았다")
        #expect(guestSession.isLocalTurn)
    }

    @Test("방을 두 번 만들면 대기 방은 마지막 하나만 남고, 닫으면 사라진다")
    func 대기_방_하나() async throws {
        let host = SupabaseService(client: makeClient())
        await host.signIn()
        let first = try await host.createRoom(name: "A")
        let second = try await host.createRoom(name: "A")
        #expect(first.id != second.id)
        await host.reloadMatches()
        let waiting = host.myMatches.filter(\.isWaiting)
        #expect(waiting.map(\.id) == [second.id], "대기 방이 하나가 아니다: \(waiting.map(\.code))")
        try await host.deleteMatch(id: second.id)
        await host.reloadMatches()
        #expect(host.myMatches.filter(\.isWaiting).isEmpty)
    }

    @Test("이미 찬 방이나 없는 코드는 들어갈 수 없다")
    func 입장_거부() async throws {
        let guest = SupabaseService(client: makeClient())
        await guest.signIn()
        await #expect(throws: (any Error).self) {
            _ = try await guest.joinRoom(code: "000000", name: "B")
        }
    }
}
