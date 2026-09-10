import Testing
import Foundation
import YachtCore
@testable import YachtDice

@Suite("턴 전송")
struct TurnTransportTests {
    private func payload(_ text: String, count: Int, turn: Int? = 1, winner: Int? = nil, finished: Bool = false) -> TurnPayload {
        TurnPayload(log: Data(text.utf8), eventCount: count, hints: [], turnSeat: turn, winnerSeat: winner, finished: finished)
    }

    @Test("A가 올린 것이 B에게만 흐르고 A는 보낸 것을 기억한다")
    func 전달() async throws {
        let (a, b) = InMemoryTurnTransport.pair()
        var iterator = b.incoming.makeAsyncIterator()
        let p = payload("{\"n\":1}", count: 1)
        try await a.publish(p)
        let received = await iterator.next()
        #expect(received?.log == p.log && received?.eventCount == 1)
        #expect(a.sent == [p] && a.lastPayload?.turnSeat == 1)
    }

    @Test("끝난 판은 승자와 finished를 싣는다")
    func 종료() async throws {
        let (a, _) = InMemoryTurnTransport.pair()
        try await a.publish(payload("{}", count: 40, turn: nil, winner: 0, finished: true))
        #expect(a.lastPayload?.winnerSeat == 0 && a.lastPayload?.finished == true)
    }

    @Test("힌트가 로그와 함께 전달된다")
    func 힌트_전달() async throws {
        let (a, b) = InMemoryTurnTransport.pair()
        var iterator = b.incoming.makeAsyncIterator()
        let hint = ThrowHint(event: 0, trajectory: 5, direction: 1, yaws: [0, 1, 2, 3, 0])
        try await a.publish(TurnPayload(log: Data("{}".utf8), eventCount: 1, hints: [hint], turnSeat: 0, winnerSeat: nil, finished: false))
        #expect(await iterator.next()?.hints == [hint])
    }

    @Test("쌍을 만들면 서로의 uid가 presence로 흐른다")
    func 접속() async throws {
        let (a, _) = InMemoryTurnTransport.pair(uidA: "a", uidB: "b")
        var iterator = a.presence.makeAsyncIterator()
        #expect(await iterator.next() == ["b"])
    }
}
