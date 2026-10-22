import Testing
import Foundation
import YachtCore
import DiceTrajectory
@testable import YachtDice

@Suite("게임 세션 - 온라인")
@MainActor
struct GameSessionOnlineTests {
    private struct ConstantDriver: MatchDriver {
        let face: Int
        func requestRoll(count: Int) async throws -> [Int] { Array(repeating: face, count: count) }
        func submit(_ event: Event) async throws {}
        var incoming: AsyncStream<Event> { AsyncStream { $0.finish() } }
    }

    /// 굴릴 때마다 `faces`를 돌아가며 쓴다. 좌석마다 다른 눈을 주기 위해서다(승자 판정 테스트용).
    private final class AlternatingDriver: MatchDriver, @unchecked Sendable {
        private let lock = NSLock()
        private var callCount = 0
        let faces: [Int]
        init(faces: [Int]) { self.faces = faces }
        func requestRoll(count: Int) async throws -> [Int] {
            let face = lock.withLock {
                defer { callCount += 1 }
                return faces[callCount % faces.count]
            }
            return Array(repeating: face, count: count)
        }
        func submit(_ event: Event) async throws {}
        var incoming: AsyncStream<Event> { AsyncStream { $0.finish() } }
    }

    /// 두 기기. A는 좌석 0, B는 좌석 1.
    private func makePair() throws -> (a: GameSession, b: GameSession, ta: InMemoryTurnTransport, tb: InMemoryTurnTransport) {
        let (ta, tb) = InMemoryTurnTransport.pair()
        let library = try TrajectoryLibrary.bundled()
        let seatsA: [Participant] = [.human(name: "A"), .remote(playerID: "b", name: "B")]
        let seatsB: [Participant] = [.remote(playerID: "a", name: "A"), .human(name: "B")]
        let a = GameSession(driver: ConstantDriver(face: 3), stage: DiceStage(library: library),
                            record: MatchRecord(mode: .online(matchID: "m"), participants: seatsA, log: MatchLog(playerCount: 2)),
                            transport: ta)
        let b = GameSession(driver: ConstantDriver(face: 5), stage: DiceStage(library: library),
                            record: MatchRecord(mode: .online(matchID: "m"), participants: seatsB, log: MatchLog(playerCount: 2)),
                            transport: tb)
        a.reduceMotion = true; b.reduceMotion = true
        a.startListening(); b.startListening()
        return (a, b, ta, tb)
    }

    /// 원격 상대 하나와 붙은 A 세션 하나. 받을 일은 없고 보내는 것만 본다.
    private func makeSender(_ transport: any TurnTransport) throws -> GameSession {
        let seats: [Participant] = [.human(name: "A"), .remote(playerID: "b", name: "B")]
        return GameSession(driver: ConstantDriver(face: 3), stage: DiceStage(library: try TrajectoryLibrary.bundled()),
                           record: MatchRecord(mode: .online(matchID: "m"), participants: seats, log: MatchLog(playerCount: 2)),
                           transport: transport)
    }

    /// 조건이 참이 될 때까지 기다린다.
    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test("굴림은 착지 전에 한 번만 올라가고 내 화면은 전송을 기다리지 않는다")
    func 굴림_선전송() async throws {
        let transport = GatedTransport()
        let a = try makeSender(transport)
        a.reduceMotion = false
        let rolling = Task { await a.send(.roll) }
        await waitUntil { !transport.sent.isEmpty }
        let payload = try #require(transport.sent.first)
        #expect(a.visibleState.rollsRemaining == 3, "착지한 뒤에야 굴림을 올렸다")
        #expect(payload.eventCount == 1)
        #expect(try MatchLog.decoded(from: payload.log).events == [.rolled([3, 3, 3, 3, 3])])
        #expect(payload.hints.count == 1 && payload.hints.first?.event == 0)
        // 게이트가 닫혀 있어도 착지하면 내 화면에는 굴림이 드러난다
        await waitUntil { a.visibleState.rollsRemaining == 2 }
        #expect(a.visibleState.rollsRemaining == 2, "전송을 기다리느라 굴림이 드러나지 않았다")
        transport.open()
        await rolling.value
        #expect(transport.sent.count == 1, "굴림 하나에 payload가 \(transport.sent.count)번 나갔다")
    }

    @Test("굴림 전송이 실패해도 굴림은 내 화면에 드러나고 오류가 남는다")
    func 굴림_전송_실패() async throws {
        let a = try makeSender(FailingTransport())
        a.reduceMotion = true
        await a.send(.roll)
        #expect(a.visibleState.rollsRemaining == 2)
        #expect(a.lastTransportError == "서버에 보내지 못해 다시 시도하는 중이다")
    }

