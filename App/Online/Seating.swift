import Foundation

/// Game Center 매치의 참가자 한 명. GameKit 객체 없이 테스트하기 위한 최소 표현이다.
struct SeatPlayer: Equatable {
    /// 자동 매칭이 아직 상대를 못 찾았으면 nil.
    let id: String?
    let name: String?
}

/// 매치 참가자 순서를 좌석 순서로 옮긴다. 나는 `.human`, 나머지는 `.remote`.
/// 아직 비어 있는 자리도 `.remote`로 둔다 — 로그의 playerCount와 좌석 수가 같아야 하기 때문이다.
func seatParticipants(localID: String, players: [SeatPlayer]) -> [Participant] {
    players.map { player in
        if player.id == localID {
            return .human(name: player.name ?? "나")
        }
        return .remote(playerID: player.id ?? "?", name: player.name ?? "상대")
    }
}
