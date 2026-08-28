import Testing
@testable import YachtCore

@Suite("게임 상태")
struct GameStateTests {

    @Test("초기 상태는 1턴, 굴림 전이다")
    func 초기상태() {
        let s = GameState(playerCount: 1)
        #expect(s.turnIndex == 1)
        #expect(s.currentPlayer == 0)
        #expect(s.phase == .awaitingFirstRoll)
        #expect(s.rollsUsed == 0)
        #expect(s.rollsRemaining == 3)
        #expect(s.dice == [0, 0, 0, 0, 0])
        #expect(s.held.isEmpty)
        #expect(s.rollableIndices == [0, 1, 2, 3, 4])
    }

    @Test("첫 굴림은 5개 슬롯을 모두 채운다")
    func 첫_굴림() {
        let s = GameState(playerCount: 1).applying(.rolled([3, 1, 4, 6, 6]))
        #expect(s.dice == [3, 1, 4, 6, 6])
        #expect(s.rollsUsed == 1)
        #expect(s.rollsRemaining == 2)
        #expect(s.phase == .rolling)
    }

    @Test("rolled는 keep되지 않은 슬롯에 인덱스 오름차순으로 채워진다")
    func 재굴림_슬롯_매핑() {
        var s = GameState(playerCount: 1).applying(.rolled([1, 2, 3, 4, 5]))
        s = s.applying(.holdToggled(1)).applying(.holdToggled(3))   // held = {1, 3}
        #expect(s.rollableIndices == [0, 2, 4])

        s = s.applying(.rolled([6, 6, 6]))
        // 슬롯 0←6, 2←6, 4←6. keep한 1·3은 그대로.
        #expect(s.dice == [6, 2, 6, 4, 6])
        #expect(s.rollsUsed == 2)
    }

    @Test("hold 토글은 켜고 끌 수 있다")
    func 홀드_토글() {
        var s = GameState(playerCount: 1).applying(.rolled([1, 2, 3, 4, 5]))
        s = s.applying(.holdToggled(2))
        #expect(s.held == [2])
        s = s.applying(.holdToggled(2))
        #expect(s.held.isEmpty)
    }

    @Test("commit은 현재 플레이어의 점수판에 기록한다")
    func 커밋() {
        var s = GameState(playerCount: 1).applying(.rolled([6, 6, 6, 6, 6]))
        s = s.applying(.committed(.yacht, 50))
        #expect(s.scorecards[0].entry(.yacht) == 50)
    }

    @Test("turnAdvanced는 주사위와 홀드를 비우고 다음 플레이어로 넘긴다")
    func 턴_넘김_2인() {
        var s = GameState(playerCount: 2).applying(.rolled([1, 2, 3, 4, 5]))
        s = s.applying(.holdToggled(0)).applying(.committed(.aces, 1)).applying(.turnAdvanced)

        #expect(s.currentPlayer == 1)
        #expect(s.turnIndex == 1, "아직 1턴이 안 끝났다 — 2번 플레이어가 남았다")
        #expect(s.dice == [0, 0, 0, 0, 0])
        #expect(s.held.isEmpty)
        #expect(s.rollsUsed == 0)
        #expect(s.phase == .awaitingFirstRoll)

        s = s.applying(.rolled([2, 2, 2, 2, 2])).applying(.committed(.deuces, 10)).applying(.turnAdvanced)
        #expect(s.currentPlayer == 0)
        #expect(s.turnIndex == 2, "모든 플레이어가 마쳐야 턴이 오른다")
    }

    @Test("turnIndex는 12를 넘지 않는다")
    func 턴_상한() {
        var s = GameState(playerCount: 1)
        for _ in 0..<20 { s = s.applying(.turnAdvanced) }
        #expect(s.turnIndex == 12)
    }

    @Test("gameEnded는 finished로 만든다")
    func 종료() {
        let s = GameState(playerCount: 1).applying(.gameEnded)
        #expect(s.phase == .finished)
    }

    @Test("12칸을 모두 채우면 isAllScored가 참이다")
    func 전부_기록됨() {
        var s = GameState(playerCount: 1)
        #expect(s.isAllScored == false)
        for c in Category.allCases {
            s = s.applying(.rolled([1, 1, 1, 1, 1])).applying(.committed(c, 0)).applying(.turnAdvanced)
        }
        #expect(s.isAllScored == true)
    }

    @Test("같은 이벤트 로그를 리플레이하면 같은 상태가 된다")
    func 리플레이_결정성() {
        let log: [Event] = [
            .rolled([3, 3, 5, 5, 5]), .holdToggled(2), .holdToggled(3), .holdToggled(4),
            .rolled([5, 1]), .committed(.fives, 20), .turnAdvanced,
        ]
        let a = GameState.replaying(log, playerCount: 2)
        let b = GameState.replaying(log, playerCount: 2)
        #expect(a == b)
        #expect(a.scorecards[0].entry(.fives) == 20)
        #expect(a.currentPlayer == 1)
    }
}
