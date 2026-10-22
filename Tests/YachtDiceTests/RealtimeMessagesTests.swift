import Testing
import Foundation
import Supabase
import YachtCore
@testable import YachtDice

@Suite("채널 페이로드")
struct RealtimeMessagesTests {
    private func yachtLog() throws -> Data {
        var log = MatchLog(playerCount: 2)
        log.append(.rolled([1, 2, 3, 4, 5]))
        log.append(.holdToggled(0))
        log.append(.committed(.choice, 15))
        return try log.encoded()
    }

    @Test("MoveMessage는 SDK의 JSONObject로 바꿨다 되돌려도 같은 RemoteUpdate가 된다")
    func 수_왕복() throws {
        let hint = ThrowHint(event: 0, trajectory: 12, direction: 2, yaws: [0, 1, 2, 3, 0])
        let payload = TurnPayload(log: try yachtLog(), eventCount: 3, hints: [hint], turnSeat: 0, winnerSeat: nil, finished: false)
        let object = try JSONObject(MoveMessage(payload))
        let decoded = try AnyJSON.object(object).decode(as: MoveMessage.self)
        let update = try decoded.remoteUpdate()
        #expect(try MatchLog.decoded(from: update.log) == MatchLog.decoded(from: payload.log))
        #expect(update.eventCount == 3 && update.hints == [hint])
    }

    @Test("LiveMessage는 state를 JSON 그대로 싣고 nil은 nil로 돌아온다")
    func 순간_상태_왕복() throws {
        let frame = LiveFrame(eventCount: 2, state: Data("{\"x\":3,\"y\":4}".utf8))
        let message = try LiveMessage(frame)
        let text = String(decoding: try JSONEncoder().encode(message), as: UTF8.self)
        #expect(text.contains("\"x\":3") && text.contains("\"event_count\":2"), "state가 JSON 그대로 실리지 않았다: \(text)")
        let back = try AnyJSON.object(try JSONObject(message)).decode(as: LiveMessage.self).frame()
        #expect(back.eventCount == 2)
        let state = try #require(back.state)
        #expect(try JSONDecoder().decode([String: Int].self, from: state) == ["x": 3, "y": 4])

        let empty = try AnyJSON.object(try JSONObject(LiveMessage(LiveFrame(eventCount: 2, state: nil)))).decode(as: LiveMessage.self)
        #expect(try empty.frame() == LiveFrame(eventCount: 2, state: nil))
    }

    @Test("깨진 페이로드는 디코드에 실패한다")
    func 깨진_페이로드() {
        let broken = AnyJSON.object(["event_count": .string("x")])
        #expect(throws: (any Error).self) { try broken.decode(as: MoveMessage.self) }
        #expect(throws: (any Error).self) { try broken.decode(as: LiveMessage.self) }
    }
}
