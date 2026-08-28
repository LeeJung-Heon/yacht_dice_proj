import SwiftUI
import RealityKit
import simd
import DiceTrajectory

// 브리프의 Result<Trajectory, String>을 그대로 쓰기 위한 최소 확장.
// String은 기본적으로 Error를 준수하지 않는다.
extension String: @retroactive Error {}

@MainActor
@Observable
final class BakerModel {
    var progress = "대기 중"
    var result = BakeResult()
    var isRunning = false

    private var dice: [ModelEntity] = []
    private var root = Entity()

    /// 트레이와 주사위를 만든다. 치수는 TrayGeometry에서만 가져온다.
    func makeScene() -> Entity {
        root = Entity()
        // 트레이와 주사위가 같은 시뮬레이션 루트 아래 있어야 서로 충돌한다 (스파이크 실측)
        root.components.set(PhysicsSimulationComponent())
        let t = TrayGeometry.wallThickness
        let inner = TrayGeometry.trayInner
        let walls: [(size: SIMD3<Float>, offset: SIMD3<Float>)] = [
            ([inner.x, t, inner.z], [0, -t / 2, 0]),
            ([inner.x, inner.y, t], [0, inner.y / 2,  (inner.z + t) / 2]),
            ([inner.x, inner.y, t], [0, inner.y / 2, -(inner.z + t) / 2]),
            ([t, inner.y, inner.z], [ (inner.x + t) / 2, inner.y / 2, 0]),
            ([t, inner.y, inner.z], [-(inner.x + t) / 2, inner.y / 2, 0]),
        ]
        for wall in walls {
            let entity = ModelEntity(
                mesh: .generateBox(size: wall.size),
                materials: [SimpleMaterial(color: .brown, isMetallic: false)]
            )
            entity.position = wall.offset
            let shape = ShapeResource.generateBox(size: wall.size)
            entity.components.set(CollisionComponent(shapes: [shape]))
            entity.components.set(PhysicsBodyComponent(
                shapes: [shape], mass: 0,
                material: .generate(friction: 0.65, restitution: 0.20),
                mode: .static))
            root.addChild(entity)
        }

        dice = (0..<5).map { index in
            let size = TrayGeometry.dieSize
            let entity = ModelEntity(
                mesh: .generateBox(size: size, cornerRadius: size * 0.10),
                materials: [SimpleMaterial(color: .white, isMetallic: false)])
            entity.name = "die\(index)"
            let shape = ShapeResource.generateBox(size: .init(repeating: size))
            entity.components.set(CollisionComponent(shapes: [shape]))
            // massProperties: .init(mass:)를 쓰면 관성이 기본값 0.1로 남아 실제값의 약 47만 배가
            // 되고 주사위가 영원히 돈다. 반드시 형상에서 계산되는 이 생성자를 쓴다 (스파이크 실측).
            entity.components.set(PhysicsBodyComponent(
                shapes: [shape], mass: 0.005,
                material: .generate(friction: 0.55, restitution: 0.30),
                mode: .dynamic))
            entity.components.set(PhysicsMotionComponent())
            root.addChild(entity)
            return entity
        }
        return root
    }

