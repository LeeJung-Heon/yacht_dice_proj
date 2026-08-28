import Testing
import Foundation
@testable import YachtCore

@Suite("점수판")
struct ScoreCardTests {

    @Test("빈 점수판은 전부 0이고 완성되지 않았다")
    func 초기상태() {
        let card = ScoreCard()
        #expect(card.upperSubtotal == 0)
        #expect(card.upperBonus == 0)
        #expect(card.total == 0)
        #expect(card.isComplete == false)
        #expect(card.entry(.aces) == nil)
        #expect(card.isFilled(.aces) == false)
    }

    @Test("0점을 기록해도 채워진 것으로 센다")
    func 스크래치() {
        var card = ScoreCard()
        card.record(.yacht, 0)
        #expect(card.isFilled(.yacht) == true)
        #expect(card.entry(.yacht) == 0)
    }

    @Test("상단 소계가 63 미만이면 보너스가 없다")
    func 보너스_미달() {
        var card = ScoreCard()
        for c in Category.upperCases { card.record(c, 10) }   // 60
        #expect(card.upperSubtotal == 60)
        #expect(card.upperBonus == 0)
        #expect(card.total == 60)
    }

    @Test("상단 소계가 정확히 63이면 보너스 35가 붙는다")
    func 보너스_경계() {
        var card = ScoreCard()
        for (i, c) in Category.upperCases.enumerated() { card.record(c, i == 0 ? 13 : 10) }   // 63
        #expect(card.upperSubtotal == 63)
        #expect(card.upperBonus == 35)
        #expect(card.total == 63 + 35)
    }

    @Test("하단 점수는 보너스에 영향을 주지 않는다")
    func 하단은_보너스와_무관() {
        var card = ScoreCard()
        card.record(.yacht, 50)
        #expect(card.upperSubtotal == 0)
        #expect(card.upperBonus == 0)
        #expect(card.total == 50)
    }

    @Test("12칸을 모두 채우면 완성이다")
    func 완성() {
        var card = ScoreCard()
        for c in Category.allCases { card.record(c, 0) }
        #expect(card.isComplete == true)
    }

    @Test("JSON 왕복 후에도 같다")
    func 코더블_왕복() throws {
        var card = ScoreCard()
        card.record(.sixes, 24)
        card.record(.fullHouse, 21)
        let data = try JSONEncoder().encode(card)
        let restored = try JSONDecoder().decode(ScoreCard.self, from: data)
        #expect(restored == card)
    }
}
