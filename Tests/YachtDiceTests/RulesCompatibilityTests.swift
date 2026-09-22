import Foundation
import GameCore
import Testing
import YachtCore
@testable import YachtDice

@Suite("방의 규칙 버전")
@MainActor
struct RulesCompatibilityTests {
    @Test("방 생성 로그가 각 게임의 최신 규칙으로 열리고 요트 기록은 유지된다")
    func 생성_로그() throws {
        let omok = try JSONEncoder().encode(SupabaseService.initialLog(for: "omok"))
        var log = try MoveLog<Omok>.decoded(from: omok)
        let applied = log.append(.init(x: 18, y: 18))
        #expect(applied)
        let cup = try JSONEncoder().encode(SupabaseService.initialLog(for: "cuppong"))
        #expect(try MoveLog<CupPong>.decoded(from: cup).state.remaining(seat: 0) == 10)
        let alkkagi = try JSONEncoder().encode(SupabaseService.initialLog(for: "alkkagi"))
        #expect(try MoveLog<Alkkagi>.decoded(from: alkkagi).state.phase == .setup)
        let yacht = try JSONEncoder().encode(SupabaseService.initialLog(for: "yacht"))
        #expect(try MatchLog.decoded(from: yacht).playerCount == 2)
    }

    @Test("입장 요청은 선택한 게임과 호환 규칙을 서버로 보낸다",
          arguments: [("yacht", 1), ("omok", 2), ("cuppong", 2), ("alkkagi", 2)])
    func 입장_요청(game: String, version: Int) throws {
        let params = try SupabaseService.JoinRoomParameters(code: "123456", name: "손님", game: game, player: "player")
        let data = try JSONEncoder().encode(params)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["p_rules_version"] as? Int == version)
        #expect(object["p_game"] as? String == game)
        #expect(object["p_player"] as? String == "player")
    }
}