    /// 한 궤적을 굽는다. 주사위를 던지고 멈출 때까지 프레임을 모은다.
    func bakeOne(id: UInt16, dieCount: Int, direction: ThrowDirection,
                 advanceFrame: @MainActor () async -> Void) async -> Result<Trajectory, String> {
        resetDice(dieCount: dieCount, direction: direction)

        var frames: [[DiePose]] = []
        var collisions: [CollisionCue] = []
        var previousSpeeds = [Float](repeating: .infinity, count: dieCount)
        var stillCount = 0

        for frameIndex in 0..<BakePlan.maxFrames {
            await advanceFrame()

            var poses: [DiePose] = []
            var maxSpeed: Float = 0
            for die in 0..<dieCount {
                let entity = dice[die]
                let position = entity.position(relativeTo: nil)
                let orientation = entity.orientation(relativeTo: nil)
                poses.append(DiePose(position: position, orientation: simd_normalize(orientation)))

                // PhysicsMotionComponent의 속도는 잠든 뒤 유령 값이 남아 쓸 수 없다 (스파이크 실측).
                // 위치 차분으로 판정한다.
                let speed = frames.isEmpty ? .infinity
                    : simd_length(position - frames[frames.count - 1][die].position) * Float(BakePlan.frameRate)
                maxSpeed = max(maxSpeed, speed)

                // 속도가 급감하면 충돌로 본다 — 사운드·햅틱 큐로 쓴다
                if previousSpeeds[die].isFinite, previousSpeeds[die] - speed > 0.25 {
                    collisions.append(CollisionCue(
                        frame: UInt16(frameIndex), dieIndex: UInt8(die),
                        intensity: min(1, (previousSpeeds[die] - speed) / 2)))
                }
                previousSpeeds[die] = speed
            }
            frames.append(poses)

            stillCount = maxSpeed < BakePlan.settleThreshold ? stillCount + 1 : 0
            if stillCount >= BakePlan.settleFrames { break }
        }

        guard stillCount >= BakePlan.settleFrames else {
            return .failure("\(BakePlan.maxFrames)프레임 안에 멈추지 않음")
        }

        // 정지 자세는 물리가 만든 그대로 둔다. 축정렬로 스냅하면 안 된다 —
        // 바닥에 누운 주사위는 yaw가 연속적으로 자유로워서 최대 45° 홱 돌아간다 (스펙 §7.3).
        // 기록하는 것은 "위를 향한 눈"뿐이고, 회전 오프셋은 그 값에만 의존한다.
        var restUpFaces: [UInt8] = []
        for die in 0..<dieCount {
            let resting = frames[frames.count - 1][die].orientation
            let tiltDegrees = DieFace.upFaceTiltRadians(for: resting) * 180 / .pi
            guard tiltDegrees <= BakePlan.maxUpFaceTiltDegrees else {
                return .failure("주사위가 기울어 멈춤 (\(String(format: "%.1f", tiltDegrees))도, 벽에 기댄 듯)")
            }
            restUpFaces.append(UInt8(DieFace.upValue(for: resting)))
        }

        let trajectory = Trajectory(
            id: id, dieCount: dieCount, direction: direction, frameRate: BakePlan.frameRate,
            frames: frames, restUpFaces: restUpFaces, collisions: collisions)

        let problems = TrajectoryValidator.problems(
            in: trajectory, trayInner: TrayGeometry.trayInner, dieSize: TrayGeometry.dieSize)
        guard problems.isEmpty else { return .failure(problems[0]) }

        return .success(trajectory)
    }

    /// 던지기 시작 높이. TrayGeometry.shelfHeight(0.16, keep 주사위용 선반)를 그대로 쓰면
    /// TrajectoryValidator의 트레이 상한(trayInner.y + dieSize = 0.136)을 프레임 0부터
    /// 넘어서 거의 모든 궤적이 즉시 기각된다 (실측: 40개 중 39개 기각, "트레이를 벗어났다").
    /// shelfHeight는 Task 13의 keep 선반 위치와 값을 공유해야 하므로 건드리지 않고,
    /// 던지기 전용 높이를 트레이 벽 상단(0.12) 바로 위로 따로 둔다.
    private static let throwHeight: Float = 0.10

    private func resetDice(dieCount: Int, direction: ThrowDirection) {
        let lateral: Float = switch direction {
        case .left: -0.35
        case .center: 0
        case .right: 0.35
        }
        for (index, entity) in dice.enumerated() {
            entity.isEnabled = index < dieCount
            guard index < dieCount else { continue }
            entity.position = [
                Float(index) * TrayGeometry.dieSize * 1.5 - 0.03,
                Self.throwHeight,
                -TrayGeometry.trayInner.z / 2 + 0.02,
            ]
            entity.orientation = simd_normalize(simd_quatf(
                angle: .random(in: 0...(2 * .pi)),
                axis: simd_normalize(SIMD3<Float>.random(in: -1...1))))
            var motion = PhysicsMotionComponent()
            motion.linearVelocity = [lateral + .random(in: -0.1...0.1), -0.5, .random(in: 0.5...0.9)]
            motion.angularVelocity = SIMD3(.random(in: -25...25), .random(in: -25...25), .random(in: -25...25))
            entity.components.set(motion)
        }
    }
}
