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
    /// 풀어줄 때까지 인증에서 멈춰 서 있는 가짜. 두 호출이 겹치는 순간을 만든다.
    final class Blocking: GameCenterAuthenticating, @unchecked Sendable {
        private(set) var calls = 0
        private let gate: AsyncStream<Void>
        private let opener: AsyncStream<Void>.Continuation

        init() {
            var opener: AsyncStream<Void>.Continuation!
            gate = AsyncStream { opener = $0 }
            self.opener = opener
        }

        func authenticate() async throws -> (playerID: String, name: String) {
            calls += 1
            var iterator = gate.makeAsyncIterator()
            _ = await iterator.next()
            return (playerID: "G:1", name: "정헌")
        }

        func submitScore(_ score: Int, leaderboardID: String) async throws {}

        func open() { opener.finish() }
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

    @Test("겹쳐 불러도 인증은 한 번뿐이고 둘 다 결과를 받는다")
    func 중복_호출() async {
        let fake = Blocking()
        let service = GameCenterService(authenticator: fake)
        let first = Task { await service.authenticate() }
        let second = Task { await service.authenticate() }

        // 첫 호출이 인증에서 멈춘 뒤에도 한참 더 돌려, 둘째 호출이 제자리를 잡게 한다.
        // 겹침을 막지 못한다면 둘째가 여기서 인증을 또 시작한다.
        var spins = 0
        while fake.calls == 0, spins < 1_000 {
            await Task.yield()
            spins += 1
        }
        for _ in 0..<50 { await Task.yield() }
        let 겹친_동안의_호출 = fake.calls
        #expect(겹친_동안의_호출 == 1)

        fake.open()
        await first.value
        await second.value

        #expect(fake.calls == 1)
        #expect(service.authState == .authenticated(playerID: "G:1", name: "정헌"))
    }
}
