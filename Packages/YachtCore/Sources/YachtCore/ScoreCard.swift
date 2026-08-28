import Foundation

/// 한 플레이어의 점수판. 기록은 되돌릴 수 없다 (야추 규칙).
public struct ScoreCard: Equatable, Codable, Sendable {
    public static let upperBonusThreshold = 63
    public static let upperBonusPoints = 35

    private var entries: [Category: Int]

    public init() { entries = [:] }

    public func entry(_ category: Category) -> Int? { entries[category] }
    public func isFilled(_ category: Category) -> Bool { entries[category] != nil }

    /// 0점(scratch)도 기록으로 센다. 같은 칸을 두 번 기록하는 것은 호출자의 버그다.
    public mutating func record(_ category: Category, _ points: Int) {
        precondition(entries[category] == nil, "이미 기록된 카테고리다: \(category)")
        entries[category] = points
    }

    public var upperSubtotal: Int {
        Category.upperCases.reduce(0) { $0 + (entries[$1] ?? 0) }
    }

    /// 소계가 63에 도달하는 즉시 확정된다. 12턴 종료를 기다리지 않는다.
    public var upperBonus: Int {
        upperSubtotal >= Self.upperBonusThreshold ? Self.upperBonusPoints : 0
    }

    public var total: Int { entries.values.reduce(0, +) + upperBonus }

    public var isComplete: Bool { entries.count == Category.allCases.count }

    public var openCategories: [Category] { Category.allCases.filter { entries[$0] == nil } }
}
