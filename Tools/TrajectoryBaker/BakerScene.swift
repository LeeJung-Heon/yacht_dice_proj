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
        // keep 선반도 물리 장애물이다. 앱은 이 띠(shelfFrontZ 뒤)에 선반을 그리므로,
        // 여기 없이 구우면 주사위가 선반 안쪽에서 멈춰 나무 턱에 파묻힌 채로 보인다.
        let shelfDepth = TrayGeometry.shelfFrontZ - TrayGeometry.shelfBackZ
        let shelf: (size: SIMD3<Float>, offset: SIMD3<Float>) = (
            [inner.x, TrayGeometry.shelfTop, shelfDepth],
            [0, TrayGeometry.shelfTop / 2, TrayGeometry.shelfDieZ])
        for wall in walls + [shelf] {
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
            var body = PhysicsBodyComponent(
                shapes: [shape], mass: 0.005,
                material: .generate(friction: 0.6, restitution: 0.30),
                mode: .dynamic)
            // 물리 엔진에는 비틀림 마찰이 없다. 바닥에 평평하게 놓인 주사위의 수직축 회전이 안 죽어서
            // 팽이처럼 제자리에서 돌았다(실측: 29%가 마지막 0.4초에 60도 이상). 각감쇠로 대신한다.
            body.angularDamping = 3.0
            entity.components.set(body)
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

        // 정착 판정에 쓴 대기 프레임은 재생할 가치가 없다. 멈춘 뒤 1초를 가만히 보여주면
        // "던진" 느낌이 아니라 "떨어뜨리고 기다리는" 느낌이 된다. 마지막 움직임 뒤 몇 프레임만 남긴다.
        frames = Self.trimIdleTail(frames, keep: BakePlan.tailFrames)
        collisions = collisions.filter { Int($0.frame) < frames.count }

        // 정지 자세는 물리가 만든 그대로 둔다. 축정렬로 스냅하면 안 된다 —
        // 바닥에 누운 주사위는 yaw가 연속적으로 자유로워서 최대 45° 홱 돌아간다 (스펙 §7.3).
        // 기록하는 것은 "위를 향한 눈"뿐이고, 회전 오프셋은 그 값에만 의존한다.
        var restUpFaces: [UInt8] = []
        for die in 0..<dieCount {
            // 선반 위에 올라앉아 멈춘 주사위는 keep한 것과 구분이 안 된다
            let restZ = frames[frames.count - 1][die].position.z
            guard restZ - TrayGeometry.dieSize / 2 > TrayGeometry.shelfFrontZ else {
                return .failure("선반 위에서 멈춤 (z=\(String(format: "%.3f", restZ)))")
            }
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

        // 화면에 그리는 벽(0.03)보다 위에서 물리 벽(0.12)에 부딪히면 허공에서 튕기는 것처럼 보인다.
        let ghostHits = TrajectoryValidator.wallContactsAboveVisibleWall(
            in: trajectory, trayInner: TrayGeometry.trayInner, dieSize: TrayGeometry.dieSize,
            visibleWallHeight: TrayGeometry.visualWallHeight)
        guard ghostHits == 0 else { return .failure("보이는 벽 위에서 벽에 닿음 (\(ghostHits)프레임)") }

        let duration = Float(frames.count) / Float(BakePlan.frameRate)
        guard duration >= BakePlan.minDurationSeconds else {
            return .failure("너무 짧음 (\(String(format: "%.2f", duration))초)")
        }

        return .success(trajectory)
    }

    /// 마지막으로 눈에 띄게 움직인 프레임 뒤로 `keep`개만 남긴다.
    /// 마지막 프레임은 정착 판정을 통과한 자세이므로 잘라내도 정지 자세는 그대로다 —
    /// 잘린 프레임들은 전부 그 자세와 settleThreshold 이내로 같다.
    static func trimIdleTail(_ frames: [[DiePose]], keep: Int) -> [[DiePose]] {
        guard frames.count > 1 else { return frames }
        let final = frames[frames.count - 1]
        var lastMoving = 0
        for (index, frame) in frames.enumerated() {
            for (die, pose) in frame.enumerated() {
                let moved = simd_length(pose.position - final[die].position) > 0.0004
                let turned = abs(simd_dot(pose.orientation.vector, final[die].orientation.vector)) < cos(0.5 * .pi / 180 / 2)
                if moved || turned { lastMoving = index }
            }
        }
        let end = min(frames.count, lastMoving + 1 + keep)
        // 잘린 뒤에도 마지막 프레임은 원래의 정지 자세여야 한다
        return Array(frames[0..<(end - 1)]) + [final]
    }

    /// 던지기 시작 높이. 손에서 놓는 높이다 — 화면에 그리는 벽(0.03)보다 조금 위, 물리 벽(0.12)보다는
    /// 훨씬 아래. 예전처럼 0.10에서 거의 수직으로 떨어뜨리면 "던진" 게 아니라 "떨어뜨린" 것처럼 보였고,
    /// 0.16에서는 TrajectoryValidator의 상한(0.136)을 넘어 즉시 기각됐다.
    private static let throwHeight: Float = 0.045

    /// 플레이어 쪽(앞, +z) 가장자리에서 트레이 안쪽으로 던진다. 카메라가 앞에서 보므로
    /// 주사위가 손에서 떠나 멀어지며 구르는 것처럼 읽힌다. 예전엔 뒤쪽 벽에서 카메라 쪽으로 던져
    /// 항상 화면 아래 앞벽에 몰려 멈췄다.
    private func resetDice(dieCount: Int, direction: ThrowDirection) {
        // 방향은 "어느 쪽으로 던지는가". 왼쪽으로 쓸어넘기면 주사위가 왼쪽으로 간다.
        let lateral: Float = switch direction {
        case .left: -0.45
        case .center: 0
        case .right: 0.45
        }
        let count = Float(dieCount)
        for (index, entity) in dice.enumerated() {
            entity.isEnabled = index < dieCount
            guard index < dieCount else { continue }
            // 한 손에 쥔 것처럼 앞쪽 가운데에 모아 놓는다. 겹치지 않을 만큼만 띄운다.
            entity.position = [
                (Float(index) - (count - 1) / 2) * TrayGeometry.dieSize * 1.35 + .random(in: -0.003...0.003),
                Self.throwHeight + .random(in: 0...0.012),
                TrayGeometry.trayInner.z / 2 - 0.03 + .random(in: -0.008...0.008),
            ]
            // 시작 자세는 축정렬에 가깝게. 손에서 놓는 주사위는 이미 어느 면이 위든 대략 반듯하다.
            // 무작위 자세로 시작하면 앱의 리드인이 0.2초 동안 중앙값 100도를 제자리에서 돌려야 한다.
            // 눈의 다양성은 회전 오프셋(4개)과 궤적 선택이 만든다 — 시작 자세가 만들 필요가 없다.
            let yaw = simd_quatf(angle: Float(Int.random(in: 0..<4)) * .pi / 2, axis: [0, 1, 0])
            let tilt = simd_quatf(angle: .random(in: -0.25...0.25), axis: simd_normalize(SIMD3<Float>(.random(in: -1...1), 0, .random(in: -1...1))))
            entity.orientation = simd_normalize(tilt * yaw)
            var motion = PhysicsMotionComponent()
            // 뒤로(-z), 살짝 위로. 앞쪽 가장자리에서 0.045 높이로 던지면 약 0.16초 뒤 바닥에 닿으므로
            // 앞 속도 0.55~0.95면 첫 착지가 트레이 가운데(z ≈ 0)가 된다. 이보다 빠르면 공중에서
            // 뒷벽까지 날아가 보이는 벽 위에서 부딪히고(기각), 벽에 맞자마자 멈춰 너무 짧아진다(기각).
            // 구르는 시간은 회전이 만든다.
            motion.linearVelocity = [
                lateral * 0.5 + .random(in: -0.12...0.12),
                .random(in: 0.08...0.30),
                -.random(in: 0.25...0.55),
            ]
            // 회전은 진행 방향(-z)에 수직인 x축 둘레로 — 앞으로 구르는 회전이다. 수직축(y) 성분은 거의 없앤다:
            // 바닥에 닿아도 잘 안 죽어서 주사위가 제자리에서 팽이처럼 도는 원인이었다(실측: 29%가 마지막 0.4초에 60도 이상).
            let tumble: Float = .random(in: 22...42) * (Bool.random() ? 1 : -1)
            motion.angularVelocity = SIMD3(tumble, .random(in: -4...4), .random(in: -12...12))
            entity.components.set(motion)
        }
    }
}
