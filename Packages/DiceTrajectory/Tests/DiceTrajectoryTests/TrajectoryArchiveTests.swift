import Testing
import Foundation
import simd
@testable import DiceTrajectory

/// 테스트용 합성 궤적. 물리는 없고 포맷과 검증기만 확인한다.
private func makeTrajectory(id: UInt16 = 1, dieCount: Int = 5, frameCount: Int = 90) -> Trajectory {
    var frames: [[DiePose]] = []
    var restPoses: [simd_quatf] = []
    var restUpFaces: [UInt8] = []
    for die in 0..<dieCount {
        // 물리가 실제로 만드는 정지 자세를 흉내낸다 — 축정렬이 아니라 yaw가 자유롭다
        let base = OctahedralGroup.elements[(die * 5) % OctahedralGroup.elements.count]
        let yaw = simd_quatf(angle: Float(die) * 31 * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
        let rest = simd_normalize(simd_mul(yaw, base))
        restPoses.append(rest)
        restUpFaces.append(UInt8(DieFace.upValue(for: rest)))
    }
    for frame in 0..<frameCount {
        let t = Float(frame) / Float(frameCount - 1)
        var poses: [DiePose] = []
        for die in 0..<dieCount {
            let spin = simd_quatf(angle: (1 - t) * 8, axis: simd_normalize(SIMD3<Float>(0.3, 1, 0.2)))
            poses.append(DiePose(
                position: SIMD3(Float(die - 2) * 0.02, 0.10 * (1 - t) + 0.008, -0.06 + 0.10 * t),
                orientation: t >= 1 ? restPoses[die] : simd_normalize(simd_mul(spin, restPoses[die]))
            ))
        }
        frames.append(poses)
    }
    return Trajectory(id: id, dieCount: dieCount, direction: .center, frameRate: 60,
                      frames: frames, restUpFaces: restUpFaces,
                      collisions: [CollisionCue(frame: 12, dieIndex: 0, intensity: 0.8)])
}

@Suite("궤적 포맷")
struct TrajectoryArchiveTests {

    @Test("인코딩-디코딩 왕복 후 구조가 보존된다")
    func 왕복_구조() throws {
        let original = [makeTrajectory(id: 1), makeTrajectory(id: 2, dieCount: 3, frameCount: 60)]
        let restored = try TrajectoryArchive.decode(TrajectoryArchive.encode(original))

        #expect(restored.count == 2)
        for (a, b) in zip(original, restored) {
            #expect(a.id == b.id)
            #expect(a.dieCount == b.dieCount)
            #expect(a.direction == b.direction)
            #expect(a.frameRate == b.frameRate)
            #expect(a.frames.count == b.frames.count)
            #expect(a.restUpFaces == b.restUpFaces, "정지 시 윗면 값은 손실 없이 보존돼야 한다")
            #expect(a.collisions == b.collisions)
        }
    }

    @Test("위치와 자세는 양자화 오차 안에서 보존된다")
    func 왕복_수치() throws {
        let original = makeTrajectory()
        let restored = try TrajectoryArchive.decode(TrajectoryArchive.encode([original]))[0]

        for (frameIndex, (a, b)) in zip(original.frames, restored.frames).enumerated() {
            for (die, (poseA, poseB)) in zip(a, b).enumerated() {
                let positionError = simd_length(poseA.position - poseB.position)
                #expect(positionError < 0.001, "프레임 \(frameIndex) 주사위 \(die) 위치 오차 \(positionError)m")
                let angleError = OctahedralGroup.angle(between: poseA.orientation, and: poseB.orientation)
                #expect(angleError < 0.01, "프레임 \(frameIndex) 주사위 \(die) 자세 오차 \(angleError)rad")
            }
        }
    }

    @Test("정지 시 윗면 값은 양자화를 거치지 않는다 — 1바이트 정수로 저장하기 때문")
    func 윗면_값은_정확하다() throws {
        let original = makeTrajectory()
        let restored = try TrajectoryArchive.decode(TrajectoryArchive.encode([original]))[0]
        for die in 0..<original.dieCount {
            #expect(original.restUpFace(die: die) == restored.restUpFace(die: die),
                    "정지 시 윗면 값이 왕복에서 바뀌었다 — 오프셋이 엉뚱한 눈을 올린다")
            // 마지막 프레임의 실제 자세에서 읽은 윗면과도 일치해야 한다
            let last = restored.frames.count - 1
            #expect(DieFace.upValue(for: restored.frames[last][die].orientation)
                    == restored.restUpFace(die: die),
                    "기록된 윗면 값이 마지막 프레임의 실제 자세와 다르다")
        }
    }

    @Test("매직 넘버가 다르면 디코딩이 실패한다")
    func 잘못된_매직() {
        #expect(throws: TrajectoryArchive.Failure.badMagic) {
            try TrajectoryArchive.decode(Data([0x00, 0x01, 0x02, 0x03, 0x04]))
        }
    }

    @Test("포맷 버전이 다르면 디코딩이 실패한다")
    func 버전_불일치() throws {
        var data = try TrajectoryArchive.encode([makeTrajectory()])
        data[4] = 0xFF
        data[5] = 0xFF
        #expect(throws: (any Error).self) { try TrajectoryArchive.decode(data) }
    }

    @Test("정상 궤적에는 문제가 없다")
    func 검증기_통과() {
        let problems = TrajectoryValidator.problems(
            in: makeTrajectory(),
            trayInner: SIMD3(0.24, 0.12, 0.24),
            dieSize: 0.016
        )
        #expect(problems.isEmpty, "\(problems.joined(separator: " | "))")
    }

    @Test("트레이를 벗어난 궤적을 잡아낸다")
    func 검증기_이탈_감지() {
        var trajectory = makeTrajectory()
        trajectory.frames[40][2].position = SIMD3(5, 0.01, 0)   // 5미터 밖
        let problems = TrajectoryValidator.problems(
            in: trajectory,
            trayInner: SIMD3(0.24, 0.12, 0.24),
            dieSize: 0.016
        )
        #expect(problems.contains { $0.contains("트레이") })
    }

    @Test("마지막 프레임이 기록된 정지 자세와 다르면 잡아낸다")
    func 검증기_정지자세_불일치() {
        var trajectory = makeTrajectory()
        trajectory.frames[trajectory.frames.count - 1][0].orientation =
            simd_normalize(simd_quatf(angle: 0.6, axis: SIMD3<Float>(0, 0, 1)))
        let problems = TrajectoryValidator.problems(
            in: trajectory,
            trayInner: SIMD3(0.24, 0.12, 0.24),
            dieSize: 0.016
        )
        #expect(problems.contains { $0.contains("정지 자세") })
    }

    @Test("모든 궤적 x 모든 목표 눈에서 오프셋이 목표 눈을 위로 올린다")
    func 궤적_전수_검증() {
        // 스펙 §11의 검증 ③. Task 12가 실제 궤적을 구우면 같은 검사를 그 데이터로 돌린다.
        let trajectory = makeTrajectory()
        for die in 0..<trajectory.dieCount {
            for value in 1...6 {
                for yaw in 0..<4 {
                    let offset = FaceControl.offset(
                        restUpFace: trajectory.restUpFace(die: die),
                        showing: value, yawChoice: yaw
                    )
                    let last = trajectory.frames.count - 1
                    let pose = trajectory.posed(die: die, frame: last, offset: offset)
                    #expect(DieFace.upValue(for: pose.orientation) == value)
                }
            }
        }
    }
}

