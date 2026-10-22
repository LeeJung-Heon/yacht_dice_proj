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

    @Test("수를 두면 들고 있던 순간 상태를 버리고 nil로 거둔다")
    func 두면_거두기() async throws {
        let (a, _, ta, _) = makePair()
        a.publishLive(Omok.Move(x: 1, y: 1))
        a.publishLive(Omok.Move(x: 2, y: 2))
        await a.play(Omok.Move(x: 7, y: 7))
        try await Task.sleep(for: .milliseconds(250))
        #expect(sentMoves(ta) == [Omok.Move(x: 1, y: 1), nil], "수를 둔 뒤에 지난 차례의 손놀림이 나갔다")
        #expect(ta.sentLive.last?.eventCount == 0)
    }

    @Test("재생 중에 도착한 지난 차례의 순간 상태는 다음 차례에 되살아나지 않는다")
    func 되살아나지_않음() async throws {
        let (a, b, ta, _) = makePair()
        var replaying = false
        var release: CheckedContinuation<Void, Never>?
        b.onRemoteMove = { _, _ in
            replaying = true
            await withCheckedContinuation { release = $0 }
        }
        await a.play(Omok.Move(x: 5, y: 5))
        await waitUntil { replaying }
        // 상대 수를 재생하는 동안 그 수 전의 손놀림이 늦게 닿는다
        await ta.sendLive(LiveFrame(eventCount: 0, state: encoded(Omok.Move(x: 9, y: 9))))
        try await Task.sleep(for: .milliseconds(50))
        release?.resume()
        await b.waitForIncoming()
        b.onRemoteMove = nil
        await b.play(Omok.Move(x: 6, y: 6))
        await a.waitForIncoming()
        // 다시 상대 차례다. 그 사이 상대가 아무것도 보내지 않았으니 보일 것이 없다.
        #expect(!b.isLocalTurn)
        #expect(b.remoteLive == nil, "지난 차례의 손놀림이 되살아났다")
    }
}

@Suite("OnlineMatch - 순간 상태 (연속 수)")
@MainActor
struct OnlineMatchConsecutiveLiveTests {
    @Test("같은 좌석이 이어 두면 재생 중에 온 다음 수의 순간 상태가 재생 뒤에 보인다")
    func 연속_수() async throws {
        let (ta, tb) = InMemoryTurnTransport.pair()
        let a = OnlineMatch(game: CupPong.self, mode: .online(matchID: "c"),
                            participants: [.human(name: "A"), .remote(playerID: "b", name: "B")], log: MoveLog<CupPong>(), transport: ta)
        let b = OnlineMatch(game: CupPong.self, mode: .online(matchID: "c"),
                            participants: [.remote(playerID: "a", name: "A"), .human(name: "B")], log: MoveLog<CupPong>(), transport: tb)
        a.startListening(); b.startListening()
        var replaying = false
        var release: CheckedContinuation<Void, Never>?
        b.onRemoteMove = { _, _ in
            replaying = true
            await withCheckedContinuation { release = $0 }
        }
        // 맞히는 던지기라 A가 한 번 더 던진다
        #expect(await a.play(CupPongMatchTests.winningShots[0]))
        #expect(a.isLocalTurn)
        let deadline = ContinuousClock.now + .seconds(2)
        while !replaying, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        a.publishLive(CupPongScreen.Live(aiming: true))
        try await Task.sleep(for: .milliseconds(50))
        #expect(b.remoteLive == nil, "재생 중에는 다음 수의 손놀림을 그리지 않는다")
        release?.resume()
        await b.waitForIncoming()
        #expect(b.remoteLive(as: CupPongScreen.Live.self) == CupPongScreen.Live(aiming: true), "재생 뒤에도 조준 중이 보이지 않는다")
    }
}

extension OnlineMatchLiveTests {
    @Test("로컬 2인은 아무것도 보내지 않고 remoteLive가 없다")
    func 로컬() async throws {
        let local = OnlineMatch(game: Omok.self, mode: .passAndPlay(names: ["A", "B"]), participants: [.human(name: "A"), .human(name: "B")],
                                log: MoveLog<Omok>(), transport: nil)
        local.publishLive(Omok.Move(x: 1, y: 1))
        try await Task.sleep(for: .milliseconds(50))
        #expect(local.remoteLive == nil)
    }
}

