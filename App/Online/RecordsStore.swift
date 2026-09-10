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

    init(service: SupabaseService, gameCenter: GameCenterService) {
        self.service = service
        self.gameCenter = gameCenter
    }

    /// 내 식별자: Game Center면 gamePlayerID, 아니면 uid. 서버 `records.player`와 같은 값이다.
    var me: String? { gameCenter.playerID ?? service.uid?.uuidString }

    func reload() async {
        guard let me, let uid = service.uid else { return }
        records = await service.fetchRecords(player: me)
        recent = Self.summarize(rows: await service.fetchFinished(), me: me, myUid: uid)
        for row in records {
            if let game = GameID(rawValue: row.game) { await gameCenter.submit(wins: row.wins, game: game) }
        }
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