    @Test("따로 도착한 고정 둘은 뜸 없이 이어 재생한다")
    func 고정_뜸() async throws {
        let (a, b, _, _) = try makePair()
        b.reduceMotion = false
        await a.send(.roll)
        await b.waitForIncoming()
        await a.send(.toggleHold(0))
        await a.send(.toggleHold(1))
        let clock = ContinuousClock()
        await waitUntil { b.visibleState.held.contains(0) }
        let first = clock.now
        await waitUntil { b.visibleState.held.contains(1) }
        let gap = clock.now - first
        #expect(b.visibleState.held == [0, 1])
        #expect(gap < .milliseconds(300), "두 번째 고정이 \(gap) 뒤에야 보였다")
    }

    @Test("요트 온라인 세션은 반응을 주고받고 상대 기록으로 차례가 바뀌면 배지가 사라진다")
    func 반응() async throws {
        let (a, b, _, _) = try makePair()
        #expect(a.sendReaction("🔥"))
        await waitUntil { b.reactions?.badges[0] != nil }
        #expect(b.reactions?.badges[0]?.emoji == "🔥")
        await a.send(.roll)
        await a.send(.commit(.threes))
        await b.waitForIncoming()
        #expect(b.reactions?.badges[0] == nil && a.reactions?.badges[0] == nil)
    }

    @Test("요트 로컬 세션은 반응이 없다")
    func 로컬_반응() throws {
        let session = GameSession(driver: ConstantDriver(face: 3), stage: DiceStage(library: try TrajectoryLibrary.bundled()),
                                  record: MatchRecord(mode: .solo, participants: GameMode.solo.participants, log: MatchLog(playerCount: 1)))
        #expect(session.reactions == nil && !session.sendReaction("🔥"))
    }

    @Test("A의 턴이 끝나면 B에 같은 상태가 재생되고 B의 차례가 열린다")
    func 한_턴_전파() async throws {
        let (a, b, _, _) = try makePair()
        #expect(a.isLocalTurn && !b.isLocalTurn)
        await a.send(.roll)
        await a.send(.toggleHold(0))
        await a.send(.commit(.threes))
        await b.waitForIncoming()
        #expect(b.visibleState == a.visibleState)
        #expect(b.visibleState.scorecards[0].entry(.threes) == 15)
        #expect(b.isLocalTurn && !a.isLocalTurn)
    }

    @Test("상대가 굴리는 도중에도 내 화면에 굴림이 도착하고, 차례는 아직 상대다")
    func 실시간_중계() async throws {
        let (a, b, _, _) = try makePair()
        await a.send(.roll)
        await b.waitForIncoming()
        #expect(b.visibleState.dice == a.visibleState.dice, "첫 굴림이 실시간으로 오지 않았다")
        #expect(b.visibleState.rollsRemaining == 2)
        #expect(!b.isLocalTurn && a.isLocalTurn)

        await a.send(.toggleHold(0))
        await b.waitForIncoming()
        #expect(b.visibleState.held == [0], "고정이 실시간으로 오지 않았다")

        await a.send(.commit(.choice))
        await b.waitForIncoming()
        #expect(b.isLocalTurn)
    }

    @Test("상대가 기록하면 어느 칸에 몇 점인지 알림이 남는다")
    func 상대_기록_알림() async throws {
        let (a, b, _, _) = try makePair()
        await a.send(.roll)
        await a.send(.commit(.threes))
        await b.waitForIncoming()
        let commit = try #require(b.lastOpponentCommit)
        #expect(commit.seat == 0 && commit.category == .threes && commit.points == 15)
        #expect(a.lastOpponentCommit == nil, "내가 기록한 것은 알림이 아니다")
    }

    @Test("상대의 굴림이 내 화면에서도 같은 자세로 멈춘다")
    func 같은_던지기() async throws {
        let (a, b, _, _) = try makePair()
        await a.send(.roll)
        await b.waitForIncoming()
        for slot in 0..<5 {
            let qa = try #require(a.stageOrientation(slot: slot))
            let qb = try #require(b.stageOrientation(slot: slot))
            #expect(DiceStage.rotationAngle(from: qa, to: qb) < 0.01, "슬롯 \(slot) 자세가 다르다")
        }
    }

    @Test("메모리 전송의 presence로 상대 접속이 보인다")
    func 접속_표시() async throws {
        let (a, _, _, _) = try makePair()
        let deadline = ContinuousClock.now + .seconds(2)
        while !a.opponentPresent, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(a.opponentPresent)
    }