@Suite("OnlineMatch - 이모지 반응")
@MainActor
struct OnlineMatchReactionTests {
    private func makePair() -> (OnlineMatch<Omok>, OnlineMatch<Omok>) {
        let (ta, tb) = InMemoryTurnTransport.pair()
        let a = OnlineMatch(game: Omok.self, mode: .online(matchID: "m"), participants: [.human(name: "A"), .remote(playerID: "b", name: "B")],
                            log: MoveLog<Omok>(), transport: ta)
        let b = OnlineMatch(game: Omok.self, mode: .online(matchID: "m"), participants: [.remote(playerID: "a", name: "A"), .human(name: "B")],
                            log: MoveLog<Omok>(), transport: tb)
        a.startListening(); b.startListening()
        return (a, b)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test("온라인은 반응을 내놓고 로컬은 없다")
    func 있고_없음() {
        let (a, b) = makePair()
        #expect(a.reactions?.localSeat == 0 && a.reactions?.remoteSeat == 1 && a.reactions?.remoteName == "B")
        #expect(b.reactions?.localSeat == 1 && b.reactions?.remoteSeat == 0)
        let local = OnlineMatch(game: Omok.self, mode: .passAndPlay(names: ["A", "B"]), participants: [.human(name: "A"), .human(name: "B")],
                                log: MoveLog<Omok>(), transport: nil)
        #expect(local.reactions == nil)
        #expect(!local.sendReaction("🔥"))
    }

    @Test("상대 수를 재생해 차례가 바뀌면 그 전의 배지가 양쪽에서 사라진다")
    func 차례에_거둠() async {
        let (a, b) = makePair()
        #expect(a.sendReaction("🔥"))
        await waitUntil { b.reactions?.badges[0] != nil }
        #expect(b.reactions?.badges[0]?.emoji == "🔥")
        await a.play(Omok.Move(x: 7, y: 7))
        await b.waitForIncoming()
        #expect(a.reactions?.badges[0] == nil && b.reactions?.badges[0] == nil)
    }

    @Test("내 수를 상대가 재생하는 중에 보낸 이모지는 재생이 끝나도 양쪽에 남는다")
    func 재생_중_수신() async {
        let (a, b) = makePair()
        var replaying = false
        var release: CheckedContinuation<Void, Never>?
        b.onRemoteMove = { _, _ in
            replaying = true
            await withCheckedContinuation { release = $0 }
        }
        await a.play(Omok.Move(x: 5, y: 5))
        await waitUntil { replaying }
        #expect(a.sendReaction("😭"))
        await waitUntil { b.reactions?.badges[0] != nil }
        release?.resume()
        await b.waitForIncoming()
        b.onRemoteMove = nil
        #expect(a.reactions?.badges[0]?.emoji == "😭")
        #expect(b.reactions?.badges[0]?.emoji == "😭", "재생이 끝나자 받은 배지가 사라졌다")
        await b.play(Omok.Move(x: 6, y: 6))
        await a.waitForIncoming()
        #expect(a.reactions?.badges[0] == nil && b.reactions?.badges[0] == nil)
    }

    @Test("판이 끝난 뒤에도 반응을 주고받는다")
    func 끝난_뒤() async {
        let (a, b) = makePair()
        for x in 0..<5 {
            await a.play(Omok.Move(x: x, y: 0)); await b.waitForIncoming()
            if x < 4 { await b.play(Omok.Move(x: x, y: 1)); await a.waitForIncoming() }
        }
        #expect(a.outcome == .win(seat: 0) && b.outcome == .win(seat: 0))
        #expect(b.sendReaction("👏"))
        await waitUntil { a.reactions?.badges[1] != nil }
        #expect(a.reactions?.badges[1]?.emoji == "👏")
    }

    @Test("stop()하면 반응을 받지 않는다")
    func 접기() async throws {
        let (a, b) = makePair()
        b.stop()
        a.sendReaction("🔥")
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.reactions?.bursts.isEmpty == true && b.reactions?.badges.isEmpty == true)
    }
}
