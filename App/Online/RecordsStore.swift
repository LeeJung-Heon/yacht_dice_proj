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
    var me: String? { Self.playerKey(playerID: gameCenter.playerID, uid: service.uid) }

    /// 서버 `records.player`·`matches.host_player`/`guest_player`와 같은 값을 만든다. Game Center에
    /// 로그인했으면 gamePlayerID 그대로, 아니면 uid를 쓰되 서버 `uid::text` 캐스트가 소문자를 내놓으므로
    /// `uuidString`을 그대로 쓰면 대문자라 텍스트 동등 비교가 항상 어긋난다 — 반드시 소문자로 맞춘다.
    nonisolated static func playerKey(playerID: String?, uid: UUID?) -> String? {
        playerID ?? uid?.uuidString.lowercased()
    }

    /// 전적을 읽을 키들. 서버는 좌석에 gamePlayerID가 적혀 있으면 그것으로, 없으면 uid로 세는데, 로그인한 사람도
    /// Game Center 열이 생기기 전이나 그 실행에서 신원을 잇지 못했을 때 둔 판은 좌석에 uid만 남는다. 그래서
    /// 로그인했으면 gamePlayerID와 지금 uid를 함께 읽는다. 한 판의 내 좌석은 둘 중 한 키에만 들어가 두 번 세지 않는다.
    nonisolated static func playerKeys(playerID: String?, uid: UUID?) -> [String] {
        var keys: [String] = []
        if let playerID { keys.append(playerID) }
        if let uid = uid?.uuidString.lowercased(), !keys.contains(uid) { keys.append(uid) }
        return keys
    }

    /// 키마다 쪼개진 줄을 게임별로 더해 `player`로 묶고, 허브의 게임 순서로 늘어놓는다.
    nonisolated static func merge(_ rows: [RecordRow], as player: String) -> [RecordRow] {
        var totals: [String: (wins: Int, losses: Int, draws: Int)] = [:]
        for row in rows {
            let sum = totals[row.game] ?? (0, 0, 0)
            totals[row.game] = (sum.wins + row.wins, sum.losses + row.losses, sum.draws + row.draws)
        }
        let order = GameID.allCases.map(\.rawValue)
        let games = totals.keys.sorted { a, b in
            switch (order.firstIndex(of: a), order.firstIndex(of: b)) {
            case let (i?, j?): i < j
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a < b
            }
        }
        return games.map { game in
            let sum = totals[game]!
            return RecordRow(player: player, game: game, wins: sum.wins, losses: sum.losses, draws: sum.draws)
        }
    }

    /// 허브에 돌아올 때마다 부른다. 읽지 못한 쪽은 이미 보여주던 값을 그대로 둔다 —
    /// 잠깐 망이 끊겼다고 전적이 사라진 것처럼 보이면 안 된다.
    func reload() async {
        guard let me, let uid = service.uid else { return }
        let keys = Self.playerKeys(playerID: gameCenter.playerID, uid: uid)
        if let rows = await service.fetchRecords(players: keys) { records = Self.merge(rows, as: me) }
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
