import Foundation
import GameCore
import Observation
import Supabase
import YachtCore

/// Supabase 클라이언트 하나와 익명 로그인, 방 만들기·들어가기·내 매치 목록.
/// GameKit이 `GameCenterService`에 갇혀 있듯 Supabase SDK는 여기와 `SupabaseTurnTransport`에만 있다.
@MainActor
@Observable
final class SupabaseService {
    enum AuthState: Equatable {
        case unknown
        case signedIn(uid: UUID)
        case unavailable(String)
    }

    let client: SupabaseClient
    private(set) var authState: AuthState = .unknown
    private(set) var myMatches: [MatchRow] = []
    /// `link_profile`로 이 uid에 이어 둔 gamePlayerID. 서버는 이어지지 않은 플레이어를 좌석에 적는 것을
    /// 거부하므로, 방을 만들거나 들어갈 때 보내는 값은 로그인 여부가 아니라 이 값으로 가른다.
    private(set) var linkedPlayer: String?

    static let nicknameKey = "online.nickname"

    var nickname: String {
        get { UserDefaults.standard.string(forKey: Self.nicknameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.nicknameKey) }
    }

    init(client: SupabaseClient = SupabaseClient(supabaseURL: SupabaseConfig.url,
                                                 supabaseKey: SupabaseConfig.publishableKey)) {
        self.client = client
    }

    var uid: UUID? {
        if case .signedIn(let uid) = authState { return uid }
        return nil
    }

    /// 익명 로그인. 이미 세션이 있으면 그것을 쓴다.
    func signIn() async {
        do {
            if let session = try? await client.auth.session {
                authState = .signedIn(uid: session.user.id)
            } else {
                let session = try await client.auth.signInAnonymously()
                authState = .signedIn(uid: session.user.id)
            }
            await reloadMatches()
        } catch {
            authState = .unavailable("로그인 실패: \(error.localizedDescription)")
        }
    }

