import Testing
import Foundation
import DiceTrajectory
@testable import YachtDice

@Suite("궤적 라이브러리")
struct TrajectoryLibraryTests {

    @Test("번들에 궤적 파일이 들어 있다")
    func 번들_로딩() throws {
        let library = try TrajectoryLibrary.bundled()
        #expect(library.count > 0, "trajectories.bin이 앱 번들에 포함되지 않았다")
    }

    @Test("굴리는 개수 1~5, 방향 3종 모두에 궤적이 있다")
    func 조합_커버리지() throws {
        let library = try TrajectoryLibrary.bundled()
        var rng = SystemRandomNumberGenerator()
        for dieCount in 1...5 {
            for direction in ThrowDirection.allCases {
                let picked = library.pick(dieCount: dieCount, direction: direction, using: &rng)
                #expect(picked != nil, "\(dieCount)개 / \(direction) 궤적이 없다")
                #expect(picked?.dieCount == dieCount)
                #expect(picked?.direction == direction)
            }
        }
    }

    @Test("번들된 모든 궤적이 검증기를 통과한다")
    func 전체_검증() throws {
        let library = try TrajectoryLibrary.bundled()
        var failures: [String] = []
        for trajectory in library.all {
            let problems = TrajectoryValidator.problems(
                in: trajectory, trayInner: TrayGeometry.trayInner, dieSize: TrayGeometry.dieSize)
            if !problems.isEmpty { failures.append("궤적 \(trajectory.id): \(problems[0])") }
        }
        #expect(failures.isEmpty, "검증 실패 \(failures.count)건. 처음 3건: \(failures.prefix(3).joined(separator: " | "))")
    }

    @Test("각 조합에 최소 20개의 변형이 있다")
    func 변형_다양성() throws {
        let library = try TrajectoryLibrary.bundled()
        for dieCount in 1...5 {
            for direction in ThrowDirection.allCases {
                let matching = library.all.filter { $0.dieCount == dieCount && $0.direction == direction }
                #expect(matching.count >= 20, "\(dieCount)개/\(direction)에 \(matching.count)개뿐이다 — 굴림이 반복적으로 보인다")
            }
        }
    }
}
