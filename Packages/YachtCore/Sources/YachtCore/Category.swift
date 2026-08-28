import Foundation

/// 야추 12 카테고리. 점수 규칙은 스펙 §4.2 표가 유일한 근거다.
public enum Category: String, CaseIterable, Codable, Hashable, Sendable {
    case aces, deuces, threes, fours, fives, sixes
    case choice, fourOfAKind, fullHouse, smallStraight, largeStraight, yacht

    /// 상단 소계와 63점 보너스에 들어가는 6개.
    public static let upperCases: [Category] = [.aces, .deuces, .threes, .fours, .fives, .sixes]

    public var isUpper: Bool { Category.upperCases.contains(self) }

    /// 이 카테고리에 이 주사위를 기록했을 때의 점수. 조건을 못 채우면 0이다.
    public func score(_ dice: [Int]) -> Int {
        precondition(dice.count == YachtCore.diceCount, "주사위는 정확히 5개여야 한다")
        precondition(dice.allSatisfy { (1...6).contains($0) }, "주사위 눈은 1...6이어야 한다")

        var counts = [Int](repeating: 0, count: 7)   // counts[v] = 눈 v의 개수, counts[0]은 항상 0
        for die in dice { counts[die] += 1 }
        let total = dice.reduce(0, +)
        let present = Set(dice)

        switch self {
        case .aces:   return counts[1] * 1
        case .deuces: return counts[2] * 2
        case .threes: return counts[3] * 3
        case .fours:  return counts[4] * 4
        case .fives:  return counts[5] * 5
        case .sixes:  return counts[6] * 6

        case .choice:
            return total

        case .fourOfAKind:
            // 5개 동일도 "4개 이상"을 만족한다
            return counts.contains(where: { $0 >= 4 }) ? total : 0

        case .fullHouse:
            // 5개 동일을 인정하는 것은 제품 결정이다 (스펙 §4.2)
            if counts.contains(5) { return total }
            return (counts.contains(3) && counts.contains(2)) ? total : 0

        case .smallStraight:
            let runs: [Set<Int>] = [[1, 2, 3, 4], [2, 3, 4, 5], [3, 4, 5, 6]]
            return runs.contains(where: { $0.isSubset(of: present) }) ? 15 : 0

        case .largeStraight:
            return (present == [1, 2, 3, 4, 5] || present == [2, 3, 4, 5, 6]) ? 30 : 0

        case .yacht:
            return counts.contains(5) ? 50 : 0
        }
    }
}