    /// 방을 만든다. 호스트는 대기 방을 하나만 가지므로 먼저 이전 대기 방을 지우고, 코드가 겹치면 다시 뽑는다.
    /// `log`는 게임별 빈 로그다 — 요트는 `MatchLog`, 그 외는 게임이 정하는 모양의 JSON.
    func createRoom(name: String, game: String = "yacht", player: String? = nil) async throws -> MatchRow {
        guard let uid else { throw ServiceError.notSignedIn }
        let log = try Self.initialLog(for: game)
        try await client.from("matches").delete()
            .eq("host_uid", value: uid.uuidString).eq("status", value: "waiting").execute()
        var generator = SystemRandomNumberGenerator()
        var lastError: Error = ServiceError.codeCollision
        for _ in 0..<5 {
            let code = MatchRow.makeCode(using: &generator)
            let insert = NewMatch(code: code, hostUid: uid, hostName: name, log: log, game: game, hostPlayer: player)
            do {
                let row: MatchRow = try await client.from("matches").insert(insert).select().single().execute().value
                return row
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func joinRoom(code: String, name: String, game: String = "yacht", player: String? = nil) async throws -> MatchRow {
        guard uid != nil else { throw ServiceError.notSignedIn }
        let params = try JoinRoomParameters(code: code, name: name, game: game, player: player)
        do {
            return try await client.rpc("join_match", params: params).single().execute().value
        } catch let error as PostgrestError {
            if error.message == "rules version mismatch" { throw ServiceError.rulesVersionMismatch }
            if error.message == "game mismatch" { throw ServiceError.gameMismatch }
            throw error
        }
    }

    static func initialLog(for game: String) throws -> JSONValue {
        let data: Data
        switch game {
        case "yacht": data = try MatchLog(playerCount: 2).encoded()
        case Omok.id: data = try MoveLog<Omok>().encoded()
        case CupPong.id: data = try MoveLog<CupPong>().encoded()
        case Alkkagi.id: data = try MoveLog<Alkkagi>().encoded()
        default: throw ServiceError.unsupportedGame
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    struct JoinRoomParameters: Encodable {
        let code: String
        let name: String
        let game: String
        let player: String?
        let rulesVersion: Int

        init(code: String, name: String, game: String, player: String?) throws {
            self.code = code; self.name = name; self.game = game; self.player = player
            switch game {
            case "yacht": rulesVersion = 1
            case Omok.id: rulesVersion = Omok.rulesVersion
            case CupPong.id: rulesVersion = CupPong.rulesVersion
            case Alkkagi.id: rulesVersion = Alkkagi.rulesVersion
            default: throw ServiceError.unsupportedGame
            }
        }

        enum CodingKeys: String, CodingKey {
            case code = "p_code", name = "p_name", game = "p_game", player = "p_player"
            case rulesVersion = "p_rules_version"
        }
    }

    /// Game Center 로그인 뒤 gamePlayerID ↔ 내 uid를 잇는다.
    /// 앱을 지웠다 깔면 익명 uid가 바뀌어 예전 행의 주인이 아니게 되므로, 직접 upsert하지 않고
    /// `security definer` RPC에 맡긴다 — RLS의 "내 uid 행만 고친다"를 넘어 다시 이어야 하기 때문이다.
    func upsertProfile(player: String, name: String) async {
        guard uid != nil else { return }
        do {
            _ = try await client.rpc("link_profile", params: ["p_player": player, "p_name": name]).execute()
            linkedPlayer = player
        } catch {
            linkedPlayer = nil
        }
    }

    /// 서버 `records` 뷰의 내 줄들. 게임마다 한 줄이다. 읽지 못했으면 nil — 빈 배열(정말 전적이
    /// 없다)과 다르므로, 부르는 쪽이 이미 가진 값을 지우지 않게 가른다.
    func fetchRecords(player: String) async -> [RecordRow]? {
        try? await client.from("records").select().eq("player", value: player).execute().value
    }

    /// 끝난 내 매치를 최근 순으로. RLS가 내가 낀 행만 보여준다. 읽지 못했으면 nil.
    func fetchFinished(limit: Int = 10) async -> [MatchRow]? {
        try? await client.from("matches").select().eq("status", value: "finished")
            .order("updated_at", ascending: false).limit(limit).execute().value
    }

    /// 대기 방 취소나 끝난 판 정리. 참가자만 지울 수 있다(RLS).
    func deleteMatch(id: UUID) async throws {
        try await client.from("matches").delete().eq("id", value: id.uuidString).execute()
        myMatches.removeAll { $0.id == id }
    }

    func fetchMatch(id: UUID) async throws -> MatchRow {
        try await client.from("matches").select().eq("id", value: id.uuidString).single().execute().value
    }

    /// 지금 이 uid로 이어서 둘 수 있는 방만 준다. `matches`는 예전 uid로 둔 판도 gamePlayerID로 이어
    /// 읽히지만(전적용 SELECT 정책) 그런 행은 갱신 정책이 막아 손댈 수 없으므로, 목록에 두면 눌러도
    /// 아무 일이 없는 죽은 줄이 된다 — 좌석 uid가 나인 행만 고른다.
    func reloadMatches() async {
        guard let uid else { return }
        let rows: [MatchRow]? = try? await client.from("matches").select()
            .neq("status", value: "finished")
            .or("host_uid.eq.\(uid.uuidString),guest_uid.eq.\(uid.uuidString)")
            .order("updated_at", ascending: false)
            .execute().value
        myMatches = rows ?? []
    }

    enum ServiceError: LocalizedError {
        case notSignedIn, codeCollision, unsupportedGame, rulesVersionMismatch, gameMismatch
        var errorDescription: String? {
            switch self {
            case .notSignedIn: "로그인되지 않았다"
            case .codeCollision: "방 코드를 만들지 못했다"
            case .unsupportedGame: "아직 지원하지 않는 게임입니다."
            case .rulesVersionMismatch: "상대와 게임 규칙 버전이 다릅니다. 두 기기 모두 최신 버전으로 업데이트한 뒤 새 방을 만들어 주세요."
            case .gameMismatch: "다른 게임의 방 코드입니다. 같은 게임을 선택한 뒤 다시 들어가 주세요."
            }
        }
    }

    private struct NewMatch: Encodable {
        let code: String
        let hostUid: UUID
        let hostName: String
        let log: JSONValue
        let game: String
        let hostPlayer: String?
        enum CodingKeys: String, CodingKey {
            case code, log, game
            case hostUid = "host_uid", hostName = "host_name"
            case hostPlayer = "host_player"
        }
    }
}
