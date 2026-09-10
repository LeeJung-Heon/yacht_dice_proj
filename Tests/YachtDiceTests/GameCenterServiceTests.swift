import Testing
@testable import YachtDice

@Suite("Game Center 신원")
@MainActor
struct GameCenterServiceTests {
    final class Fake: GameCenterAuthenticating, @unchecked Sendable {
        var result: Result<(playerID: String, name: String), any Error>
        var submitted: [(Int, String)] = []
        init(_ result: Result<(playerID: String, name: String), any Error>) { self.result = result }
        func authenticate() async throws -> (playerID: String, name: String) { try result.get() }
        func submitScore(_ score: Int, leaderboardID: String) async throws { submitted.append((score, leaderboardID)) }
    }
    struct Nope: Error {}

    @Test("인증되면 playerID와 이름이 생기고 리더보드에 제출한다")
    func 인증() async {
        let fake = Fake(.success((playerID: "G:42", name: "정헌")))
        let service = GameCenterService(authenticator: fake)
        await service.authenticate()
        #expect(service.authState == .authenticated(playerID: "G:42", name: "정헌"))
        #expect(service.playerID == "G:42" && service.displayName == "정헌")
        await service.submit(wins: 3, game: .omok)
        #expect(fake.submitted.map { $0.1 } == ["wins.omok"] && fake.submitted.first?.0 == 3)
    }

    @Test("인증에 실패하면 unavailable이고 제출은 조용히 건너뛴다")
    func 실패() async {
        let fake = Fake(.failure(Nope()))
        let service = GameCenterService(authenticator: fake)
        await service.authenticate()
        guard case .unavailable = service.authState else { Issue.record("unavailable이 아니다"); return }
        #expect(service.playerID == nil)
        await service.submit(wins: 1, game: .yacht)
        #expect(fake.submitted.isEmpty)
    }
}
