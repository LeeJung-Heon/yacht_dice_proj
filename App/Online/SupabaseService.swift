import Foundation
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
        try await client.from("matches").delete()
            .eq("host_uid", value: uid.uuidString).eq("status", value: "waiting").execute()
        let log: JSONValue = game == "yacht"
            ? try JSONDecoder().decode(JSONValue.self, from: MatchLog(playerCount: 2).encoded())
            : .object(["moves": .array([])])
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

    func joinRoom(code: String, name: String, player: String? = nil) async throws -> MatchRow {
        guard uid != nil else { throw ServiceError.notSignedIn }
        var params: [String: String] = ["p_code": code, "p_name": name]
        if let player { params["p_player"] = player }
        let row: MatchRow = try await client
            .rpc("join_match", params: params)
            .single()
            .execute().value
        return row
    }

    /// Game Center 로그인 뒤 gamePlayerID ↔ 내 uid를 잇는다.
    /// 앱을 지웠다 깔면 익명 uid가 바뀌어 예전 행의 주인이 아니게 되므로, 직접 upsert하지 않고
    /// `security definer` RPC에 맡긴다 — RLS의 "내 uid 행만 고친다"를 넘어 다시 이어야 하기 때문이다.
    func upsertProfile(player: String, name: String) async {
        guard uid != nil else { return }
        _ = try? await client.rpc("link_profile", params: ["p_player": player, "p_name": name]).execute()
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

    func reloadMatches() async {
        guard uid != nil else { return }
        let rows: [MatchRow]? = try? await client.from("matches").select()
            .neq("status", value: "finished")
            .order("updated_at", ascending: false)
            .execute().value
        myMatches = rows ?? []
    }

    enum ServiceError: LocalizedError {
        case notSignedIn, codeCollision
        var errorDescription: String? {
            switch self {
            case .notSignedIn: "로그인되지 않았다"
            case .codeCollision: "방 코드를 만들지 못했다"
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
