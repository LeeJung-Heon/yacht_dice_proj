import Foundation
import Testing
@testable import GameCore

@Suite("게임 규칙 버전 호환")
struct RulesVersionTests {
    @Test("버전 없는 구형 빈 방도 새 규칙의 방으로 읽지 않는다")
    func 구형_빈_로그_거부() {
        let data = Data(#"{"moves":[]}"#.utf8)
        #expect(throws: (any Error).self) { try MoveLog<Omok>.decoded(from: data) }
        #expect(throws: (any Error).self) { try MoveLog<CupPong>.decoded(from: data) }
        #expect(throws: (any Error).self) { try MoveLog<Alkkagi>.decoded(from: data) }
    }

    @Test("기록된 수가 유효해 보여도 구형 규칙으로 시작한 판은 재해석하지 않는다",
          arguments: [#"{"moves":[{"x":7,"y":7}]}"#,
                      #"{"rulesVersion":1,"moves":[{"x":7,"y":7}]}"#,
                      #"{"rulesVersion":3,"moves":[{"x":7,"y":7}]}"#])
    func 다른_버전_착수_거부(json: String) {
        #expect(throws: (any Error).self) { try MoveLog<Omok>.decoded(from: Data(json.utf8)) }
    }

    @Test("새 로그는 규칙 2를 전달하고 확장한 가장자리의 돌을 복원한다")
    func 새_규칙_왕복() throws {
        var log = MoveLog<Omok>()
        let applied = log.append(.init(x: 18, y: 18))
        #expect(applied)
        let data = try log.encoded()
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["rulesVersion"] as? Int == 2)
        let restored = try MoveLog<Omok>.decoded(from: data)
        #expect(restored.state.stone(x: 18, y: 18) == 1)
        #expect(restored.state.nextSeat == 1)
    }
}
