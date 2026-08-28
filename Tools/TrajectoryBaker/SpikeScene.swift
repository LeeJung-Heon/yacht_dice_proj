import SwiftUI
import RealityKit
import simd
import Foundation

/// 스파이크 전용. Task 12에서 정식 베이커로 대체되거나 흡수된다.
/// 브리프와 달리 화면 List 대신 stdout으로 결과를 찍고 스스로 exit(0) 한다.
/// 환경변수로 파라미터를 바꿔 A' 재시도(마찰/반발/질량관성/댐핑)를 할 수 있게 해두었다.

// MARK: - 설정 (환경변수 knob)

struct SpikeConfig {
    var massMode: String      // "manual" (브리프 원안) | "shapes" (형상에서 관성 계산)
    var friction: Float
    var restitution: Float
    var linearDamping: Float
    var angularDamping: Float
    var cornerRadiusRatio: Float
    var maxSeconds: Double
    var trace: Bool

    static func fromEnvironment() -> SpikeConfig {
        func f(_ k: String, _ d: Float) -> Float { ProcessInfo.processInfo.environment[k].flatMap(Float.init) ?? d }
        func d(_ k: String, _ dv: Double) -> Double { ProcessInfo.processInfo.environment[k].flatMap(Double.init) ?? dv }
        func s(_ k: String, _ dv: String) -> String { ProcessInfo.processInfo.environment[k] ?? dv }
        return SpikeConfig(
            massMode: s("BAKER_MASS", "manual"),
            friction: f("BAKER_FRICTION", 0.5),
            restitution: f("BAKER_RESTITUTION", 0.35),
            linearDamping: f("BAKER_LINDAMP", 0),
            angularDamping: f("BAKER_ANGDAMP", 0),
            cornerRadiusRatio: f("BAKER_CORNER", 0.12),
            maxSeconds: d("BAKER_SECONDS", 15),
            trace: s("BAKER_TRACE", "0") == "1"
        )
    }

    var description: String {
        "mass=\(massMode) fric=\(friction) rest=\(restitution) linDamp=\(linearDamping) angDamp=\(angularDamping) corner=\(cornerRadiusRatio) sec=\(maxSeconds)"
    }
}

nonisolated(unsafe) let spikeConfig = SpikeConfig.fromEnvironment()

/// 결정성 확인용 고정 시드 RNG. BAKER_SEED가 있으면 초기조건을 재현한다.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

nonisolated(unsafe) var spikeRNG: SplitMix64? = ProcessInfo.processInfo.environment["BAKER_SEED"]
    .flatMap(UInt64.init).map { SplitMix64(state: $0) }

@MainActor func rnd(_ range: ClosedRange<Float>) -> Float {
    if spikeRNG != nil { return Float.random(in: range, using: &spikeRNG!) }
    return Float.random(in: range)
}

// MARK: - 축정렬 자세 (스파이크용 간이 생성)

enum SpikeAxis {
    /// 스파이크용 간이 생성. 정식 구현은 Task 9의 OctahedralGroup.
    nonisolated(unsafe) static let axisAlignedOrientations: [simd_quatf] = {
        var out: [simd_quatf] = []
        let quarter: [Float] = [0, .pi / 2, .pi, 3 * .pi / 2]
        for x in quarter { for y in quarter { for z in quarter {
            let q = simd_normalize(simd_quatf(angle: z, axis: [0, 0, 1])
                                 * simd_quatf(angle: y, axis: [0, 1, 0])
                                 * simd_quatf(angle: x, axis: [1, 0, 0]))
            if !out.contains(where: { abs(simd_dot($0.vector, q.vector)) > 0.9999 }) { out.append(q) }
        }}}
        return out
    }()

    /// 24개 축정렬 자세 중 가장 가까운 것과의 각도 차이 (도).
    static func alignmentErrorDegrees(_ q: simd_quatf) -> Float {
        var best: Float = .pi
        let qn = simd_normalize(q.vector)
        for candidate in axisAlignedOrientations {
            let d = min(1, abs(simd_dot(qn, simd_normalize(candidate.vector))))
            best = min(best, 2 * acos(d))
        }
        return best * 180 / .pi
    }

