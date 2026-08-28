import Testing
import Foundation
@testable import YachtCore

@Suite("이벤트 로그")
struct MatchLogTests {

    @Test("append한 순서대로 상태가 재구성된다")
    func 상태_재구성() {
        var log = MatchLog(playerCount: 1)
        log.append(.rolled([6, 6, 6, 6, 6]))
        log.append(.committed(.yacht, 50))
        #expect(log.state.scorecards[0].entry(.yacht) == 50)
        #expect(log.events.count == 2)
    }

    @Test("직렬화 왕복 후 상태가 같다")
    func 왕복() throws {
        var log = MatchLog(playerCount: 2)
        log.append(.rolled([1, 2, 3, 4, 5]))
        log.append(.holdToggled(0))
        log.append(.rolled([6, 6, 6, 6]))
        log.append(.committed(.sixes, 24))
        log.append(.turnAdvanced)

        let data = try log.encoded()
        let restored = try MatchLog.decoded(from: data)

        #expect(restored == log)
        #expect(restored.state == log.state)
        #expect(restored.playerCount == 2)
    }

    @Test("포맷 버전이 다르면 디코딩이 실패한다")
    func 버전_불일치() throws {
        var log = MatchLog(playerCount: 1)
        log.append(.rolled([1, 1, 1, 1, 1]))
        var json = try JSONSerialization.jsonObject(with: log.encoded()) as! [String: Any]
        json["formatVersion"] = 999
        let tampered = try JSONSerialization.data(withJSONObject: json)

        #expect(throws: MatchLog.DecodingFailure.unsupportedVersion(999)) {
            try MatchLog.decoded(from: tampered)
        }
    }

    @Test("게임이 끝났는지 판별한다")
    func 완결_판별() {
        var log = MatchLog(playerCount: 1)
        #expect(log.isFinished == false)
        for c in ScoreCategory.allCases {
            log.append(.rolled([1, 1, 1, 1, 1]))
            log.append(.committed(c, 0))
            log.append(.turnAdvanced)
        }
        log.append(.gameEnded)
        #expect(log.isFinished == true)
    }
}
