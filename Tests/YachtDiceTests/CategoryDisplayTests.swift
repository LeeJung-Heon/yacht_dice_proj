import Testing
import YachtCore
@testable import YachtDice

@Suite("카테고리 표시")
struct CategoryDisplayTests {

    @Test("모든 카테고리에 표시 이름이 있다")
    func 이름_존재() {
        for category in ScoreCategory.allCases {
            #expect(!category.displayName.isEmpty, "\(category)의 표시 이름이 비어 있다")
            #expect(!category.accessibilityDescription.isEmpty, "\(category)의 음성 설명이 비어 있다")
        }
    }

    @Test("표시 이름이 서로 겹치지 않는다")
    func 이름_유일성() {
        let names = ScoreCategory.allCases.map(\.displayName)
        #expect(Set(names).count == names.count, "중복된 표시 이름이 있다")
    }

    @Test("음성 설명이 조건을 알려준다")
    func 음성_설명() {
        #expect(ScoreCategory.yacht.accessibilityDescription.contains("5"))
        #expect(ScoreCategory.fullHouse.accessibilityDescription.contains("3"))
        #expect(ScoreCategory.smallStraight.accessibilityDescription.contains("4"))
    }
}
