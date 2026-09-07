import Testing
import Foundation
import simd
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

    @Test("멈춘 주사위는 keep 선반 앞에 있다")
    func 선반_앞_정지() throws {
        let library = try TrajectoryLibrary.bundled()
        for trajectory in library.all {
            for pose in trajectory.frames[trajectory.frameCount - 1] {
                // 선반 앞면에 기대어 멈춘 주사위는 정확히 경계에 있고, float16 양자화로 0.01mm쯤 넘는다
                #expect(pose.position.z - TrayGeometry.dieSize / 2 > TrayGeometry.shelfFrontZ - 0.0005,
                        "궤적 \(trajectory.id)의 주사위가 선반 띠 안(z=\(pose.position.z))에서 멈췄다")
            }
        }
    }

    @Test("정착 대기 프레임이 잘려 있다 — 마지막 0.5초 안에 움직임이 있다")
    func 대기_프레임_절단() throws {
        let library = try TrajectoryLibrary.bundled()
        let window = library.all[0].frameRate / 2
        for trajectory in library.all {
            let last = trajectory.frames[trajectory.frameCount - 1]
            let earlier = trajectory.frames[max(0, trajectory.frameCount - 1 - window)]
            let moved = zip(last, earlier).contains { a, b in
                simd_length(a.position - b.position) > 0.0004
                    // 자리는 그대로인데 자세만 마저 도는 주사위도 "움직임"이다 (0.5도 기준)
                    || abs(simd_dot(a.orientation.vector, b.orientation.vector)) < cos(0.5 * .pi / 180 / 2)
            }
            #expect(moved, "궤적 \(trajectory.id)는 마지막 0.5초 동안 아무것도 움직이지 않는다")
        }
    }

    @Test("굴림은 0.6초 이상이다")
    func 최소_길이() throws {
        let library = try TrajectoryLibrary.bundled()
        for trajectory in library.all {
            let seconds = Float(trajectory.frameCount) / Float(trajectory.frameRate)
            #expect(seconds >= 0.6, "궤적 \(trajectory.id)가 \(seconds)초로 너무 짧다")
        }
    }
}
