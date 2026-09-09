import Testing
import Foundation
@testable import YachtDice

@Suite("던지기 힌트")
struct ThrowHintTests {
    @Test("JSON 왕복")
    func 왕복() throws {
        let hint = ThrowHint(event: 7, trajectory: 123, direction: 2, yaws: [0, 3, 1, 2, 0])
        let data = try JSONEncoder().encode([hint])
        #expect(try JSONDecoder().decode([ThrowHint].self, from: data) == [hint])
    }
}
