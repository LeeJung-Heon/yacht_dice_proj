import Testing
import Foundation
import GameCore
@testable import YachtDice

@Suite("OnlineMatch - 순간 상태")
@MainActor
struct OnlineMatchLiveTests {
    private func makePair() -> (OnlineMatch<Omok>, OnlineMatch<Omok>, InMemoryTurnTransport, InMemoryTurnTransport) {
        let (ta, tb) = InMemoryTurnTransport.pair()
        let seatsA: [Participant] = [.human(name: "A"), .remote(playerID: "b", name: "B")]
        let seatsB: [Participant] = [.remote(playerID: "a", name: "A"), .human(name: "B")]
        let a = OnlineMatch(game: Omok.self, mode: .online(matchID: "m"), participants: seatsA, log: MoveLog<Omok>(), transport: ta)
        let b = OnlineMatch(game: Omok.self, mode: .online(matchID: "m"), participants: seatsB, log: MoveLog<Omok>(), transport: tb)
        a.startListening(); b.startListening()
        return (a, b, ta, tb)
    }

    private func encoded(_ move: Omok.Move) -> Data { try! JSONEncoder().encode(move) }

    /// 보낸 프레임의 상태를 오목 수로 읽는다. nil은 손을 뗐다는 뜻이다.
    private func sentMoves(_ transport: InMemoryTurnTransport) -> [Omok.Move?] {
        transport.sentLive.map { frame in frame.state.flatMap { try? JSONDecoder().decode(Omok.Move.self, from: $0) } }
    }

    /// 조건이 참이 될 때까지 기다린다(최대 2초).
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test("100ms 안에 보낸 값은 처음 것과 마지막 것만 나간다")
    func 묶기() async throws {
        let (a, _, ta, _) = makePair()
        a.publishLive(Omok.Move(x: 1, y: 1))
        a.publishLive(Omok.Move(x: 2, y: 2))
        a.publishLive(Omok.Move(x: 3, y: 3))
        try await Task.sleep(for: .milliseconds(250))
        #expect(sentMoves(ta) == [Omok.Move(x: 1, y: 1), Omok.Move(x: 3, y: 3)])
        #expect(ta.sentLive.allSatisfy { $0.eventCount == 0 })
    }

    @Test("nil은 바로 나가고 들고 있던 값을 버린다")
    func 거두기() async throws {
        let (a, _, ta, _) = makePair()
        a.publishLive(Omok.Move(x: 1, y: 1))
        a.publishLive(Omok.Move(x: 2, y: 2))
        a.publishLive(Omok.Move?.none)
        await waitUntil { ta.sentLive.count == 2 }
        #expect(sentMoves(ta) == [Omok.Move(x: 1, y: 1), nil])
        try await Task.sleep(for: .milliseconds(250))
        #expect(sentMoves(ta) == [Omok.Move(x: 1, y: 1), nil])
    }

    @Test("같은 값은 다시 보내지 않는다")
    func 중복() async throws {
        let (a, _, ta, _) = makePair()
        a.publishLive(Omok.Move(x: 1, y: 1))
        try await Task.sleep(for: .milliseconds(150))
        a.publishLive(Omok.Move(x: 1, y: 1))
        try await Task.sleep(for: .milliseconds(150))
        #expect(ta.sentLive.count == 1)
    }

    @Test("내 차례가 아니면 보내지 않는다")
    func 차례() async throws {
        let (_, b, _, tb) = makePair()
        b.publishLive(Omok.Move(x: 1, y: 1))
        try await Task.sleep(for: .milliseconds(150))
        #expect(tb.sentLive.isEmpty)
    }

    @Test("상대의 순간 상태가 보이고 상대 수가 오면 비워진다")
    func 보이고_비우기() async throws {
        let (a, b, _, _) = makePair()
        a.publishLive(Omok.Move(x: 4, y: 4))
        await waitUntil { b.remoteLive != nil }
        #expect(b.remoteLive(as: Omok.Move.self) == Omok.Move(x: 4, y: 4))
        await a.play(Omok.Move(x: 4, y: 4))
        await b.waitForIncoming()
        #expect(b.remoteLive == nil)
    }

    @Test("내 로그와 수가 다른 순간 상태는 무시한다")
    func 옛_프레임() async throws {
        let (a, b, ta, _) = makePair()
        await a.play(Omok.Move(x: 4, y: 4))
        await b.waitForIncoming()
        await ta.sendLive(LiveFrame(eventCount: 0, state: encoded(Omok.Move(x: 5, y: 5))))
        await ta.sendLive(LiveFrame(eventCount: 7, state: encoded(Omok.Move(x: 6, y: 6))))
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.remoteLive == nil)
    }

    @Test("상대가 채널을 떠나거나 연결이 끊기면 비워진다")
    func 떠남() async throws {
        let (a, b, _, tb) = makePair()
        a.publishLive(Omok.Move(x: 4, y: 4))
        await waitUntil { b.remoteLive != nil }
        tb.emitPresence([])
        await waitUntil { b.remoteLive == nil }
        #expect(b.remoteLive == nil)

        a.publishLive(Omok.Move(x: 5, y: 5))
        await waitUntil { b.remoteLive != nil }
        #expect(b.remoteLive(as: Omok.Move.self) == Omok.Move(x: 5, y: 5))
        tb.emitConnection(false)
        await waitUntil { b.remoteLive == nil }
        #expect(b.remoteLive == nil)
    }

    @Test("stop()은 보낸 순간 상태를 nil로 거둔다")
    func 접기() async throws {
        let (a, _, ta, _) = makePair()
        a.publishLive(Omok.Move(x: 1, y: 1))
        await waitUntil { ta.sentLive.count == 1 }
        a.stop()
        await waitUntil { ta.sentLive.count == 2 }
        #expect(sentMoves(ta) == [Omok.Move(x: 1, y: 1), nil])
    }

    @Test("로컬 2인은 아무것도 보내지 않고 remoteLive가 없다")
    func 로컬() async throws {
        let local = OnlineMatch(game: Omok.self, mode: .passAndPlay(names: ["A", "B"]), participants: [.human(name: "A"), .human(name: "B")],
                                log: MoveLog<Omok>(), transport: nil)
        local.publishLive(Omok.Move(x: 1, y: 1))
        try await Task.sleep(for: .milliseconds(50))
        #expect(local.remoteLive == nil)
    }
}
