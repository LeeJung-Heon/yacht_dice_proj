import simd
import Testing
@testable import DiceTrajectory

@Test func 포맷_버전이_1이다() {
    #expect(DiceTrajectory.formatVersion == 1)
}

@Suite("보이는 벽 위 접촉")
struct GhostWallTests {
    private func trajectory(positions: [SIMD3<Float>]) -> Trajectory {
        Trajectory(id: 0, dieCount: 1, direction: .center, frameRate: 60,
                   frames: positions.map { [DiePose(position: $0, orientation: simd_quatf(angle: 0, axis: [0, 1, 0]))] },
                   restUpFaces: [1], collisions: [])
    }

    @Test("벽에 닿을 만큼 가깝고 보이는 벽보다 높은 프레임만 센다")
    func 유령_벽() {
        let inner = SIMD3<Float>(0.24, 0.12, 0.24)
        let t = trajectory(positions: [
            [0, 0.05, 0],          // 가운데 공중 — 벽과 무관
            [0.115, 0.05, 0],      // 오른쪽 벽에 닿음, 바닥이 0.042 > 0.03 → 유령
            [0.115, 0.02, 0],      // 오른쪽 벽에 닿음, 낮음 → 정상
            [0, 0.06, -0.116],     // 뒷벽에 닿음, 높음 → 유령
        ])
        let count = TrajectoryValidator.wallContactsAboveVisibleWall(
            in: t, trayInner: inner, dieSize: 0.016, visibleWallHeight: 0.03)
        #expect(count == 2)
    }
}
