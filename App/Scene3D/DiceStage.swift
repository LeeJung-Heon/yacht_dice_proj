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
    /// 각 주사위가 트레이 바닥에서 마지막으로 있던 자리.
    /// keep을 풀었을 때 어디로 돌려보낼지는 이것 말고는 알 방법이 없다.
    private var floorPositions: [SIMD3<Float>] = []

    init(library: TrajectoryLibrary) {
        self.library = library
        root = DiceSceneBuilder.makeRoot()
        dice = DiceSceneBuilder.dice(in: root)
        floorPositions = (0..<dice.count).map(DiceSceneBuilder.restingPosition(slot:))
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

    /// 리드인 길이 (프레임, 60fps 기준 0.2초)와 들어 올리는 높이.
    static let leadInFrames = 12
    static let leadInLift: Float = 0.03

    /// - Parameters:
    ///   - values: 나와야 할 눈. slots와 같은 길이·순서다.
    ///   - slots: 굴릴 주사위 슬롯 (keep되지 않은 것들).
    ///   - skipAnimation: Reduce Motion이 켜져 있으면 true.
    /// - Returns: 재생 중 터뜨릴 충돌 큐. 호출자가 사운드·햅틱에 쓴다.
    func roll(values: [Int], slots: [Int], direction: ThrowDirection,
              skipAnimation: Bool, onCue: ((CollisionCue) -> Void)? = nil) async -> [CollisionCue] {
        precondition(values.count == slots.count, "값과 슬롯의 개수가 다르다")
        guard !slots.isEmpty else { return [] }

        var generator = SystemRandomNumberGenerator()
        // 굴리는 개수 1~5 × 방향 3종 = 15가지 조합 모두에 최소 20개씩 들어 있다는 것을
        // TrajectoryLibraryTests.변형_다양성이 번들 파일에 대해 보장한다.
        guard let trajectory = library.pick(dieCount: slots.count, direction: direction, using: &generator) else {
            assertionFailure("\(slots.count)개 / \(direction) 궤적이 번들에 없다")
            return []
        }

        // 굴리는 각 주사위에 대해 오프셋을 미리 계산한다.
        // 4개 후보 중 지금 자세에서 가장 적게 도는 것을 고른다 — 무작위로 고르면 리드인 0.2초 동안
        // 주사위가 제자리에서 중앙값 100도를 돌아 "던지기 전에 빙글 도는" 것처럼 보였다.
        // 다양성은 궤적 선택이 만든다.
        let offsets = (0..<slots.count).map { lane in
            let yaw = Self.leastRotationYawChoice(
                current: dice[slots[lane]].orientation, trajectory: trajectory, die: lane, showing: values[lane])
            return FaceControl.offset(
                restUpFace: trajectory.restUpFace(die: lane),
                showing: values[lane],
                yawChoice: yaw)
        }

        if skipAnimation {
            applyFrame(trajectory.frameCount - 1, of: trajectory, slots: slots, offsets: offsets)
            for cue in trajectory.collisions { onCue?(cue) }
            return trajectory.collisions
        }
        // 프레임 순으로 정렬돼 있으므로 커서 하나로 그 프레임에 도달할 때마다 알린다
        let cues = trajectory.collisions.sorted { $0.frame < $1.frame }
        var cueCursor = 0

        let frameDuration = Duration.seconds(1.0 / Double(trajectory.frameRate))
        var clock = ContinuousClock.now

        // 리드인: 지금 있는 자리에서 궤적의 첫 자세까지 집어 올리듯 옮긴다.
        // 이게 없으면 주사위가 바닥에서 사라져 앞쪽 공중에 순간이동한 뒤 던져진다.
        let starts = slots.map { dice[$0].position }
        let startOrientations = slots.map { dice[$0].orientation }
        for step in 1...Self.leadInFrames {
            let t = Float(step) / Float(Self.leadInFrames)
            let eased = t * t * (3 - 2 * t)
            for (lane, slot) in slots.enumerated() {
                let target = trajectory.posed(die: lane, frame: 0, offset: offsets[lane])
                var position = simd_mix(starts[lane], target.position, SIMD3(repeating: eased))
                position.y += Self.leadInLift * 4 * eased * (1 - eased)   // 포물선으로 살짝 들어 올린다
                dice[slot].position = position
                dice[slot].orientation = simd_slerp(startOrientations[lane], target.orientation, eased)
            }
            clock += frameDuration
            try? await Task.sleep(until: clock, clock: .continuous)
        }

        for frame in 0..<trajectory.frameCount {
            applyFrame(frame, of: trajectory, slots: slots, offsets: offsets)
            while cueCursor < cues.count, Int(cues[cueCursor].frame) <= frame {
                onCue?(cues[cueCursor])
                cueCursor += 1
            }
            clock += frameDuration
            try? await Task.sleep(until: clock, clock: .continuous)
        }
        // 마지막 프레임을 한 번 더 확정해 반올림 오차를 없앤다
        applyFrame(trajectory.frameCount - 1, of: trajectory, slots: slots, offsets: offsets)
        return trajectory.collisions
    }

    /// 다섯 개 전부의 자리를 정한다 — keep한 것은 뒤쪽 선반 위로, 나머지는 트레이 바닥으로.
    ///
    /// keep을 푼 주사위까지 여기서 책임지지 않으면 그 주사위는 다음 굴림의 applyFrame이
    /// 집어갈 때까지 선반에 남는다. 선반이 화면 밖이던 동안에는 티가 안 났지만,
    /// 선반이 보이는 지금은 "keep을 풀었는데 그대로 올라가 있는" 상태가 그대로 보인다.
    func placeHeld(_ heldSlots: [Int], values: [Int]) {
        let held = Set(heldSlots)
        let sorted = heldSlots.sorted()
        let spacing = TrayGeometry.dieSize * 1.9

        for (order, slot) in sorted.enumerated() {
            guard dice.indices.contains(slot) else { continue }
            let x = (Float(order) - Float(sorted.count - 1) / 2) * spacing
            dice[slot].position = [x, TrayGeometry.shelfDieY, TrayGeometry.shelfDieZ]
            // 선반 위에서는 눈이 정면에서 잘 보이도록 축정렬 자세를 유지한다
            if values.indices.contains(slot),
               let target = OctahedralGroup.elements.first(where: { DieFace.upValue(for: $0) == values[slot] }) {
                dice[slot].orientation = target
            }
        }

        seatOnFloor(dice.indices.filter { !held.contains($0) })
    }

    func reset() {
        for (index, die) in dice.enumerated() {
            die.position = DiceSceneBuilder.restingPosition(slot: index)
            die.orientation = OctahedralGroup.elements[0]
            floorPositions[index] = die.position
        }
    }

    // MARK: - 내부

    /// 두 자세 사이의 회전각(라디안). q와 -q는 같은 회전이다.
    static func rotationAngle(from a: simd_quatf, to b: simd_quatf) -> Float {
        let d = min(1, abs(simd_dot(simd_normalize(a).vector, simd_normalize(b).vector)))
        return 2 * acos(d)
    }

    /// 목표 눈을 만드는 4개 오프셋 중 궤적 첫 프레임 자세가 `current`에서 가장 가까운 것.
    static func leastRotationYawChoice(current: simd_quatf, trajectory: Trajectory, die: Int, showing value: Int) -> Int {
        var best = 0
        var bestAngle = Float.infinity
        for yaw in 0..<4 {
            let offset = FaceControl.offset(restUpFace: trajectory.restUpFace(die: die), showing: value, yawChoice: yaw)
            let start = trajectory.posed(die: die, frame: 0, offset: offset).orientation
            let angle = rotationAngle(from: current, to: start)
            if angle < bestAngle { bestAngle = angle; best = yaw }
        }
        return best
    }

    private func applyFrame(_ frame: Int, of trajectory: Trajectory,
                            slots: [Int], offsets: [simd_quatf]) {
        for (lane, slot) in slots.enumerated() {
            guard dice.indices.contains(slot) else { continue }
            let pose = trajectory.posed(die: lane, frame: frame, offset: offsets[lane])
            dice[slot].position = pose.position
            dice[slot].orientation = pose.orientation
            floorPositions[slot] = pose.position
        }
    }

    /// 바닥에 있어야 할 주사위를 마지막 바닥 위치로 되돌린다.
    /// 이미 바닥에 있는 것부터 자리를 확정하고, 선반에서 내려오는 것은 그 뒤에 끼워 넣는다 —
    /// 굴림이 끝난 배치를 흔들지 않기 위해서다.
    private func seatOnFloor(_ slots: [Int]) {
        let alreadyDown = slots.filter { dice[$0].position.y < TrayGeometry.shelfTop }
        let comingDown = slots.filter { dice[$0].position.y >= TrayGeometry.shelfTop }
        var taken: [SIMD3<Float>] = []
        for slot in alreadyDown + comingDown {
            let seat = clearSeat(floorPositions[slot], avoiding: taken)
            dice[slot].position = seat
            floorPositions[slot] = seat
            taken.append(seat)
        }
    }

    /// 되돌릴 자리에 다른 주사위가 이미 있으면 x축으로 좌우 번갈아 밀어낸다.
    private func clearSeat(_ wanted: SIMD3<Float>, avoiding taken: [SIMD3<Float>]) -> SIMD3<Float> {
        let step = TrayGeometry.dieSize * 1.15
        let limit = TrayGeometry.trayInner.x / 2 - TrayGeometry.dieSize / 2
        var candidate = wanted
        for attempt in 0..<12 {
            if !taken.contains(where: { overlaps($0, candidate) }) { return candidate }
            let shift = Float(attempt / 2 + 1) * step * (attempt.isMultiple(of: 2) ? 1 : -1)
            candidate = wanted
            candidate.x = min(limit, max(-limit, wanted.x + shift))
        }
        return candidate
    }

    private func overlaps(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
        abs(a.x - b.x) < TrayGeometry.dieSize && abs(a.z - b.z) < TrayGeometry.dieSize
    }
}
