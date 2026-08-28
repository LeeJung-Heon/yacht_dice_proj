import Testing
@testable import YachtCore

@Suite("게임 불변식")
struct GameInvariantTests {

    /// 시드 고정 난수. 실패를 재현할 수 있어야 한다.
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func next() -> UInt64 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return state
        }
    }

    /// 무작위지만 합법적인 한 판을 끝까지 진행하고, 최종 상태와 이벤트 로그를 돌려준다.
    private func playRandomGame(seed: UInt64, playerCount: Int) -> (GameState, [Event]) {
        var rng = SeededRNG(seed: seed)
        var state = GameState(playerCount: playerCount)
        var log: [Event] = []

        func emit(_ event: Event) {
            log.append(event)
            state = state.applying(event)
        }

        while !state.isAllScored {
            // 최소 1회, 최대 3회 굴린다
            let rollCount = Int.random(in: 1...3, using: &rng)
            for roll in 0..<rollCount {
                guard state.allows(.roll) else { break }
                emit(.rolled(state.rollableIndices.map { _ in Int.random(in: 1...6, using: &rng) }))
                // 마지막 굴림 뒤에는 홀드를 만지지 않는다
                if roll < rollCount - 1 {
                    for index in 0..<YachtCore.diceCount where Bool.random(using: &rng) {
                        if state.allows(.toggleHold(index)) { emit(.holdToggled(index)) }
                    }
                }
            }
            let open = state.scorecards[state.currentPlayer].openCategories
            let chosen = open[Int.random(in: 0..<open.count, using: &rng)]
            emit(.committed(chosen, chosen.score(state.dice)))
            emit(.turnAdvanced)
        }
        emit(.gameEnded)
        return (state, log)
    }

    @Test("무작위 100판이 전부 12칸을 채우고 끝난다", arguments: 1...100)
    func 게임은_반드시_완결된다(seed: Int) {
        let (state, _) = playRandomGame(seed: UInt64(seed), playerCount: 2)
        #expect(state.isAllScored)
        #expect(state.phase == .finished)
        for card in state.scorecards {
            #expect(card.isComplete)
            #expect(card.openCategories.isEmpty)
        }
    }

    @Test("총점은 항목 합 + 보너스와 일치한다", arguments: 1...50)
    func 총점_일관성(seed: Int) {
        let (state, _) = playRandomGame(seed: UInt64(seed), playerCount: 2)
        for card in state.scorecards {
            let itemSum = ScoreCategory.allCases.reduce(0) { $0 + (card.entry($1) ?? 0) }
            let expectedBonus = card.upperSubtotal >= ScoreCard.upperBonusThreshold ? 35 : 0
            #expect(card.upperBonus == expectedBonus)
            #expect(card.total == itemSum + expectedBonus)
        }
    }

    @Test("이벤트 로그를 리플레이하면 같은 상태가 나온다", arguments: 1...50)
    func 리플레이_동일성(seed: Int) {
        let (state, log) = playRandomGame(seed: UInt64(seed), playerCount: 2)
        let replayed = GameState.replaying(log, playerCount: 2)
        #expect(replayed == state, "seed \(seed): 리플레이가 원본과 다르다 — P3 재접속이 깨진다")
    }

    @Test("rolled는 keep되지 않은 슬롯에 인덱스 오름차순으로 채워진다")
    func 슬롯_매핑_순서() {
        // Task 5의 같은 이름 테스트는 [6,6,6]을 굴려서 순서를 검증하지 못한다.
        // 값이 전부 같으면 내림차순으로 배정하는 버그도 통과한다. 서로 다른 값으로 다시 건다.
        var state = GameState(playerCount: 1).applying(.rolled([1, 1, 1, 1, 1]))
        state = state.applying(.holdToggled(1)).applying(.holdToggled(3))
        #expect(state.rollableIndices == [0, 2, 4])

        state = state.applying(.rolled([5, 2, 6]))
        #expect(state.dice == [5, 1, 2, 1, 6], "슬롯 0←5, 2←2, 4←6이어야 한다")
    }

    @Test("commit은 0번이 아니라 현재 플레이어의 점수판에 기록된다")
    func 커밋_대상_플레이어() {
        // scorecards[0]으로 하드코딩하는 회귀를 잡는다.
        // Task 5의 테스트는 2번 플레이어의 기록 내용을 확인하지 않는다.
        var state = GameState(playerCount: 2)
        state = state.applying(.rolled([1, 1, 1, 1, 1]))
        state = state.applying(.committed(.aces, 5)).applying(.turnAdvanced)
        #expect(state.currentPlayer == 1)

        state = state.applying(.rolled([2, 2, 2, 2, 2]))
        state = state.applying(.committed(.deuces, 10))

        #expect(state.scorecards[1].entry(.deuces) == 10, "2번 플레이어 점수판에 들어가야 한다")
        #expect(state.scorecards[0].entry(.deuces) == nil, "0번 플레이어 점수판이 오염됐다")
        #expect(state.scorecards[0].entry(.aces) == 5)
    }

    @Test("2인전은 각자 12턴을 갖는다", arguments: 1...20)
    func 턴_수(seed: Int) {
        let (_, log) = playRandomGame(seed: UInt64(seed), playerCount: 2)
        let commits = log.filter { if case .committed = $0 { return true } else { return false } }
        #expect(commits.count == 24, "2인 x 12칸 = 24회 기록이어야 한다")
    }
}
