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

    @Test("플레이어 키는 Game Center id가 uid를 이기고, 없으면 uid를 소문자로 낮춘다")
    func 플레이어_키() {
        let uid = UUID()
        #expect(RecordsStore.playerKey(playerID: "G:9", uid: uid) == "G:9")
        #expect(RecordsStore.playerKey(playerID: nil, uid: uid) == uid.uuidString.lowercased())
        #expect(RecordsStore.playerKey(playerID: nil, uid: nil) == nil)
    }

    @Test("같은 승수는 리더보드에 다시 올리지 않는다")
    @MainActor
    func 중복_제출() {
        let store = RecordsStore(service: SupabaseService(), gameCenter: GameCenterService())
        let 처음 = store.shouldSubmit(wins: 3, for: "omok")
        let 같은_값 = store.shouldSubmit(wins: 3, for: "omok")
        let 늘어난_값 = store.shouldSubmit(wins: 4, for: "omok")
        let 다른_게임 = store.shouldSubmit(wins: 3, for: "yacht")
        #expect(처음)
        #expect(!같은_값)
        #expect(늘어난_값)
        #expect(다른_게임)
    }
}