    /// 주사위 로컬 ±축 6개 중 월드 +Y에 가장 가까운 것의 각도 오차 (도).
    /// "윗면이 얼마나 수평인가"만 본다 — 눈 판정에 실제로 필요한 값.
    static func upFaceErrorDegrees(_ q: simd_quatf) -> Float {
        let axes: [SIMD3<Float>] = [[1,0,0], [-1,0,0], [0,1,0], [0,-1,0], [0,0,1], [0,0,-1]]
        var best: Float = .pi
        for a in axes {
            let w = simd_normalize(q.act(a))
            best = min(best, acos(min(1, max(-1, w.y))))
        }
        return best * 180 / .pi
    }
}

// MARK: - 관찰 상태

@MainActor
final class SpikeState {
    var dice: [ModelEntity] = []
    var sub: EventSubscription?
    var collisionSub: EventSubscription?
    var updateFrames = 0
    var updateEverFired = false
    var q2Readable: Bool?
    var q3VelocityReadable: Bool?
    var q3VelocityEverNonZero = false
    var maxTravel: Float = 0
    var startPositions: [SIMD3<Float>] = []
    var dieDieContacts = 0
    var dieWallContacts = 0
}

// MARK: - 씬

struct SpikeScene: View {
    // 트레이 안쪽 치수 (미터). 실물 주사위 16mm 기준으로 잡았다.
    static let trayInner = SIMD3<Float>(0.24, 0.12, 0.24)
    static let dieSize: Float = 0.016

    @State private var state = SpikeState()

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "root"
            root.components.set(Self.makeSimulation())
            content.add(root)

            root.addChild(Self.makeTray())
            let dice = Self.makeDice()
            for d in dice { root.addChild(d) }
            Self.throwDice(dice)

            let camera = Entity()
            camera.components.set(PerspectiveCameraComponent())
            camera.look(at: .zero, from: [0, 0.35, 0.30], relativeTo: nil)
            content.add(camera)

