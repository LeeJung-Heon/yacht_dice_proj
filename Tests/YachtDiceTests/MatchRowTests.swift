import Testing
import Foundation
import YachtCore
@testable import YachtDice

@Suite("Supabase 매치 행")
struct MatchRowTests {
    private let host = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let guest = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    private func row(guest: UUID?) throws -> MatchRow {
        MatchRow(id: UUID(), code: "123456", hostUid: host, guestUid: guest, hostName: "호스트",
                 guestName: guest == nil ? nil : "게스트", log: try MatchLog(playerCount: 2).encoded(),
                 eventCount: 0, status: guest == nil ? "waiting" : "playing", totals: nil, game: "yacht")
    }

    @Test("호스트로 열면 좌석 0이 나, 게스트로 열면 좌석 1이 나다")
    func 좌석() throws {
        let asHost = try #require(row(guest: guest).record(localUid: host))
        #expect(asHost.participants == [.human(name: "호스트"), .remote(playerID: guest.uuidString, name: "게스트")])
        let asGuest = try #require(row(guest: guest).record(localUid: guest))
        #expect(asGuest.participants == [.remote(playerID: host.uuidString, name: "호스트"), .human(name: "게스트")])
    }

    @Test("게스트가 없는 대기 방은 기록을 만들지 않는다")
    func 대기_방() throws {
        #expect(try row(guest: nil).record(localUid: host) == nil)
    }

    @Test("서버 JSON(snake_case, jsonb 로그)을 그대로 디코드한다")
    func 디코드() throws {
        let json = """
        {"id":"\(UUID().uuidString.lowercased())","code":"000042","host_uid":"\(host.uuidString.lowercased())",
         "guest_uid":null,"host_name":"h","guest_name":null,
         "log":{"formatVersion":1,"playerCount":2,"events":[{"rolled":{"_0":[1,2,3,4,5]}}]},
         "event_count":1,"status":"waiting","totals":null,"created_at":"2026-09-07T00:00:00Z","updated_at":"2026-09-07T00:00:00Z"}
        """
        let decoded = try JSONDecoder().decode(MatchRow.self, from: Data(json.utf8))
        #expect(decoded.code == "000042")
        #expect(decoded.yachtLog()?.events == [.rolled([1, 2, 3, 4, 5])])
        #expect(decoded.isWaiting)
    }

    @Test("행의 log는 원문 JSON이고 요트 행만 요트 로그로 읽힌다")
    func 원문_로그() throws {
        // MatchLog는 formatVersion도 요구하므로(YachtCore) 요트로 읽히려면 로그가 그 모양을 갖춰야 한다.
        let json = Data("{\"formatVersion\":1,\"playerCount\":2,\"events\":[]}".utf8)
        let yacht = MatchRow(id: UUID(), code: "000001", hostUid: UUID(), guestUid: UUID(), hostName: "A", guestName: "B",
                             log: json, eventCount: 0, status: "playing", totals: nil, game: "yacht")
        #expect(yacht.yachtLog()?.playerCount == 2)
        let omok = MatchRow(id: UUID(), code: "000002", hostUid: UUID(), guestUid: UUID(), hostName: "A", guestName: "B",
                            log: Data("{\"moves\":[]}".utf8), eventCount: 0, status: "playing", totals: nil, game: "omok")
        #expect(omok.yachtLog() == nil)
        #expect(omok.record(localUid: omok.hostUid) == nil)
    }

    @Test("game·player·winner 열을 읽고 없으면 기본값이다")
    func 새_열() throws {
        let text = """
        {"id":"\(UUID().uuidString)","code":"123456","host_uid":"\(UUID().uuidString)","guest_uid":null,"host_name":"A","guest_name":null,
         "log":{"moves":[]},"event_count":0,"status":"waiting","totals":null,"game":"omok","host_player":"G:1","guest_player":null,"winner_seat":null}
        """
        let row = try JSONDecoder().decode(MatchRow.self, from: Data(text.utf8))
        #expect(row.game == "omok" && row.hostPlayer == "G:1" && row.winnerSeat == nil)
        let legacy = try JSONDecoder().decode(MatchRow.self, from: Data(text.replacingOccurrences(of: ",\"game\":\"omok\",\"host_player\":\"G:1\",\"guest_player\":null,\"winner_seat\":null", with: "").utf8))
        #expect(legacy.game == "yacht" && legacy.hostPlayer == nil)
        #expect(String(data: row.log, encoding: .utf8) == "{\"moves\":[]}")
    }

    @Test("방 코드는 6자리 숫자다")
    func 코드() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            #expect(MatchRow.isValidCode(MatchRow.makeCode(using: &generator)))
        }
        #expect(!MatchRow.isValidCode("12345"))
        #expect(!MatchRow.isValidCode("12345a"))
    }
}
