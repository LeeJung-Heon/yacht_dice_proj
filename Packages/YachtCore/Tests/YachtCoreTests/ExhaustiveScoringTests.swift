import Testing
@testable import YachtCore

/// 주사위 5개의 모든 조합 6^5 = 7,776가지.
private let allRolls: [[Int]] = {
    var out: [[Int]] = []
    out.reserveCapacity(7_776)
    for a in 1...6 { for b in 1...6 { for c in 1...6 { for d in 1...6 { for e in 1...6 {
        out.append([a, b, c, d, e])
    }}}}}
    return out
}()

/// 프로덕션 구현과 **알고리즘이 다른** 순진한 채점기.
/// 프로덕션이 counts 배열과 Set을 쓰는 데 비해 이쪽은 정렬과 문자열 매칭을 쓴다.
/// 두 구현이 우연히 같은 실수를 하기 어렵게 만드는 것이 목적이다.
private func naiveScore(_ category: Category, _ dice: [Int]) -> Int {
    let sorted = dice.sorted()
    let total = sorted.reduce(0, +)

    func occurrences(of value: Int) -> Int { sorted.filter { $0 == value }.count }
    func hasRun(_ length: Int) -> Bool {
        let unique = Array(Set(sorted)).sorted()
        var run = 1
        var best = 1
        for i in 1..<max(unique.count, 1) where i < unique.count {
            if unique[i] == unique[i - 1] + 1 { run += 1; best = max(best, run) } else { run = 1 }
        }
        return best >= length
    }

    switch category {
    case .aces:   return occurrences(of: 1) * 1
    case .deuces: return occurrences(of: 2) * 2
    case .threes: return occurrences(of: 3) * 3
    case .fours:  return occurrences(of: 4) * 4
    case .fives:  return occurrences(of: 5) * 5
    case .sixes:  return occurrences(of: 6) * 6
    case .choice: return total
    case .fourOfAKind:
        return (1...6).contains(where: { occurrences(of: $0) >= 4 }) ? total : 0
    case .fullHouse:
        let multiplicities = (1...6).map { occurrences(of: $0) }.filter { $0 > 0 }.sorted()
        return (multiplicities == [2, 3] || multiplicities == [5]) ? total : 0
    case .smallStraight:  return hasRun(4) ? 15 : 0
    case .largeStraight:  return hasRun(5) ? 30 : 0
    case .yacht:          return sorted.first == sorted.last ? 50 : 0
    }
}

@Suite("전수 검증")
struct ExhaustiveScoringTests {

    @Test("조합이 정확히 7,776가지다")
    func 조합_개수() {
        #expect(allRolls.count == 7_776)
        #expect(Set(allRolls.map { $0.description }).count == 7_776)
    }

    @Test("7,776 x 12 = 93,312 케이스가 독립 구현과 일치한다")
    func 독립_구현_대조() {
        var mismatches: [String] = []
        var checked = 0
        for dice in allRolls {
            for category in Category.allCases {
                checked += 1
                let mine = category.score(dice)
                let theirs = naiveScore(category, dice)
                if mine != theirs {
                    mismatches.append("\(category) \(dice): 구현 \(mine) vs 독립 \(theirs)")
                }
            }
        }
        #expect(checked == 93_312)
        #expect(mismatches.isEmpty, "불일치 \(mismatches.count)건. 처음 5건: \(mismatches.prefix(5).joined(separator: " | "))")
    }

    @Test("모든 조합에서 규칙 불변식이 성립한다")
    func 불변식() {
        for dice in allRolls {
            let total = dice.reduce(0, +)

            // Choice는 언제나 총합이다
            #expect(Category.choice.score(dice) == total)

            // 라지 스트레이트가 성립하면 스몰도 성립한다
            if Category.largeStraight.score(dice) == 30 {
                #expect(Category.smallStraight.score(dice) == 15, "라지인데 스몰이 아니다: \(dice)")
            }

            // 야추가 성립하면 4 of a Kind와 Full House도 성립한다
            if Category.yacht.score(dice) == 50 {
                #expect(Category.fourOfAKind.score(dice) == total, "야추인데 포카인드가 아니다: \(dice)")
                #expect(Category.fullHouse.score(dice) == total, "야추인데 풀하우스가 아니다: \(dice)")
            }

            // 총합형 카테고리는 0이거나 정확히 총합이다 — 부분합이 나오면 안 된다
            for category in [Category.fourOfAKind, .fullHouse] {
                let s = category.score(dice)
                #expect(s == 0 || s == total, "\(category)가 부분합 \(s)를 냈다: \(dice)")
            }

            // 고정 점수형은 0이거나 정해진 값이다
            #expect([0, 15].contains(Category.smallStraight.score(dice)))
            #expect([0, 30].contains(Category.largeStraight.score(dice)))
            #expect([0, 50].contains(Category.yacht.score(dice)))

            // 상단은 해당 눈 개수 x 눈값이므로 5 x 눈값을 넘을 수 없다
            for (index, category) in Category.upperCases.enumerated() {
                let face = index + 1
                let s = category.score(dice)
                #expect(s % face == 0 && s <= 5 * face, "\(category)가 \(s)를 냈다: \(dice)")
            }
        }
    }

    @Test("전체 점수표의 체크섬이 고정되어 있다")
    func 골든_체크섬() {
        // 규칙을 바꾸면 이 값이 바뀐다. 의도한 변경이면 새 값으로 갱신하고,
        // 의도하지 않았다면 방금 무언가를 깨뜨린 것이다.
        // Swift의 Hasher는 실행마다 시드가 달라져 골든값으로 쓸 수 없으므로
        // 결정적인 두 가지 합계를 직접 만든다.
        var sum = 0
        var weighted = 0
        for (rollIndex, dice) in allRolls.enumerated() {
            for (categoryIndex, category) in Category.allCases.enumerated() {
                let s = category.score(dice)
                sum += s
                weighted += s * (rollIndex % 97 + 1) * (categoryIndex + 1)
            }
        }
        #expect(sum == 305_745, "점수표 총합이 바뀌었다 — 규칙을 의도적으로 바꾼 게 아니면 회귀다")
        #expect(weighted == 91_320_422, "점수표 가중합이 바뀌었다 — 규칙을 의도적으로 바꾼 게 아니면 회귀다")
    }
}
