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

    /// 방을 만든다. 코드가 겹치면 다시 뽑는다.
    func createRoom(name: String) async throws -> MatchRow {
        guard let uid else { throw ServiceError.notSignedIn }
        var generator = SystemRandomNumberGenerator()
        var lastError: Error = ServiceError.codeCollision
        for _ in 0..<5 {
            let code = MatchRow.makeCode(using: &generator)
            let insert = NewMatch(code: code, hostUid: uid, hostName: name,
                                  log: MatchLog(playerCount: 2))
            do {
                let row: MatchRow = try await client.from("matches").insert(insert).select().single().execute().value
                return row
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func joinRoom(code: String, name: String) async throws -> MatchRow {
        guard uid != nil else { throw ServiceError.notSignedIn }
        let row: MatchRow = try await client
            .rpc("join_match", params: ["p_code": code, "p_name": name])
            .single()
            .execute().value
        return row
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
        let log: MatchLog
        enum CodingKeys: String, CodingKey {
            case code, log
            case hostUid = "host_uid", hostName = "host_name"
        }
    }
}
