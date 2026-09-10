import Testing
import Foundation
@testable import GameCore

@Suite("MoveLog")
struct MoveLogTests {
    @Test("수를 더하면 상태가 따라오고 규칙에 어긋난 수는 거부한다")
    func 추가() {
        var log = MoveLog<Omok>()
        // #expect(log.append(...))는 매크로가 mutating 호출을 캡처하지 못해 컴파일이 안 된다. 결과를 먼저 변수에 받는다.
        let first = log.append(Omok.Move(x: 7, y: 7))
        let second = log.append(Omok.Move(x: 7, y: 7))
        #expect(first)
        #expect(!second)
        #expect(log.moves.count == 1 && log.state.cells[7 * 15 + 7] == 1)
    }

    @Test("JSON 왕복이 같고, 적용 불가한 로그는 디코드에서 던진다")
    func 왕복() throws {
        var log = MoveLog<Omok>()
        _ = log.append(Omok.Move(x: 0, y: 0)); _ = log.append(Omok.Move(x: 1, y: 1))
        let data = try log.encoded()
        #expect(try MoveLog<Omok>.decoded(from: data) == log)
        let bad = Data("{\"moves\":[{\"x\":0,\"y\":0},{\"x\":0,\"y\":0}]}".utf8)
        #expect(throws: (any Error).self) { try MoveLog<Omok>.decoded(from: bad) }
    }
}
