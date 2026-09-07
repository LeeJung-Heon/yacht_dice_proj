import Testing
import Foundation
import YachtCore
@testable import YachtDice

@Suite("Supabase 매치 행")
struct MatchRowTests {
    private let host = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let guest = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    private func row(guest: UUID?) -> MatchRow {
        MatchRow(id: UUID(), code: "123456", hostUid: host, guestUid: guest, hostName: "호스트",
                 guestName: guest == nil ? nil : "게스트", log: MatchLog(playerCount: 2),
                 eventCount: 0, status: guest == nil ? "waiting" : "playing", totals: nil)
    }

    @Test("호스트로 열면 좌석 0이 나, 게스트로 열면 좌석 1이 나다")
    func 좌석() throws {
        let asHost = try #require(row(guest: guest).record(localUid: host))
        #expect(asHost.participants == [.human(name: "호스트"), .remote(playerID: guest.uuidString, name: "게스트")])
        let asGuest = try #require(row(guest: guest).record(localUid: guest))
        #expect(asGuest.participants == [.remote(playerID: host.uuidString, name: "호스트"), .human(name: "게스트")])
    }

    @Test("게스트가 없는 대기 방은 기록을 만들지 않는다")
    func 대기_방() {
        #expect(row(guest: nil).record(localUid: host) == nil)
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
        #expect(decoded.log.events == [.rolled([1, 2, 3, 4, 5])])
        #expect(decoded.isWaiting)
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
