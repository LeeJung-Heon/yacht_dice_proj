import Testing
import YachtCore
@testable import YachtBot

@Suite("봇 플레이어")
struct BotPlayerTests {

    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    /// 봇 혼자 한 판을 끝까지 둔다. 굴림은 rng로 만든다.
    private static func play(_ difficulty: BotDifficulty, seed: UInt64,
                             onIntent: (GameState, Intent) -> Void = { _, _ in }) -> GameState {
        var rng = SeededRNG(state: seed)
        let bot = BotPlayer(difficulty: difficulty)
        var state = GameState(playerCount: 1)
        var steps = 0
        while state.phase != .finished && steps < 600 {
            let plan = bot.plan(state, using: &rng)
            if plan.isEmpty { break }
            for intent in plan {
                onIntent(state, intent)
                switch intent {
                case .roll:
                    state = state.applying(.rolled(state.rollableIndices.map { _ in Int(rng.next() % 6) + 1 }))
                case .toggleHold(let i):
                    state = state.applying(.holdToggled(i))
                case .commit(let c):
                    state = state.applying(.committed(c, c.score(state.dice)))
                    state = state.applying(state.isAllScored ? .gameEnded : .turnAdvanced)
                }
                steps += 1
            }
        }
        return state
    }

    @Test("아직 굴리기 전이면 굴린다", arguments: BotDifficulty.allCases)
    func 첫_굴림(difficulty: BotDifficulty) {
        var rng = SeededRNG(state: 1)
        let plan = BotPlayer(difficulty: difficulty).plan(GameState(playerCount: 1), using: &rng)
        #expect(plan == [.roll])
    }

    @Test("굴림이 남았으면 고정 조정 뒤 굴린다 — 어려움은 6 셋을 고정")
    func 고정_후_굴림() {
        var rng = SeededRNG(state: 1)
        let state = GameState(playerCount: 1).applying(.rolled([6, 6, 6, 2, 3]))
        let plan = BotPlayer(difficulty: .hard).plan(state, using: &rng)
        #expect(plan == [.toggleHold(0), .toggleHold(1), .toggleHold(2), .roll])
    }

    @Test("이미 고정된 것은 다시 건드리지 않는다")
    func 고정_유지() {
        var rng = SeededRNG(state: 1)
        let state = GameState(playerCount: 1)
            .applying(.rolled([6, 6, 6, 2, 3]))
            .applying(.holdToggled(0)).applying(.holdToggled(4))   // 0은 맞고 4는 틀림
        let plan = BotPlayer(difficulty: .hard).plan(state, using: &rng)
        #expect(plan == [.toggleHold(1), .toggleHold(2), .toggleHold(4), .roll])
    }

    @Test("굴림이 없으면 기록한다")
    func 기록() {
        var rng = SeededRNG(state: 1)
        var state = GameState(playerCount: 1)
        for _ in 0..<3 { state = state.applying(.rolled(state.rollableIndices.map { _ in 5 })) }
        let plan = BotPlayer(difficulty: .normal).plan(state, using: &rng)
        #expect(plan == [.commit(.yacht)])
    }

    @Test("다 고정할 만큼 좋은 손패면 굴림이 남아도 기록한다")
    func 조기_기록() {
        var rng = SeededRNG(state: 1)
        let state = GameState(playerCount: 1).applying(.rolled([4, 4, 4, 4, 4]))
        let plan = BotPlayer(difficulty: .hard).plan(state, using: &rng)
        #expect(plan == [.commit(.yacht)])
    }

    @Test("계획의 모든 Intent가 순서대로 적용 가능하고 12턴을 끝낸다", arguments: BotDifficulty.allCases)
    func 계획_합법성(difficulty: BotDifficulty) {
        let final = Self.play(difficulty, seed: 7) { state, intent in
            #expect(state.allows(intent), "\(difficulty): \(intent)를 허용하지 않는 상태다")
        }
        #expect(final.phase == .finished, "\(difficulty)가 12턴을 끝내지 못했다")
    }

    @Test("어려움은 쉬움보다 평균 점수가 높다 (60판)")
    func 난이도_차이() {
        let games = 60
        let hard = (0..<games).map { Self.play(.hard, seed: UInt64($0) + 100).scorecards[0].total }.reduce(0, +) / games
        let easy = (0..<games).map { Self.play(.easy, seed: UInt64($0) + 100).scorecards[0].total }.reduce(0, +) / games
        let normal = (0..<games).map { Self.play(.normal, seed: UInt64($0) + 100).scorecards[0].total }.reduce(0, +) / games
        print("BOT AVG hard=\(hard) normal=\(normal) easy=\(easy)")
        #expect(hard > easy + 20, "어려움 \(hard) vs 쉬움 \(easy)")
        #expect(normal > easy, "보통 \(normal) vs 쉬움 \(easy)")
    }
}
