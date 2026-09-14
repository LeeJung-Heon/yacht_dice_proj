import Testing
import Foundation
import Supabase
import YachtCore
import DiceTrajectory
import GameCore
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

    private func makeClient(maxRetryAttempts: Int = RealtimeClientOptions.defaultMaxRetryAttempts) -> SupabaseClient {
        SupabaseClient(supabaseURL: SupabaseConfig.url, supabaseKey: SupabaseConfig.publishableKey,
                       options: .init(auth: .init(storage: MemoryStorage()),
                                      realtime: .init(maxRetryAttempts: maxRetryAttempts)))
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
        #expect(try #require(final.yachtLog()) == hostSession.record.log)
        #expect(final.eventCount == hostSession.record.log.events.count)
    }

    /// 호스트·게스트 세션 한 쌍을 만들어 구독이 붙을 때까지 기다린다.
    private func makePair(realtimeForGuest: Bool = true) async throws
        -> (host: SupabaseService, room: MatchRow, a: GameSession, b: GameSession, ta: SupabaseTurnTransport, tb: SupabaseTurnTransport) {
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
        let ta = SupabaseTurnTransport(client: host.client, matchID: room.id)
        let tb = SupabaseTurnTransport(client: guest.client, matchID: room.id, realtimeEnabled: realtimeForGuest)
        let a = GameSession(driver: ConstantDriver(face: 3), stage: DiceStage(library: library), record: hostRecord, transport: ta)
        let b = GameSession(driver: ConstantDriver(face: 5), stage: DiceStage(library: library), record: guestRecord, transport: tb)
        a.reduceMotion = true; b.reduceMotion = true
        a.startListening(); b.startListening()
        let deadline = ContinuousClock.now + .seconds(8)
        while !(ta.isSubscribed && (tb.isSubscribed || !realtimeForGuest)), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(ta.isSubscribed, "호스트 구독 실패: \(ta.subscribeError ?? "없음")")
        return (host, refreshed, a, b, ta, tb)
    }

    @Test("호스트의 기록이 게스트의 내 차례가 되기까지 중앙값 1.5초 아래다")
    func 지연() async throws {
        let pair = try await makePair()
        var samples: [Duration] = []
        for turn in 0..<3 {
            await pair.a.send(.roll)
            let category: ScoreCategory = [.aces, .deuces, .threes][turn]
            let started = ContinuousClock.now
            await pair.a.send(.commit(category))
            let deadline = started + .seconds(10)
            while !pair.b.isLocalTurn, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            samples.append(ContinuousClock.now - started)
            #expect(pair.b.isLocalTurn)
            // 게스트가 바로 되돌려 준다
            await pair.b.send(.roll)
            await pair.b.send(.commit(category))
            let back = ContinuousClock.now + .seconds(10)
            while !pair.a.isLocalTurn, ContinuousClock.now < back { try await Task.sleep(for: .milliseconds(10)) }
        }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        print("지연 표본 \(samples), 중앙값 \(median)")
        #expect(median < .milliseconds(1500), "지연 표본: \(samples)")
    }

    @Test("게스트가 재생한 주사위 자세가 호스트와 같다")
    func 자세_재현() async throws {
        let pair = try await makePair()
        await pair.a.send(.roll)
        let deadline = ContinuousClock.now + .seconds(10)
        while pair.b.visibleState.rollsRemaining != 2, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        while pair.b.isBusy, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        for slot in 0..<5 {
            let qa = try #require(pair.a.stageOrientation(slot: slot))
            let qb = try #require(pair.b.stageOrientation(slot: slot))
            #expect(DiceStage.rotationAngle(from: qa, to: qb) < 0.01, "슬롯 \(slot) 자세가 다르다")
        }
    }

    @Test("게스트가 채널에 들어오면 호스트의 opponentPresent가 참이 된다")
    func 접속() async throws {
        let pair = try await makePair()
        let deadline = ContinuousClock.now + .seconds(8)
        while !(pair.a.opponentPresent && pair.b.opponentPresent), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(pair.a.opponentPresent && pair.b.opponentPresent)
        #expect(pair.a.isConnected && pair.b.isConnected)
    }

    @Test("참가자가 아닌 계정은 비공개 채널을 구독할 수 없다")
    func 낯선_계정_거부() async throws {
        let pair = try await makePair()
        // 거부된 구독은 라이브러리가 다시 시도하므로 한 번만 시도하게 한다
        let stranger = SupabaseService(client: makeClient(maxRetryAttempts: 1))
        await stranger.signIn()
        let transport = SupabaseTurnTransport(client: stranger.client, matchID: pair.room.id)
        let deadline = ContinuousClock.now + .seconds(20)
        while transport.subscribeError == nil, !transport.isSubscribed, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!transport.isSubscribed && transport.subscribeError != nil, "낯선 계정이 구독됐다")
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

    @Test("오목 방을 만들고 들어가 다섯 수로 끝내면 winner_seat와 records가 남는다")
    func 오목_한_판() async throws {
        let host = SupabaseService(client: makeClient())
        let guest = SupabaseService(client: makeClient())
        await host.signIn(); await guest.signIn()
        let hostUid = try #require(host.uid), guestUid = try #require(guest.uid)
        let room = try await host.createRoom(name: "A", game: "omok", player: nil)
        #expect(room.game == "omok")
        let joined = try await guest.joinRoom(code: room.code, name: "B", player: nil)
        let refreshed = try await host.fetchMatch(id: room.id)
        let ta = SupabaseTurnTransport(client: host.client, matchID: room.id)
        let tb = SupabaseTurnTransport(client: guest.client, matchID: room.id)
        let a = OnlineMatch(game: Omok.self, mode: .online(matchID: room.id.uuidString),
                            participants: seatParticipants(localID: hostUid.uuidString, players: refreshed.seats(localUid: hostUid)),
                            log: MoveLog<Omok>(), transport: ta)
        let b = OnlineMatch(game: Omok.self, mode: .online(matchID: room.id.uuidString),
                            participants: seatParticipants(localID: guestUid.uuidString, players: joined.seats(localUid: guestUid)),
                            log: MoveLog<Omok>(), transport: tb)
        a.startListening(); b.startListening()
        let deadline = ContinuousClock.now + .seconds(8)
        while !(ta.isSubscribed && tb.isSubscribed), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        let moves: [(OnlineMatch<Omok>, Int, Int)] = [(a,0,0),(b,0,1),(a,1,0),(b,1,1),(a,2,0),(b,2,1),(a,3,0),(b,3,1),(a,4,0)]
        for (m, x, y) in moves {
            #expect(await m.play(Omok.Move(x: x, y: y)), "\(x),\(y) 실패: \(m.lastTransportError ?? "")")
            let other = m === a ? b : a
            let d = ContinuousClock.now + .seconds(10)
            while other.log.moves.count != m.log.moves.count, ContinuousClock.now < d { try await Task.sleep(for: .milliseconds(50)) }
            #expect(other.log.moves.count == m.log.moves.count, "상대에게 수가 가지 않았다")
        }
        #expect(a.outcome == .win(seat: 0) && b.outcome == .win(seat: 0))
        let final = try await host.fetchMatch(id: room.id)
        #expect(final.status == "finished" && final.winnerSeat == 0)
        // 끝난 판은 더 못 바꾼다
        await #expect(throws: (any Error).self) {
            try await ta.publish(TurnPayload(log: final.log, eventCount: 9, hints: [], turnSeat: 1, winnerSeat: nil, finished: false))
        }
        let records = await host.fetchRecords(player: try #require(RecordsStore.playerKey(playerID: nil, uid: hostUid)))
        #expect(records?.first { $0.game == "omok" }?.wins == 1)
        let theirs = await guest.fetchRecords(player: try #require(RecordsStore.playerKey(playerID: nil, uid: guestUid)))
        #expect(theirs?.first { $0.game == "omok" }?.losses == 1)
    }

    @Test("컵퐁 방에서 열 번 맞혀 끝내면 winner_seat가 남는다")
    func 컵퐁_한_판() async throws {
        let host = SupabaseService(client: makeClient())
        let guest = SupabaseService(client: makeClient())
        await host.signIn(); await guest.signIn()
        let hostUid = try #require(host.uid), guestUid = try #require(guest.uid)
        let room = try await host.createRoom(name: "A", game: "cuppong", player: nil)
        let joined = try await guest.joinRoom(code: room.code, name: "B", player: nil)
        let refreshed = try await host.fetchMatch(id: room.id)
        let ta = SupabaseTurnTransport(client: host.client, matchID: room.id)
        let tb = SupabaseTurnTransport(client: guest.client, matchID: room.id)
        let a = OnlineMatch(game: CupPong.self, mode: .online(matchID: room.id.uuidString),
                            participants: seatParticipants(localID: hostUid.uuidString, players: refreshed.seats(localUid: hostUid)),
                            log: MoveLog<CupPong>(), transport: ta)
        let b = OnlineMatch(game: CupPong.self, mode: .online(matchID: room.id.uuidString),
                            participants: seatParticipants(localID: guestUid.uuidString, players: joined.seats(localUid: guestUid)),
                            log: MoveLog<CupPong>(), transport: tb)
        a.startListening(); b.startListening()
        let deadline = ContinuousClock.now + .seconds(8)
        while !(ta.isSubscribed && tb.isSubscribed), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        let shots: [CupPong.Shot] = [
            .init(dx: -207, power: 500), .init(dx: -69, power: 500), .init(dx: 69, power: 500), .init(dx: 207, power: 500),
            .init(dx: -150, power: 450), .init(dx: 0, power: 450), .init(dx: 150, power: 450),
            .init(dx: -81, power: 400), .init(dx: 81, power: 400), .init(dx: 0, power: 350),
        ]
        for shot in shots {
            let ok = await a.play(shot)
            #expect(ok, "\(shot) 실패: \(a.lastTransportError ?? "")")
            let d = ContinuousClock.now + .seconds(10)
            while b.log.moves.count != a.log.moves.count, ContinuousClock.now < d { try await Task.sleep(for: .milliseconds(50)) }
            #expect(b.log.moves.count == a.log.moves.count, "상대에게 수가 가지 않았다")
        }
        #expect(a.outcome == .win(seat: 0) && b.outcome == .win(seat: 0))
        let final = try await host.fetchMatch(id: room.id)
        #expect(final.status == "finished" && final.winnerSeat == 0 && final.game == "cuppong")
    }

    @Test("알까기 방을 만들고 들어가 배치 두 수와 아홉 수로 끝내면 winner_seat가 남는다")
    func 알까기_한_판() async throws {
        let host = SupabaseService(client: makeClient())
        let guest = SupabaseService(client: makeClient())
        await host.signIn(); await guest.signIn()
        let hostUid = try #require(host.uid), guestUid = try #require(guest.uid)
        let room = try await host.createRoom(name: "A", game: "alkkagi", player: nil)
        let joined = try await guest.joinRoom(code: room.code, name: "B", player: nil)
        let refreshed = try await host.fetchMatch(id: room.id)
        let ta = SupabaseTurnTransport(client: host.client, matchID: room.id)
        let tb = SupabaseTurnTransport(client: guest.client, matchID: room.id)
        let a = OnlineMatch(game: Alkkagi.self, mode: .online(matchID: room.id.uuidString),
                            participants: seatParticipants(localID: hostUid.uuidString, players: refreshed.seats(localUid: hostUid)),
                            log: MoveLog<Alkkagi>(), transport: ta)
        let b = OnlineMatch(game: Alkkagi.self, mode: .online(matchID: room.id.uuidString),
                            participants: seatParticipants(localID: guestUid.uuidString, players: joined.seats(localUid: guestUid)),
                            log: MoveLog<Alkkagi>(), transport: tb)
        a.startListening(); b.startListening()
        let deadline = ContinuousClock.now + .seconds(8)
        while !(ta.isSubscribed && tb.isSubscribed), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
        for (i, move) in AlkkagiMatchTests.winningMoves().enumerated() {
            let mover = i % 2 == 0 ? a : b, other = i % 2 == 0 ? b : a
            let ok = await mover.play(move)
            #expect(ok, "\(i)번째 수 \(move) 실패: \(mover.lastTransportError ?? "")")
            let d = ContinuousClock.now + .seconds(10)
            while other.log.moves.count != mover.log.moves.count, ContinuousClock.now < d { try await Task.sleep(for: .milliseconds(50)) }
            #expect(other.log.moves.count == mover.log.moves.count, "상대에게 수가 가지 않았다")
        }
        #expect(a.outcome == .win(seat: 0) && b.outcome == .win(seat: 0))
        let final = try await host.fetchMatch(id: room.id)
        #expect(final.status == "finished" && final.winnerSeat == 0 && final.game == "alkkagi")
    }

    @Test("연결된 플레이어로만 방을 만들고 들어갈 수 있다")
    func 연결된_플레이어() async throws {
        let host = SupabaseService(client: makeClient())
        let guest = SupabaseService(client: makeClient())
        await host.signIn(); await guest.signIn()
        let hostPlayer = "T:" + UUID().uuidString.lowercased()
        let guestPlayer = "T:" + UUID().uuidString.lowercased()
        // 연결하지 않은 플레이어 문자열로는 방을 만들 수 없다
        await #expect(throws: (any Error).self) {
            _ = try await host.createRoom(name: "A", game: "omok", player: hostPlayer)
        }
        await host.upsertProfile(player: hostPlayer, name: "A")
        let room = try await host.createRoom(name: "A", game: "omok", player: hostPlayer)
        #expect(room.hostPlayer == hostPlayer)
        // 게스트도 연결하지 않으면 거부되고, 연결하면 들어간다
        await #expect(throws: (any Error).self) {
            _ = try await guest.joinRoom(code: room.code, name: "B", player: guestPlayer)
        }
        await guest.upsertProfile(player: guestPlayer, name: "B")
        let joined = try await guest.joinRoom(code: room.code, name: "B", player: guestPlayer)
        #expect(joined.guestPlayer == guestPlayer && joined.status == "playing")
        // 호스트는 연결된 플레이어 정책으로도 행을 읽는다
        let refreshed = try await host.fetchMatch(id: room.id)
        #expect(refreshed.guestPlayer == guestPlayer)
        try await host.deleteMatch(id: room.id)
    }
}
