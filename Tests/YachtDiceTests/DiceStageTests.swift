import Testing
import Foundation
import simd
import DiceTrajectory
@testable import YachtDice

@Suite("주사위 무대")
@MainActor
struct DiceStageTests {

    @Test("재생이 끝나면 각 주사위가 요청한 눈을 위로 향한다")
    func 재생_결과_일치() async throws {
        let stage = DiceStage(library: try TrajectoryLibrary.bundled())
        let values = [3, 1, 4, 6, 6]
        _ = await stage.roll(values: values, slots: [0, 1, 2, 3, 4],
                             direction: .center, skipAnimation: true)

        for (index, expected) in values.enumerated() {
            #expect(stage.faceUpValue(slot: index) == expected,
                    "슬롯 \(index)에 \(expected)를 요구했는데 \(String(describing: stage.faceUpValue(slot: index)))가 나왔다")
        }
    }

    @Test("keep한 주사위를 제외한 슬롯만 굴린다")
    func 부분_굴림() async throws {
        let stage = DiceStage(library: try TrajectoryLibrary.bundled())
        _ = await stage.roll(values: [1, 2, 3, 4, 5], slots: [0, 1, 2, 3, 4],
                             direction: .center, skipAnimation: true)
        stage.placeHeld([1, 3], values: [1, 2, 3, 4, 5])

        _ = await stage.roll(values: [6, 6, 6], slots: [0, 2, 4],
                             direction: .left, skipAnimation: true)

        #expect(stage.faceUpValue(slot: 0) == 6)
        #expect(stage.faceUpValue(slot: 2) == 6)
        #expect(stage.faceUpValue(slot: 4) == 6)
        #expect(stage.faceUpValue(slot: 1) == 2, "keep한 주사위가 바뀌었다")
        #expect(stage.faceUpValue(slot: 3) == 4, "keep한 주사위가 바뀌었다")
    }

    @Test("애니메이션을 건너뛰면 즉시 끝난다")
    func 감소된_모션() async throws {
        let stage = DiceStage(library: try TrajectoryLibrary.bundled())
        let start = ContinuousClock.now
        _ = await stage.roll(values: [1, 1, 1, 1, 1], slots: [0, 1, 2, 3, 4],
                             direction: .center, skipAnimation: true)
        #expect(ContinuousClock.now - start < .milliseconds(200))
    }

    @Test("같은 눈을 여러 번 굴려도 자세가 매번 같지 않다")
    func 시각적_다양성() async throws {
        let stage = DiceStage(library: try TrajectoryLibrary.bundled())
        var orientations: Set<String> = []
        for _ in 0..<12 {
            _ = await stage.roll(values: [4, 4, 4, 4, 4], slots: [0, 1, 2, 3, 4],
                                 direction: .center, skipAnimation: true)
            let q = stage.orientation(slot: 0)!
            orientations.insert(String(format: "%.2f,%.2f,%.2f,%.2f", q.vector.x, q.vector.y, q.vector.z, q.vector.w))
        }
        #expect(orientations.count > 1, "매번 같은 자세로 멈춘다 — yaw 다양성이 동작하지 않는다")
    }

    @Test("굴림은 충돌 큐를 돌려준다")
    func 충돌_큐() async throws {
        let stage = DiceStage(library: try TrajectoryLibrary.bundled())
        let cues = await stage.roll(values: [2, 5, 1, 3, 6], slots: [0, 1, 2, 3, 4],
                                    direction: .right, skipAnimation: true)
        #expect(!cues.isEmpty, "충돌 큐가 비어 있다 — 사운드와 햅틱을 붙일 수 없다")
    }
}

@Suite("주사위 무대 - 리드인 회전")
@MainActor
struct DiceStageLeadInTests {
    @Test("4개 오프셋 중 지금 자세에서 가장 적게 도는 것을 고른다", arguments: 1...6)
    func 최소_회전(value: Int) throws {
        let library = try TrajectoryLibrary.bundled()
        let trajectory = library.all[0]
        let current = OctahedralGroup.elements[0]
        let chosen = DiceStage.leastRotationYawChoice(
            current: current, trajectory: trajectory, die: 0, showing: value)
        let angles = (0..<4).map { yaw in
            let offset = FaceControl.offset(restUpFace: trajectory.restUpFace(die: 0), showing: value, yawChoice: yaw)
            let start = trajectory.posed(die: 0, frame: 0, offset: offset).orientation
            return DiceStage.rotationAngle(from: current, to: start)
        }
        #expect(angles[chosen] <= angles.min()! + 1e-5, "고른 \(chosen)의 회전 \(angles[chosen])이 최소 \(angles.min()!)가 아니다")
    }

    @Test("회전각: 같은 자세는 0, 90도 돌린 자세는 90도")
    func 회전각() {
        let a = simd_quatf(angle: 0, axis: [0, 1, 0])
        let b = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        #expect(DiceStage.rotationAngle(from: a, to: a) < 1e-5)
        #expect(abs(DiceStage.rotationAngle(from: a, to: b) - .pi / 2) < 1e-4)
        // q와 -q는 같은 회전이다
        #expect(DiceStage.rotationAngle(from: a, to: simd_quatf(vector: -a.vector)) < 1e-5)
    }
}
