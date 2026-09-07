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
        var iterator = b.incomingLogs.makeAsyncIterator()
        try await a.endTurn(log: log)
        let received = await iterator.next()
        #expect(received == log)
        #expect(a.sentLogs == [log])
    }

    @Test("endMatch는 결과를 기록하고 상대에게도 로그를 보낸다")
    func 종료() async throws {
        let (a, b) = InMemoryTurnTransport.pair()
        var iterator = b.incomingLogs.makeAsyncIterator()
        try await a.endMatch(log: MatchLog(playerCount: 2), totals: [120, 90])
        let received = await iterator.next()
        #expect(received != nil)
        #expect(a.finishedTotals == [120, 90])
    }
}
