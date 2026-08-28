import Testing
@testable import YachtCore

@Suite("카테고리 점수")
struct CategoryScoringTests {

    @Test("상단 카테고리는 해당 눈의 합이다", arguments: [
        (Category.aces,   [1, 1, 3, 4, 1], 3),
        (Category.deuces, [2, 2, 2, 4, 5], 6),
        (Category.threes, [1, 2, 4, 5, 6], 0),
        (Category.fours,  [4, 4, 4, 4, 4], 20),
        (Category.fives,  [5, 5, 1, 2, 3], 10),
        (Category.sixes,  [6, 6, 6, 1, 1], 18),
    ])
    func 상단(category: Category, dice: [Int], expected: Int) {
        #expect(category.score(dice) == expected)
    }

    @Test("Choice는 항상 5개 총합이다")
    func choice() {
        #expect(Category.choice.score([1, 2, 3, 4, 5]) == 15)
        #expect(Category.choice.score([6, 6, 6, 6, 6]) == 30)
    }

    @Test("4 of a Kind는 같은 눈 4개 이상일 때 5개 총합이다", arguments: [
        ([6, 6, 6, 6, 2], 26),   // 레퍼런스 사진의 26
        ([3, 3, 3, 3, 3], 15),   // 5개 동일도 만족한다
        ([6, 6, 6, 2, 2], 0),    // 3개뿐
        ([1, 2, 3, 4, 5], 0),
    ])
    func 포카인드(dice: [Int], expected: Int) {
        #expect(Category.fourOfAKind.score(dice) == expected)
    }

    @Test("Full House는 3+2일 때 5개 총합이고 5개 동일도 인정한다", arguments: [
        ([3, 3, 3, 2, 2], 13),
        ([6, 6, 6, 6, 6], 30),   // 5개 동일 인정
        ([6, 6, 6, 6, 2], 0),    // 4+1은 풀하우스가 아니다
        ([1, 1, 2, 2, 3], 0),    // 2+2+1
        ([1, 2, 3, 4, 5], 0),
    ])
    func 풀하우스(dice: [Int], expected: Int) {
        #expect(Category.fullHouse.score(dice) == expected)
    }

    @Test("S. Straight는 연속 4개면 15점 고정이다", arguments: [
        ([1, 2, 3, 4, 6], 15),
        ([2, 3, 4, 5, 5], 15),
        ([3, 4, 5, 6, 1], 15),
        ([1, 2, 3, 4, 5], 15),   // 라지 스트레이트는 스몰도 만족한다
        ([1, 2, 3, 5, 6], 0),
        ([1, 1, 2, 3, 4], 15),   // 중복이 있어도 연속 4개가 있으면 인정
    ])
    func 스몰스트레이트(dice: [Int], expected: Int) {
        #expect(Category.smallStraight.score(dice) == expected)
    }

    @Test("L. Straight는 연속 5개면 30점 고정이다", arguments: [
        ([1, 2, 3, 4, 5], 30),
        ([2, 3, 4, 5, 6], 30),
        ([1, 2, 3, 4, 6], 0),
        ([1, 1, 2, 3, 4], 0),
    ])
    func 라지스트레이트(dice: [Int], expected: Int) {
        #expect(Category.largeStraight.score(dice) == expected)
    }

    @Test("Yacht는 5개 동일이면 50점 고정이다")
    func 야추() {
        #expect(Category.yacht.score([4, 4, 4, 4, 4]) == 50)
        #expect(Category.yacht.score([4, 4, 4, 4, 1]) == 0)
    }

    @Test("상단 6개만 isUpper다")
    func 상단_구분() {
        #expect(Category.upperCases.count == 6)
        #expect(Category.allCases.count == 12)
        #expect(Category.allCases.filter(\.isUpper) == Category.upperCases)
    }
}