    @Test("두 세션이 12턴을 완주하고 로그가 같다")
    func 완주() async throws {
        let (a, b, ta, tb) = try makePair()
        for category in ScoreCategory.allCases {
            await a.send(.roll); await a.send(.commit(category))
            await b.waitForIncoming()
            await b.send(.roll); await b.send(.commit(category))
            await a.waitForIncoming()
        }
        #expect(a.visibleState.phase == .finished)
        #expect(b.visibleState.phase == .finished)
        #expect(a.record.log == b.record.log)

        // 끝났다고 알리는 마지막 payload는 둘 중 게임을 실제로 끝낸 쪽이 보낸다.
        let finishing = try #require([ta.lastPayload, tb.lastPayload].compactMap { $0 }.first { $0.finished })
        #expect(finishing.turnSeat == nil)
        let totals = a.visibleState.scorecards.map(\.total)
        let best = totals.max()!
        let uniqueWinner = totals.filter { $0 == best }.count == 1 ? totals.firstIndex(of: best) : nil
        #expect(finishing.winnerSeat == uniqueWinner)
    }

    @Test("동점이 아니면 payload가 유일한 최고 총점 좌석을 승자로 싣는다")
    func 승자_판정() async throws {
        // 참가자를 둘 다 human으로 두면(온라인이지만 원격 좌석이 없는 셈) 한 세션으로 양쪽 턴을
        // 다 넣을 수 있다 — payload(finished:turnSeat:)의 승자 계산만 보면 되니 상대 세션은 필요 없다.
        let (transport, _) = InMemoryTurnTransport.pair()
        let library = try TrajectoryLibrary.bundled()
        let participants: [Participant] = [.human(name: "A"), .human(name: "B")]
        let session = GameSession(driver: AlternatingDriver(faces: [6, 1]), stage: DiceStage(library: library),
                                  record: MatchRecord(mode: .online(matchID: "m"), participants: participants,
                                                      log: MatchLog(playerCount: 2)),
                                  transport: transport)
        session.reduceMotion = true
        for category in ScoreCategory.allCases {
            await session.send(.roll); await session.send(.commit(category)); session.acknowledgeHandoff()
            await session.send(.roll); await session.send(.commit(category)); session.acknowledgeHandoff()
        }
        #expect(session.visibleState.phase == .finished)
        let totals = session.visibleState.scorecards.map(\.total)
        #expect(totals[0] > totals[1], "좌석 0이 항상 6, 좌석 1이 항상 1을 굴렸으니 좌석 0 총점이 높아야 한다: \(totals)")
        #expect(transport.lastPayload?.finished == true)
        #expect(transport.lastPayload?.turnSeat == nil)
        #expect(transport.lastPayload?.winnerSeat == 0)
    }

    @Test("stop() 뒤에는 상대가 올린 갱신을 재생하지 않는다")
    func 중지() async throws {
        let (a, b, _, _) = try makePair()
        b.stop()
        await a.send(.roll)
        try await Task.sleep(for: .milliseconds(300))
        #expect(b.record.log.events.count == 0, "접은 세션이 계속 듣고 있다")
    }

    @Test("조작된 로그는 거부되고 상태가 바뀌지 않는다")
    func 조작_거부() async throws {
        let (ta, tb) = InMemoryTurnTransport.pair()
        let seats: [Participant] = [.remote(playerID: "a", name: "A"), .human(name: "B")]
        let b = GameSession(driver: ConstantDriver(face: 5), stage: DiceStage(library: try TrajectoryLibrary.bundled()),
                            record: MatchRecord(mode: .online(matchID: "m"), participants: seats, log: MatchLog(playerCount: 2)),
                            transport: tb)
        b.reduceMotion = true; b.startListening()
        var forged = MatchLog(playerCount: 2)
        forged.append(.committed(.yacht, 50))   // 굴리지도 않고 기록
        let encoded = try forged.encoded()
        try await ta.publish(TurnPayload(log: encoded, eventCount: forged.events.count, hints: [],
                                         turnSeat: 1, winnerSeat: nil, finished: false))
        await b.waitForIncoming()
        #expect(b.visibleState.scorecards[0].entry(.yacht) == nil)
        #expect(b.lastTransportError != nil)
    }
}

/// publish가 payload를 기록한 뒤 테스트가 `open()`할 때까지 멈춘다. 느린 망을 흉내 낸다.
private final class GatedTransport: TurnTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [TurnPayload] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    var sent: [TurnPayload] { lock.withLock { _sent } }
    let incoming = AsyncStream<RemoteUpdate> { _ in }

    func publish(_ payload: TurnPayload) async throws {
        lock.withLock { _sent.append(payload) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let open = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if open { continuation.resume() }
        }
    }

    func open() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        pending.forEach { $0.resume() }
    }
}

/// 늘 망이 끊긴 것처럼 실패한다.
private struct FailingTransport: TurnTransport {
    func publish(_ payload: TurnPayload) async throws { throw URLError(.notConnectedToInternet) }
    var incoming: AsyncStream<RemoteUpdate> { AsyncStream { _ in } }
}
