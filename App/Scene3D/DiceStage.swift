import Foundation
import RealityKit
import SwiftUI
import simd
import DiceTrajectory

/// 결과가 이미 정해진 주사위를 "굴리는 것처럼" 보여준다.
/// 물리를 돌리지 않고 구운 궤적을 재생하며, 각 주사위의 회전에만 오프셋을 곱한다.
@MainActor
final class DiceStage {
    private let library: TrajectoryLibrary
    private var root = Entity()
    private var dice: [ModelEntity] = []
    private(set) var isAnimating = false

    init(library: TrajectoryLibrary) {
        self.library = library
        root = DiceSceneBuilder.makeRoot()
        dice = DiceSceneBuilder.dice(in: root)
    }

    // 이 SDK(iOS 26)에서 `RealityView`는 `RealityViewCameraContent`만 제공하고
    // 예전 iOS 18 GA의 단순한 `RealityViewContent`는 더 이상 없다. 두 콘텐츠
    // 타입 모두 `add(_:)`를 제공하는 `RealityViewContentProtocol`을 따르므로
    // 그 프로토콜로 받으면 어느 쪽이든 동작한다.
    func attach(to content: some RealityViewContentProtocol) {
        content.add(root)
        content.add(DiceSceneBuilder.makeCamera())
    }

    // MARK: - 조회 (테스트와 디버깅용)

    func orientation(slot: Int) -> simd_quatf? {
        guard dice.indices.contains(slot) else { return nil }
        return dice[slot].orientation
    }

    func faceUpValue(slot: Int) -> Int? {
        orientation(slot: slot).map { DieFace.upValue(for: $0) }
    }

    // MARK: - 재생

    /// - Parameters:
    ///   - values: 나와야 할 눈. slots와 같은 길이·순서다.
    ///   - slots: 굴릴 주사위 슬롯 (keep되지 않은 것들).
    ///   - skipAnimation: Reduce Motion이 켜져 있으면 true.
    /// - Returns: 재생 중 터뜨릴 충돌 큐. 호출자가 사운드·햅틱에 쓴다.
    func roll(values: [Int], slots: [Int], direction: ThrowDirection,
              skipAnimation: Bool) async -> [CollisionCue] {
        precondition(values.count == slots.count, "값과 슬롯의 개수가 다르다")
        guard !slots.isEmpty else { return [] }

        var generator = SystemRandomNumberGenerator()
        guard let trajectory = library.pick(dieCount: slots.count, direction: direction, using: &generator) else {
            // 궤적이 없으면 애니메이션 없이 결과만 앉힌다. 게임이 멈추는 것보다 낫다.
            settleImmediately(values: values, slots: slots, generator: &generator)
            return []
        }

        // 굴리는 각 주사위에 대해 오프셋을 미리 계산한다
        let offsets = (0..<slots.count).map { lane in
            FaceControl.offset(
                restUpFace: trajectory.restUpFace(die: lane),
                showing: values[lane],
                yawChoice: Int.random(in: 0..<4, using: &generator))
        }

        if skipAnimation {
            applyFrame(trajectory.frameCount - 1, of: trajectory, slots: slots, offsets: offsets)
            return trajectory.collisions
        }

        isAnimating = true
        defer { isAnimating = false }

        let frameDuration = Duration.seconds(1.0 / Double(trajectory.frameRate))
        var clock = ContinuousClock.now
        for frame in 0..<trajectory.frameCount {
            applyFrame(frame, of: trajectory, slots: slots, offsets: offsets)
            clock += frameDuration
            try? await Task.sleep(until: clock, clock: .continuous)
        }
        // 마지막 프레임을 한 번 더 확정해 반올림 오차를 없앤다
        applyFrame(trajectory.frameCount - 1, of: trajectory, slots: slots, offsets: offsets)
        return trajectory.collisions
    }

    /// keep한 주사위를 트레이 상단 선반으로 올린다.
    func placeHeld(_ heldSlots: [Int], values: [Int]) {
        let spacing = TrayGeometry.dieSize * 1.9
        for (order, slot) in heldSlots.sorted().enumerated() {
            guard dice.indices.contains(slot) else { continue }
            let x = (Float(order) - Float(heldSlots.count - 1) / 2) * spacing
            dice[slot].position = [x, TrayGeometry.shelfHeight, -TrayGeometry.trayInner.z / 2 - 0.02]
            // 선반 위에서는 눈이 정면에서 잘 보이도록 축정렬 자세를 유지한다
            if let target = OctahedralGroup.elements.first(where: { DieFace.upValue(for: $0) == values[slot] }) {
                dice[slot].orientation = target
            }
        }
    }

    func reset() {
        for (index, die) in dice.enumerated() {
            die.isEnabled = true
            die.position = [Float(index - 2) * TrayGeometry.dieSize * 1.6, TrayGeometry.dieSize / 2, 0]
            die.orientation = OctahedralGroup.elements[0]
        }
    }

    // MARK: - 내부

    private func applyFrame(_ frame: Int, of trajectory: Trajectory,
                            slots: [Int], offsets: [simd_quatf]) {
        for (lane, slot) in slots.enumerated() {
            guard dice.indices.contains(slot) else { continue }
            let pose = trajectory.posed(die: lane, frame: frame, offset: offsets[lane])
            dice[slot].position = pose.position
            dice[slot].orientation = pose.orientation
        }
    }

    private func settleImmediately(values: [Int], slots: [Int],
                                   generator: inout some RandomNumberGenerator) {
        for (lane, slot) in slots.enumerated() {
            guard dice.indices.contains(slot) else { continue }
            let candidates = OctahedralGroup.elements.filter { DieFace.upValue(for: $0) == values[lane] }
            dice[slot].orientation = candidates[Int.random(in: 0..<candidates.count, using: &generator)]
            dice[slot].position = [Float(slot - 2) * TrayGeometry.dieSize * 1.6, TrayGeometry.dieSize / 2, 0]
        }
    }
}
