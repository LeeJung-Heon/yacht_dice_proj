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