            let s = state
            s.dice = dice
            s.startPositions = dice.map { $0.position(relativeTo: nil) }
            s.sub = content.subscribe(to: SceneEvents.Update.self) { _ in
                MainActor.assumeIsolated {
                    s.updateFrames += 1
                    s.updateEverFired = true
                }
            }
            s.collisionSub = content.subscribe(to: CollisionEvents.Began.self) { e in
                MainActor.assumeIsolated {
                    let a = e.entityA.name.hasPrefix("die")
                    let b = e.entityB.name.hasPrefix("die")
                    if a && b { s.dieDieContacts += 1 } else if a || b { s.dieWallContacts += 1 }
                }
            }
        } update: { _ in
        }
        .frame(minWidth: 480, minHeight: 360)
        .task { await observe() }
    }

    // MARK: 씬 구성

    static func makeSimulation() -> PhysicsSimulationComponent {
        var sim = PhysicsSimulationComponent()
        sim.gravity = [0, -9.81, 0]
        return sim
    }

    static func makeTray() -> Entity {
        let tray = Entity()
        tray.name = "tray"
        let t: Float = 0.01   // 벽 두께
        let walls: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([trayInner.x, t, trayInner.z], [0, -t / 2, 0]),                                  // 바닥
            ([trayInner.x, trayInner.y, t], [0, trayInner.y / 2,  (trayInner.z + t) / 2]),    // 앞
            ([trayInner.x, trayInner.y, t], [0, trayInner.y / 2, -(trayInner.z + t) / 2]),    // 뒤
            ([t, trayInner.y, trayInner.z], [ (trayInner.x + t) / 2, trayInner.y / 2, 0]),    // 우
            ([t, trayInner.y, trayInner.z], [-(trayInner.x + t) / 2, trayInner.y / 2, 0]),    // 좌
        ]
        for (size, offset) in walls {
            let mesh = MeshResource.generateBox(size: size)
            let e = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .brown, isMetallic: false)])
            e.position = offset
            e.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
            e.components.set(PhysicsBodyComponent(massProperties: .default,
                                                  material: .generate(friction: 0.6, restitution: 0.25),
                                                  mode: .static))
            tray.addChild(e)
        }
        return tray
    }

    @MainActor static func makeDice() -> [ModelEntity] {
        let cfg = spikeConfig
        let shape = ShapeResource.generateBox(size: .init(repeating: dieSize))
        let material = PhysicsMaterialResource.generate(friction: cfg.friction, restitution: cfg.restitution)
        return (0..<5).map { i in
            let mesh = MeshResource.generateBox(size: dieSize, cornerRadius: dieSize * cfg.cornerRadiusRatio)
            let e = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .white, isMetallic: false)])
            e.name = "die\(i)"
            e.position = [Float(i - 2) * dieSize * 1.6, 0.14, 0]
            e.orientation = simd_quatf(angle: rnd(0...(2 * .pi)),
                                       axis: simd_normalize([rnd(-1...1), rnd(-1...1), rnd(-1...1)]))
            e.components.set(CollisionComponent(shapes: [shape]))

            var body: PhysicsBodyComponent
            if cfg.massMode == "shapes" {
                // 형상에서 관성 텐서를 계산하게 한다
                body = PhysicsBodyComponent(shapes: [shape], mass: 0.005, material: material, mode: .dynamic)
            } else {
                // 브리프 원안: 질량만 지정 (관성 텐서는 RealityKit 기본값)
                body = PhysicsBodyComponent(massProperties: .init(mass: 0.005),
                                            material: material, mode: .dynamic)
            }
            body.linearDamping = cfg.linearDamping
            body.angularDamping = cfg.angularDamping
            e.components.set(body)
            e.components.set(PhysicsMotionComponent())
            return e
        }
    }

    @MainActor static func throwDice(_ dice: [ModelEntity]) {
        for d in dice {
            var motion = PhysicsMotionComponent()
            motion.linearVelocity = [rnd(-0.6...(-0.2)), -0.4, rnd(-0.3...0.3)]
            motion.angularVelocity = [rnd(-30...30), rnd(-30...30), rnd(-30...30)]
            d.components.set(motion)
        }
    }

    // MARK: 관찰 루프

    @MainActor func observe() async {
        let cfg = spikeConfig
        let s = state
        var previous: [SIMD3<Float>] = []
        var previousOrientations: [simd_quatf] = []
        var stillFrames = 0
        var velStillFrames = 0
        var settledPoll: Int?
        var settledSeconds: Double?
        var deltaSettledPoll: Int?
        var deltaSettledSeconds: Double?
        var lastRotDelta: Float = .infinity
        var trace: [String] = []
        let t0 = Date()

        for _ in 0..<200 where s.dice.isEmpty {
            try? await Task.sleep(for: .milliseconds(16))
        }
        guard s.dice.count == 5 else {
            emit(["FATAL: 주사위 엔티티를 잡지 못했다 (count=\(s.dice.count))"]); return
        }

        // 관성 텐서를 실제로 확인한다 (관성이 형상과 맞는지)
        let inertiaLine: String
        if let mp = s.dice[0].components[PhysicsBodyComponent.self]?.massProperties {
            inertiaLine = "massProperties mass=\(mp.mass) inertia=\(mp.inertia)"
        } else { inertiaLine = "massProperties 읽기 불가" }

        let maxPolls = Int(cfg.maxSeconds * 60)
        var pollsSeen = 0
        var lastLinear: Float = .infinity
        var lastAngular: Float = .infinity
        var lastDiffSpeed: Float = .infinity

        for poll in 0..<maxPolls {
            try? await Task.sleep(for: .milliseconds(16))
            pollsSeen = poll
            let dice = s.dice
            let positions = dice.map { $0.position(relativeTo: nil) }
            let motions = dice.map { $0.components[PhysicsMotionComponent.self] }
            let velocityReadable = motions.allSatisfy { $0 != nil }

            if s.q2Readable == nil {
                s.q2Readable = positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
            }
            if s.q3VelocityReadable == nil { s.q3VelocityReadable = velocityReadable }

            let linear = motions.compactMap { $0 }.map { simd_length($0.linearVelocity) }.max() ?? 0
            let angular = motions.compactMap { $0 }.map { simd_length($0.angularVelocity) }.max() ?? 0
            if linear > 1e-4 || angular > 1e-4 { s.q3VelocityEverNonZero = true }
            lastLinear = linear; lastAngular = angular

            let diffSpeed: Float
            if previous.count == positions.count {
                diffSpeed = zip(previous, positions).map { simd_length($1 - $0) * 60 }.max() ?? 0
            } else { diffSpeed = .infinity }
            previous = positions
            lastDiffSpeed = diffSpeed

            if s.startPositions.count == positions.count {
                let travel = zip(s.startPositions, positions).map { simd_length($1 - $0) }.max() ?? 0
                s.maxTravel = max(s.maxTravel, travel)
            }

            if cfg.trace && poll % 15 == 0 {
                let ys = positions.map { String(format: "%.4f", $0.y) }.joined(separator: ",")
                let errs = dice.map { String(format: "%.1f", SpikeAxis.upFaceErrorDegrees($0.orientation(relativeTo: nil))) }.joined(separator: ",")
                trace.append(String(format: "TRACE t=%.2f lin=%.5f ang=%.5f diff=%.5f y=[%@] upErr=[%@]",
                                    Double(poll) / 60, linear, angular,
                                    diffSpeed.isFinite ? diffSpeed : -1, ys, errs))
            }

            // 정지 판정 A: 브리프의 속도 임계 (linear<0.002, angular<0.05)
            let useVelocity = velocityReadable && s.q3VelocityEverNonZero
            let stoppedByVelocity = useVelocity ? (linear < 0.002 && angular < 0.05)
                                                : (diffSpeed.isFinite && diffSpeed < 0.002)
            velStillFrames = stoppedByVelocity ? velStillFrames + 1 : 0
            if velStillFrames >= 30 && settledPoll == nil {
                settledPoll = poll
                settledSeconds = Date().timeIntervalSince(t0)
            }

            // 정지 판정 B: 위치·자세 차분 (프레임 사이 실제 변화량)
            let orientations = dice.map { $0.orientation(relativeTo: nil) }
            var maxRotDelta: Float = 0
            if previousOrientations.count == orientations.count {
                for (a, b) in zip(previousOrientations, orientations) {
                    let d = min(1, abs(simd_dot(simd_normalize(a.vector), simd_normalize(b.vector))))
                    maxRotDelta = max(maxRotDelta, 2 * acos(d) * 180 / .pi)
                }
            } else { maxRotDelta = .infinity }
            previousOrientations = orientations
            lastRotDelta = maxRotDelta

            // 0.02°는 float acos의 수치 잡음 바닥(약 0.04~0.06°)보다 낮아 절대 성립하지 않았다. 0.1°로 올린다.
            let stoppedByDelta = diffSpeed.isFinite && diffSpeed < 0.0005 && maxRotDelta < 0.1
            stillFrames = stoppedByDelta ? stillFrames + 1 : 0
            if stillFrames >= 30 && deltaSettledPoll == nil {
                deltaSettledPoll = poll
                deltaSettledSeconds = Date().timeIntervalSince(t0)
            }

            if deltaSettledPoll != nil && settledPoll != nil { break }
            if deltaSettledPoll != nil && poll > (deltaSettledPoll! + 60) { break }
        }

        var lines: [String] = []
        lines.append("RUN_START")
        lines.append("CONFIG \(cfg.description)")
        lines.append(inertiaLine)
        lines.append("axisAlignedOrientations count = \(SpikeAxis.axisAlignedOrientations.count)")
        lines.append("SceneEvents.Update fired = \(s.updateEverFired) frames=\(s.updateFrames)")
        lines.append(contentsOf: trace)
        lines.append(String(format: "Q1 최대 이동거리 = %.4f m", s.maxTravel))
        for (i, p) in s.dice.map({ $0.position(relativeTo: nil) }).enumerated() {
            let inside = abs(p.x) <= Self.trayInner.x / 2 + 0.02
                      && abs(p.z) <= Self.trayInner.z / 2 + 0.02
                      && p.y > -0.02 && p.y < Self.trayInner.y + 0.02
            lines.append(String(format: "  die%d 최종위치 (%.4f, %.4f, %.4f) %@",
                                i, p.x, p.y, p.z, inside ? "트레이안" : "트레이밖!"))
        }
        lines.append("Q1 충돌: die-die=\(s.dieDieContacts) die-wall=\(s.dieWallContacts)")
        if let dp = deltaSettledPoll, let ds = deltaSettledSeconds {
            lines.append(String(format: "Q1 정지(차분기준): %d폴 (%.2f초)", dp, ds))
        } else {
            lines.append(String(format: "Q1 정지(차분기준) 실패: %d폴(약 %.0f초) 안에 멈추지 않았다", pollsSeen, cfg.maxSeconds))
        }
        if let sp = settledPoll, let sec = settledSeconds {
            lines.append(String(format: "Q1 정지(속도임계): %d폴 (%.2f초, SceneUpdate %d프레임)", sp, sec, s.updateFrames))
        } else {
            lines.append(String(format: "Q1 정지(속도임계) 실패: %d폴(약 %.0f초) 안에 임계 미달", pollsSeen, cfg.maxSeconds))
        }
        lines.append(String(format: "  마지막 자세변화량 %.5f°/frame", lastRotDelta.isFinite ? lastRotDelta : -1))
        lines.append("Q2 transform 읽기: \((s.q2Readable ?? false) ? "OK" : "불가")")
        let velOK = (s.q3VelocityReadable ?? false) && s.q3VelocityEverNonZero
        lines.append("Q3 속도 읽기: " + (velOK ? "PhysicsMotionComponent OK"
            : ((s.q3VelocityReadable ?? false) ? "컴포넌트는 있으나 값이 항상 0 → 위치 차분 필요" : "불가 → 위치 차분 사용")))
        lines.append(String(format: "  마지막 linear=%.5f angular=%.5f diffSpeed=%.5f",
                            lastLinear, lastAngular, lastDiffSpeed.isFinite ? lastDiffSpeed : -1))
        var worstFull: Float = 0
        var worstUp: Float = 0
        for (i, d) in s.dice.enumerated() {
            let q = d.orientation(relativeTo: nil)
            let deg = SpikeAxis.alignmentErrorDegrees(q)
            let up = SpikeAxis.upFaceErrorDegrees(q)
            worstFull = max(worstFull, deg); worstUp = max(worstUp, up)
            lines.append(String(format: "Q4 die%d 축정렬오차 %.2f° / 윗면오차 %.2f°  %@",
                                i, deg, up, up <= 2 ? "OK" : "초과"))
        }
        lines.append(String(format: "Q4 최대 축정렬오차 %.2f° / 최대 윗면오차 %.2f°  %@",
                            worstFull, worstUp, worstUp <= 2 ? "OK" : "초과"))
        for (i, d) in s.dice.enumerated() {
            let p = d.position(relativeTo: nil), q = d.orientation(relativeTo: nil)
            lines.append(String(format: "STATE die%d p=%.7f,%.7f,%.7f q=%.7f,%.7f,%.7f,%.7f",
                                i, p.x, p.y, p.z, q.vector.x, q.vector.y, q.vector.z, q.vector.w))
        }
        lines.append("RUN_END")
        emit(lines)
    }

    @MainActor func emit(_ lines: [String]) {
        for l in lines { print(l) }
        fflush(stdout)
        exit(0)
    }
}
