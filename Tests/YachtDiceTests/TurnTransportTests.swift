import Testing
import YachtCore
@testable import YachtDice

@Suite("턴 전송 - 메모리")
struct TurnTransportTests {
    @Test("한쪽이 endTurn하면 다른 쪽 incomingLogs로 같은 로그가 온다")
    func 왕복() async throws {
        let (a, b) = InMemoryTurnTransport.pair()
        var log = MatchLog(playerCount: 2)
        log.append(.rolled([1, 2, 3, 4, 5]))
        var iterator = b.incoming.makeAsyncIterator()
        try await a.endTurn(log: log, hints: [], nextSeat: 1)
        let received = await iterator.next()
        #expect(received?.log == log)
        #expect(a.sentLogs == [log])
        #expect(a.lastNextSeat == 1)
    }

    @Test("endMatch는 결과를 기록하고 상대에게도 로그를 보낸다")
    func 종료() async throws {
        let (a, b) = InMemoryTurnTransport.pair()
        var iterator = b.incoming.makeAsyncIterator()
        try await a.endMatch(log: MatchLog(playerCount: 2), hints: [], totals: [120, 90])
        let received = await iterator.next()
        #expect(received != nil)
        #expect(a.finishedTotals == [120, 90])
    }

    @Test("힌트가 로그와 함께 전달된다")
    func 힌트_전달() async throws {
        let (a, b) = InMemoryTurnTransport.pair()
        var iterator = b.incoming.makeAsyncIterator()
        let hint = ThrowHint(event: 0, trajectory: 5, direction: 1, yaws: [0, 1, 2, 3, 0])
        try await a.publishProgress(log: MatchLog(playerCount: 2), hints: [hint])
        #expect(await iterator.next()?.hints == [hint])
    }

    @Test("쌍을 만들면 서로의 uid가 presence로 흐른다")
    func 접속() async throws {
        let (a, _) = InMemoryTurnTransport.pair(uidA: "a", uidB: "b")
        var iterator = a.presence.makeAsyncIterator()
        #expect(await iterator.next() == ["b"])
    }
}
