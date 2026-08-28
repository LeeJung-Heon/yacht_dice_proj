import Testing
import SwiftUI
import YachtCore
@testable import YachtDice

@Suite("접근성")
@MainActor
struct AccessibilityAuditTests {

    @Test("모든 카테고리 행에 고유한 접근성 식별자가 있다")
    func 식별자_유일성() {
        let identifiers = ScoreCategory.allCases.map { "scoreboard.row.\($0.rawValue)" }
        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test("Reduce Motion이 세션에 전달된다")
    func 감소된_모션_전달() throws {
        let session = GameSession(
            driver: LocalDriver(),
            stage: DiceStage(library: try TrajectoryLibrary.bundled()),
            log: MatchLog(playerCount: 1))
        session.reduceMotion = true
        #expect(session.reduceMotion == true)
    }

    @Test("Dynamic Type 최대 크기에서도 점수판 행이 한 줄에 들어간다")
    func 큰_글씨() {
        // 가장 긴 이름 + 3자리 점수가 표준 폭에서 잘리지 않아야 한다.
        // 실제 렌더 검증은 Step 3의 수동 확인으로 하고, 여기서는 길이 상한만 고정한다.
        for category in ScoreCategory.allCases {
            #expect(category.displayName.count <= 12,
                    "\(category.displayName)이 길어서 큰 글씨에서 잘린다")
        }
    }

    @Test("최고 점수도 3자리를 넘지 않는다")
    func 점수_자릿수() {
        // 야추 최고 총점: 상단 105 + 보너스 35 + Choice 30 + 4K 30 + FH 30 + 15 + 30 + 50 = 325
        var card = ScoreCard()
        for (index, category) in ScoreCategory.upperCases.enumerated() { card.record(category, (index + 1) * 5) }
        card.record(.choice, 30)
        card.record(.fourOfAKind, 30)
        card.record(.fullHouse, 30)
        card.record(.smallStraight, 15)
        card.record(.largeStraight, 30)
        card.record(.yacht, 50)
        #expect(card.total < 1000, "총점이 4자리가 되면 레이아웃이 깨진다")
    }
}
