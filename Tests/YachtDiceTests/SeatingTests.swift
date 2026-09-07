import Testing
@testable import YachtDice

@Suite("온라인 좌석 배치")
struct SeatingTests {
    @Test("매치 참가자 순서가 좌석 순서이고, 나는 human이다")
    func 좌석() {
        let seats = seatParticipants(localID: "me", players: [
            SeatPlayer(id: "them", name: "철수"),
            SeatPlayer(id: "me", name: "나야"),
        ])
        #expect(seats == [.remote(playerID: "them", name: "철수"), .human(name: "나야")])
    }

    @Test("아직 상대가 없는 자리는 이름 없는 remote다")
    func 빈_자리() {
        let seats = seatParticipants(localID: "me", players: [
            SeatPlayer(id: "me", name: "나야"),
            SeatPlayer(id: nil, name: nil),
        ])
        #expect(seats == [.human(name: "나야"), .remote(playerID: "?", name: "상대")])
    }
}
