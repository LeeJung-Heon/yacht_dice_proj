import Foundation
import DiceTrajectory

/// 번들에 구워 넣은 궤적을 조합별로 찾아준다.
final class TrajectoryLibrary: Sendable {
    let all: [Trajectory]
    private let index: [Key: [Trajectory]]
    private let byID: [UInt16: Trajectory]

    private struct Key: Hashable {
        let dieCount: Int
        let direction: ThrowDirection
    }

    enum LoadFailure: Error {
        case resourceMissing
    }

    init(data: Data) throws {
        all = try TrajectoryArchive.decode(data)
        index = Dictionary(grouping: all) { Key(dieCount: $0.dieCount, direction: $0.direction) }
        byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 상대가 보낸 힌트의 궤적. 없으면 nil.
    func trajectory(id: UInt16) -> Trajectory? { byID[id] }

    static func bundled() throws -> TrajectoryLibrary {
        guard let url = Bundle.main.url(forResource: "trajectories", withExtension: "bin") else {
            throw LoadFailure.resourceMissing
        }
        return try TrajectoryLibrary(data: try Data(contentsOf: url))
    }

    var count: Int { all.count }

    func pick(dieCount: Int, direction: ThrowDirection,
              using generator: inout some RandomNumberGenerator) -> Trajectory? {
        let candidates = index[Key(dieCount: dieCount, direction: direction)] ?? []
        return candidates.randomElement(using: &generator)
    }
}
