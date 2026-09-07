import Foundation
import YachtCore

/// 손패의 가치를 매기고, 재굴림의 기대값을 전수 계산한다.
///
/// 평가 함수는 "빈 칸 중 최고 점수 + 상단 보너스 완성 보정"이다. 12턴 전체를 최적화하지 않는다(1-ply).
/// 그 정도로도 사람 평균은 넘고, 계산은 어느 기기에서든 수십 ms다.
public enum HandEvaluator {

    /// 칸별 "보통 이 정도는 나온다"는 기준점. 점수를 이 기준과의 차이로 평가한다.
    ///
    /// 절대 점수로 평가하면 Choice(합계)가 항상 바닥을 깔아 줘서, 확정된 S. Straight 15점보다
    /// "네 개 다시 굴려 합계를 키우는" 쪽을 고르는 어이없는 결정이 나온다. 기준점을 빼면
    /// 스트레이트 15점은 +6, Choice 18점은 -4가 되어 사람의 직관과 맞는다.
    static let baseline: [ScoreCategory: Double] = [
        .aces: 2, .deuces: 5, .threes: 8, .fours: 11, .fives: 13, .sixes: 16,
        .choice: 22, .fourOfAKind: 10, .fullHouse: 9, .smallStraight: 9, .largeStraight: 10, .yacht: 3,
    ]

    /// 모두 0점일 때 버리는 순서. 나오기 어려운 칸부터 버려야 나중에 큰 점수를 잃지 않는다.
    static let scratchOrder: [ScoreCategory] = [
        .yacht, .aces, .largeStraight, .deuces, .fourOfAKind, .smallStraight,
        .fullHouse, .threes, .fours, .fives, .sixes, .choice,
    ]

    /// 빈 칸 중 지금 기록하기 가장 좋은 칸. 점수에 보너스 보정을 더해 비교한다.
    public static func bestCommit(dice: [Int], card: ScoreCard) -> (category: ScoreCategory, points: Int) {
        let open = card.openCategories
        precondition(!open.isEmpty, "기록할 칸이 없다")
        var best: (category: ScoreCategory, worth: Double)?
        for category in open {
            let points = category.score(dice)
            var worth = worth(of: category, points: points, card: card)
            if points == 0 {
                // 0점끼리는 버리는 순서가 앞일수록 좋다. 기준점 차이보다 항상 아래에 두어
                // "0점으로 버리기"가 "점수 내기"를 이기지 못하게 한다.
                let rank = scratchOrder.firstIndex(of: category) ?? scratchOrder.count
                worth = -100 - Double(rank)
            }
            if best == nil || worth > best!.worth { best = (category, worth) }
        }
        return (best!.category, best!.category.score(dice))
    }

    /// 현재 손패의 가치. 기대값 계산의 잎 노드다.
    public static func value(dice: [Int], card: ScoreCard) -> Double {
        var best = -Double.infinity
        for category in card.openCategories {
            best = max(best, worth(of: category, points: category.score(dice), card: card))
        }
        return best
    }

    /// 기준점 대비 이득. 보너스를 완성하면 그만큼 더.
    static func worth(of category: ScoreCategory, points: Int, card: ScoreCard) -> Double {
        Double(points) + bonusBoost(category, points: points, card: card) - (baseline[category] ?? 0)
    }

    /// `holding`의 주사위는 두고 나머지를 한 번 다시 굴렸을 때 `value`의 기대값.
    /// 결과를 순서 없는 눈 조합(중복 조합)으로 묶고 경우의 수로 가중해 6^k 대신 C(k+5,5)개만 평가한다.
    public static func expectedValue(dice: [Int], holding: Set<Int>, card: ScoreCard) -> Double {
        let kept = dice.indices.filter { holding.contains($0) }.map { dice[$0] }
        let free = dice.count - kept.count
        if free == 0 { return value(dice: dice, card: card) }

        var total = 0.0
        var weightSum = 0.0
        for (combo, weight) in multisets(count: free) {
            total += weight * value(dice: kept + combo, card: card)
            weightSum += weight
        }
        return total / weightSum
    }

    /// 32개 부분집합 중 기대값이 가장 큰 고정 집합. 동점이면 더 적게 고정하는 쪽(다시 굴릴 여지).
    public static func bestHoldSet(dice: [Int], card: ScoreCard) -> Set<Int> {
        var best: (holding: Set<Int>, ev: Double) = ([], -Double.infinity)
        for mask in 0..<(1 << dice.count) {
            let holding = Set(dice.indices.filter { mask & (1 << $0) != 0 })
            let ev = expectedValue(dice: dice, holding: holding, card: card)
            if ev > best.ev + 1e-9 || (abs(ev - best.ev) <= 1e-9 && holding.count < best.holding.count) {
                best = (holding, ev)
            }
        }
        return best.holding
    }

    // MARK: - 내부

    /// 이 기록으로 상단 소계가 63을 넘기면 보너스 35점을 함께 얻는 셈이다.
    /// 아직 못 넘기더라도 상단 칸에 "눈×3 이상"을 넣는 것은 보너스 페이스를 지키는 것이므로 살짝 쳐준다.
    static func bonusBoost(_ category: ScoreCategory, points: Int, card: ScoreCard) -> Double {
        guard category.isUpper, card.upperBonus == 0 else { return 0 }
        if card.upperSubtotal + points >= ScoreCard.upperBonusThreshold {
            return Double(ScoreCard.upperBonusPoints)
        }
        let face = ScoreCategory.upperCases.firstIndex(of: category)! + 1
        return points >= face * 3 ? 4 : 0
    }

    /// `count`개 주사위의 눈 중복 조합과 그 경우의 수.
    static func multisets(count: Int) -> [(combo: [Int], weight: Double)] {
        var result: [(combo: [Int], weight: Double)] = []
        func build(_ prefix: [Int], from face: Int) {
            if prefix.count == count {
                result.append((prefix, Double(permutations(of: prefix))))
                return
            }
            for next in face...6 { build(prefix + [next], from: next) }
        }
        build([], from: 1)
        return result
    }

    /// 중복 순열의 수: n! / ∏(같은 눈 개수)!
    static func permutations(of combo: [Int]) -> Int {
        var counts = [Int](repeating: 0, count: 7)
        for face in combo { counts[face] += 1 }
        var result = factorial(combo.count)
        for c in counts where c > 1 { result /= factorial(c) }
        return result
    }

    static func factorial(_ n: Int) -> Int { n <= 1 ? 1 : n * factorial(n - 1) }
}
