import Testing
import Foundation
@testable import YachtDice

@Suite("전적 요약")
struct RecordsStoreTests {
    @Test("끝난 행에서 내 결과와 상대 이름을 뽑는다")
    func 요약() throws {
        let me = UUID(), them = UUID()
        func row(_ host: UUID, _ guest: UUID, hostName: String, guestName: String, winner: Int?, game: String, hostPlayer: String? = nil) -> MatchRow {
            MatchRow(id: UUID(), code: "000000", hostUid: host, guestUid: guest, hostName: hostName, guestName: guestName,
                     log: Data("{}".utf8), eventCount: 0, status: "finished", totals: nil, game: game,
                     hostPlayer: hostPlayer, guestPlayer: nil, winnerSeat: winner)
        }
        let rows = [
            row(me, them, hostName: "나", guestName: "상대", winner: 0, game: "omok"),
            row(them, me, hostName: "상대", guestName: "나", winner: 0, game: "yacht"),
            row(them, me, hostName: "상대", guestName: "나", winner: nil, game: "omok"),
            row(UUID(), me, hostName: "GC", guestName: "나", winner: 1, game: "omok", hostPlayer: "G:9"),
        ]
        let recent = RecordsStore.summarize(rows: rows, me: me.uuidString, myUid: me)
        #expect(recent.map(\.result) == ["승", "패", "무", "승"])
        #expect(recent.map(\.opponent) == ["상대", "상대", "상대", "GC"])
        #expect(recent.map(\.game) == ["omok", "yacht", "omok", "omok"])
    }
}
