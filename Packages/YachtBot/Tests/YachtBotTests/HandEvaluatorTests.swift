import Testing
import YachtCore
@testable import YachtBot

@Suite("손패 평가")
struct HandEvaluatorTests {

    @Test("빈 칸 중 점수가 가장 높은 칸을 고른다")
    func 최고_기록() {
        let card = ScoreCard()
        let pick = HandEvaluator.bestCommit(dice: [6, 6, 6, 6, 6], card: card)
        #expect(pick.category == .yacht && pick.points == 50)
    }

    @Test("모두 0점이면 가치가 낮은 칸부터 버린다")
    func 버리기_순서() {
        var card = ScoreCard()
        for category in ScoreCategory.upperCases { card.record(category, 0) }
        card.record(.choice, 10)
        // 남은 칸: 4 of a Kind, Full House, S/L Straight, Yacht. 손패 [1,1,2,2,5]는 전부 0점.
        let pick = HandEvaluator.bestCommit(dice: [1, 1, 2, 2, 5], card: card)
        #expect(pick.points == 0)
        #expect(pick.category == .yacht, "가장 나오기 어려운 Yacht부터 버려야 한다: \(pick.category)")
    }

    @Test("상단 보너스를 완성하는 기록은 35점을 더 쳐준다")
    func 보너스_가치() {
        var card = ScoreCard()
        card.record(.aces, 3); card.record(.deuces, 6); card.record(.threes, 9)
        card.record(.fours, 12); card.record(.fives, 15)   // 소계 45, Sixes 18이면 63
        // 6,6,6,1,2: Sixes 18 vs Choice 21. 보너스를 고려하면 Sixes(18+35)가 낫다.
        let pick = HandEvaluator.bestCommit(dice: [6, 6, 6, 1, 2], card: card)
        #expect(pick.category == .sixes)
    }

    @Test("기대값: 6이 셋이면 셋을 고정하는 것이 아무것도 안 고정하는 것보다 낫다")
    func 기대값_비교() {
        let card = ScoreCard()
        let dice = [6, 6, 6, 2, 3]
        let holdThree = HandEvaluator.expectedValue(dice: dice, holding: [0, 1, 2], card: card)
        let holdNone = HandEvaluator.expectedValue(dice: dice, holding: [], card: card)
        let holdAll = HandEvaluator.expectedValue(dice: dice, holding: [0, 1, 2, 3, 4], card: card)
        #expect(holdThree > holdNone)
        #expect(holdThree > holdAll)
        #expect(abs(holdAll - HandEvaluator.value(dice: dice, card: card)) < 1e-9, "전부 고정하면 기대값은 현재 가치다")
    }

    @Test("최적 고정 집합: 6,6,6,2,3 → 6 셋")
    func 최적_고정() {
        #expect(HandEvaluator.bestHoldSet(dice: [6, 6, 6, 2, 3], card: ScoreCard()) == [0, 1, 2])
    }

    @Test("최적 고정 집합: 1,2,3,4,1 은 1234를 고정한다")
    func 스트레이트_고정() {
        let hold = HandEvaluator.bestHoldSet(dice: [1, 2, 3, 4, 1], card: ScoreCard())
        #expect(hold == [0, 1, 2, 3] || hold == [4, 1, 2, 3], "\(hold)")
    }

    @Test("전수 계산이 빠르다 — 32개 집합 전부 0.5초 안")
    func 계산_시간() {
        let start = ContinuousClock.now
        _ = HandEvaluator.bestHoldSet(dice: [1, 2, 3, 4, 5], card: ScoreCard())
        #expect(ContinuousClock.now - start < .milliseconds(500))
    }
}
