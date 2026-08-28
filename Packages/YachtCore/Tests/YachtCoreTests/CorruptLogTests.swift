import Testing
import Foundation
@testable import YachtCore

@Suite("손상된 저장 파일")
struct CorruptLogTests {

    /// MatchLog를 거치지 않고 임의의 JSON을 만들어 손상된 파일을 흉내낸다.
    private func encodedLog(playerCount: Int, events: [Event]) throws -> Data {
        var log = MatchLog(playerCount: playerCount)
        for event in events { log.append(event) }
        return try log.encoded()
    }

    /// JSON 직렬화를 통해 playerCount를 임의로 설정한다 (precondition 우회).
    /// 매우 큰 playerCount로 인한 할당 실패를 테스트하기 위해 필요하다.
    private func encodedLogWithArbitraryPlayerCount(_ playerCount: Int) throws -> Data {
        var log = MatchLog(playerCount: 1)
        var json = try JSONSerialization.jsonObject(with: log.encoded()) as! [String: Any]
        json["playerCount"] = playerCount
        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test("정상 로그는 그대로 디코딩된다")
    func 정상_로그() throws {
        let data = try encodedLog(playerCount: 1, events: [.rolled([1, 2, 3, 4, 5]), .committed(.choice, 15)])
        let restored = try MatchLog.decoded(from: data)
        #expect(restored.events.count == 2)
        #expect(restored.state.scorecards[0].entry(.choice) == 15)
    }

    @Test("rolled 길이가 어긋난 로그는 트랩이 아니라 throw로 거부된다")
    func 잘못된_rolled_길이() throws {
        // 5개 슬롯이 비어 있는데 3개만 굴린 것으로 기록된 로그.
        // 예전에는 이 데이터가 디코딩을 통과한 뒤 .state 접근 시 프로세스를 죽였다.
        let data = try encodedLog(playerCount: 1, events: [.rolled([1, 2, 3])])
        #expect(throws: MatchLog.DecodingFailure.corruptedLog(eventIndex: 0)) {
            try MatchLog.decoded(from: data)
        }
    }

    @Test("주사위 눈이 범위를 벗어난 로그를 거부한다")
    func 잘못된_주사위_눈() throws {
        let data = try encodedLog(playerCount: 1, events: [.rolled([1, 2, 3, 4, 9])])
        #expect(throws: MatchLog.DecodingFailure.corruptedLog(eventIndex: 0)) {
            try MatchLog.decoded(from: data)
        }
    }

    @Test("같은 카테고리를 두 번 기록한 로그를 거부한다")
    func 중복_기록() throws {
        let data = try encodedLog(playerCount: 1, events: [
            .rolled([1, 1, 1, 1, 1]), .committed(.aces, 5), .turnAdvanced,
            .rolled([1, 1, 1, 1, 1]), .committed(.aces, 5),
        ])
        #expect(throws: MatchLog.DecodingFailure.corruptedLog(eventIndex: 4)) {
            try MatchLog.decoded(from: data)
        }
    }

    @Test("주사위 인덱스가 범위를 벗어난 로그를 거부한다")
    func 잘못된_홀드_인덱스() throws {
        let data = try encodedLog(playerCount: 1, events: [.rolled([1, 2, 3, 4, 5]), .holdToggled(7)])
        #expect(throws: MatchLog.DecodingFailure.corruptedLog(eventIndex: 1)) {
            try MatchLog.decoded(from: data)
        }
    }

    @Test("playerCount가 0인 로그를 거부한다")
    func 잘못된_플레이어_수() throws {
        // MatchLog(playerCount: 0)은 그 자체로는 막히지 않지만 GameState는 1명 이상을 요구한다.
        let data = try encodedLog(playerCount: 0, events: [])
        #expect(throws: MatchLog.DecodingFailure.invalidPlayerCount(0)) {
            try MatchLog.decoded(from: data)
        }
    }

    @Test("canApply는 상태를 바꾸지 않는다")
    func 부작용_없음() {
        let state = GameState(playerCount: 1).applying(.rolled([1, 2, 3, 4, 5]))
        let before = state
        _ = state.canApply(.rolled([1, 2]))
        _ = state.canApply(.holdToggled(99))
        _ = state.canApply(.committed(.aces, 1))
        #expect(state == before)
    }

    @Test("playerCount가 maxPlayers보다 크면 거부한다")
    func 플레이어_수_초과() throws {
        let data = try encodedLogWithArbitraryPlayerCount(5)
        #expect(throws: MatchLog.DecodingFailure.invalidPlayerCount(5)) {
            try MatchLog.decoded(from: data)
        }
    }

    @Test("playerCount = Int.max는 할당 실패 없이 throw로 거부된다")
    func 플레이어_수_매우_큼_intmax() throws {
        let data = try encodedLogWithArbitraryPlayerCount(Int.max)
        #expect(throws: MatchLog.DecodingFailure.invalidPlayerCount(Int.max)) {
            try MatchLog.decoded(from: data)
        }
    }

    @Test("playerCount = 10억은 할당 실패 없이 throw로 거부된다")
    func 플레이어_수_매우_큼_10억() throws {
        let data = try encodedLogWithArbitraryPlayerCount(10_000_000_000)
        #expect(throws: MatchLog.DecodingFailure.invalidPlayerCount(10_000_000_000)) {
            try MatchLog.decoded(from: data)
        }
    }

    @Test("playerCount = 4는 여전히 수용된다")
    func 플레이어_수_최대값_수용() throws {
        let data = try encodedLog(playerCount: 4, events: [])
        let restored = try MatchLog.decoded(from: data)
        #expect(restored.playerCount == 4)
    }
}
