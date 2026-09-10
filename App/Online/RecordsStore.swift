import Foundation
import Observation

/// 서버 `records` 뷰의 한 줄. 게임 하나의 승·패·무다.
struct RecordRow: Decodable, Equatable, Sendable {
    let player: String
    let game: String
    let wins: Int
    let losses: Int
    let draws: Int
}

/// 최근 매치 한 판을 내 눈으로 본 모양으로 줄인 것.
struct RecentMatch: Equatable, Sendable {
    let id: UUID
    let game: String
    let opponent: String
    let result: String
    let finishedAt: Date?
}

/// 허브 전적 카드의 데이터. 서버 `records` 뷰와 최근 매치를 읽고 리더보드에 승수를 올린다.
@MainActor
@Observable
final class RecordsStore {
    private let service: SupabaseService
    private let gameCenter: GameCenterService
    private(set) var records: [RecordRow] = []
    private(set) var recent: [RecentMatch] = []
    /// 게임별로 리더보드에 마지막으로 올린 승수. 같은 값을 되풀이해 올리지 않는다.
    private var submittedWins: [String: Int] = [:]

    init(service: SupabaseService, gameCenter: GameCenterService) {
        self.service = service
        self.gameCenter = gameCenter
    }

    /// 내 식별자: Game Center면 gamePlayerID, 아니면 uid. 서버 `records.player`와 같은 값이다.
    var me: String? { gameCenter.playerID ?? service.uid?.uuidString }

    /// 허브에 돌아올 때마다 부른다. 읽지 못한 쪽은 이미 보여주던 값을 그대로 둔다 —
    /// 잠깐 망이 끊겼다고 전적이 사라진 것처럼 보이면 안 된다.
    func reload() async {
        guard let me, let uid = service.uid else { return }
        if let rows = await service.fetchRecords(player: me) { records = rows }
        if let rows = await service.fetchFinished() { recent = Self.summarize(rows: rows, me: me, myUid: uid) }
        guard gameCenter.playerID != nil else { return }
        for row in records {
            guard let game = GameID(rawValue: row.game), shouldSubmit(wins: row.wins, for: row.game) else { continue }
            await gameCenter.submit(wins: row.wins, game: game)
        }
    }

    /// 이 승수를 리더보드에 올려야 하는가. 올릴 값이면 참을 주고 올린 것으로 기억한다.
    func shouldSubmit(wins: Int, for game: String) -> Bool {
        guard submittedWins[game] != wins else { return false }
        submittedWins[game] = wins
        return true
    }

    /// 끝난 행에서 내 좌석을 찾아 상대 이름과 승패를 뽑는다. 내 자리가 없는 행은 버린다.
    /// 순수 계산이라 액터가 없다.
    nonisolated static func summarize(rows: [MatchRow], me: String, myUid: UUID) -> [RecentMatch] {
        rows.compactMap { row in
            let mySeat: Int
            if row.hostPlayer == me || row.hostUid == myUid { mySeat = 0 }
            else if row.guestPlayer == me || row.guestUid == myUid { mySeat = 1 }
            else { return nil }
            let opponent = mySeat == 0 ? (row.guestName ?? "상대") : row.hostName
            let result = row.winnerSeat == nil ? "무" : (row.winnerSeat == mySeat ? "승" : "패")
            return RecentMatch(id: row.id, game: row.game, opponent: opponent, result: result, finishedAt: row.updatedAt)
        }
    }
}
