import Testing
import simd
@testable import DiceTrajectory

@Suite("회전 오프셋")
struct FaceControlTests {

    /// 물리가 실제로 만들어내는 정지 자세를 흉내낸다.
    /// 축정렬이 **아니다** — 수직축 둘레 yaw가 자유롭고 약간의 기울기가 남는다.
    private static func restingOrientations() -> [(orientation: simd_quatf, upFace: Int)] {
        var out: [(simd_quatf, Int)] = []
        for base in OctahedralGroup.elements {
            for yawDegrees in stride(from: Float(0), to: 360, by: 37) {
                let yaw = simd_quatf(angle: yawDegrees * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
                // 물리가 남기는 잔여 기울기 (스파이크 실측 0.03도, 여유를 둬 1.5도)
                let tilt = simd_quatf(angle: 1.5 * .pi / 180,
                                      axis: simd_normalize(SIMD3<Float>(0.6, 0, -0.8)))
                let resting = simd_normalize(simd_mul(simd_mul(tilt, yaw), base))
                out.append((resting, DieFace.upValue(for: resting)))
            }
        }
        return out
    }

    /// 스펙 §11이 "이 프로젝트에서 가장 중요한 테스트"로 지목한 것.
    /// 여기가 깨지면 온라인 대전이 통째로 무너진다.
    @Test("축정렬이 아닌 정지 자세에서도 목표 눈이 위로 온다", arguments: 1...6)
    func 목표_눈이_위로_온다(value: Int) {
        for (resting, upFace) in Self.restingOrientations() {
            for yaw in 0..<4 {
                let delta = FaceControl.offset(restUpFace: upFace, showing: value, yawChoice: yaw)
                let final = FaceControl.apply(delta, to: resting)
                #expect(DieFace.upValue(for: final) == value,
                        "눈 \(value), yaw \(yaw)에서 \(DieFace.upValue(for: final))가 나왔다")
            }
        }
    }

    @Test("오프셋을 적용해도 윗면 기울기가 커지지 않는다", arguments: 1...6)
    func 기울기_보존(value: Int) {
        // 물리가 만든 잔여 기울기는 그대로 물려받아야 한다.
        // 커진다면 Δ가 대칭군 밖으로 나간 것이다.
        for (resting, upFace) in Self.restingOrientations() {
            let before = DieFace.upFaceTiltRadians(for: resting)
            let delta = FaceControl.offset(restUpFace: upFace, showing: value, yawChoice: 0)
            let after = DieFace.upFaceTiltRadians(for: FaceControl.apply(delta, to: resting))
            #expect(abs(after - before) < 1e-3,
                    "기울기가 \(before * 180 / .pi)도에서 \(after * 180 / .pi)도로 변했다")
        }
    }

    @Test("오프셋은 항상 정육면체 대칭군의 원소다", arguments: 1...6)
    func 오프셋은_대칭군_원소다(value: Int) {
        // 이것이 성립해야 "회전된 주사위가 매 프레임 원본과 같은 공간을 점유한다"는
        // 스펙 §7.3의 논증이 성립한다.
        for upFace in 1...6 {
            for yaw in 0..<4 {
                let delta = FaceControl.offset(restUpFace: upFace, showing: value, yawChoice: yaw)
                #expect(OctahedralGroup.preservesCube(delta, tolerance: 1e-4),
                        "오프셋이 정육면체를 보존하지 않는다 — 궤적의 기하가 달라진다")
                #expect(OctahedralGroup.elements.contains { OctahedralGroup.isSameRotation($0, delta) },
                        "오프셋이 24개 군 밖에 있다")
            }
        }
    }

    @Test("yaw 4가지가 서로 다른 자세를 만든다", arguments: 1...6)
    func yaw가_다양성을_만든다(value: Int) {
        let deltas = (0..<4).map { FaceControl.offset(restUpFace: 1, showing: value, yawChoice: $0) }
        for i in 0..<4 {
            for j in (i + 1)..<4 {
                #expect(!OctahedralGroup.isSameRotation(deltas[i], deltas[j]),
                        "yaw \(i)와 \(j)가 같은 오프셋을 만든다")
            }
        }
    }

    @Test("yawChoice는 음수나 큰 수여도 안전하게 감긴다")
    func yaw_인덱스_감기() {
        let a = FaceControl.offset(restUpFace: 3, showing: 4, yawChoice: 1)
        let b = FaceControl.offset(restUpFace: 3, showing: 4, yawChoice: 5)
        let c = FaceControl.offset(restUpFace: 3, showing: 4, yawChoice: -3)
        #expect(OctahedralGroup.isSameRotation(a, b))
        #expect(OctahedralGroup.isSameRotation(a, c))
    }

    @Test("같은 눈을 요청하면 오프셋이 항등이 되는 경우가 있다")
    func 항등_케이스() {
        // 이미 6이 위인 주사위에 6을 요청하면 면을 옮길 필요가 없다.
        let delta = FaceControl.offset(restUpFace: 6, showing: 6, yawChoice: 0)
        let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        let anyIsIdentity = (0..<4).contains { yaw in
            OctahedralGroup.isSameRotation(
                FaceControl.offset(restUpFace: 6, showing: 6, yawChoice: yaw), identity)
        }
        #expect(anyIsIdentity, "같은 면을 요청했는데 항등 오프셋이 하나도 없다")
        #expect(OctahedralGroup.preservesCube(delta, tolerance: 1e-4))
    }

    @Test("왼쪽 곱셈은 틀린 답을 낸다 — 곱하는 방향이 중요하다")
    func 곱셈_방향() {
        // 회귀 방지용. 누군가 simd_mul의 인자 순서를 뒤집으면 여기서 잡힌다.
        // 정지 자세에 yaw를 섞어 두 방향이 우연히 일치하지 않게 한다.
        let yaw = simd_quatf(angle: 40 * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
        let resting = simd_normalize(simd_mul(yaw, OctahedralGroup.elements[0]))
        let upFace = DieFace.upValue(for: resting)
        let target = (upFace % 6) + 1                       // 현재 윗면과 다른 눈
        let delta = FaceControl.offset(restUpFace: upFace, showing: target, yawChoice: 0)

        #expect(DieFace.upValue(for: simd_mul(resting, delta)) == target, "오른쪽 곱셈이 틀렸다")
        #expect(DieFace.upValue(for: simd_mul(delta, resting)) != target,
                "왼쪽 곱셈이 우연히 맞았다 — 더 어려운 케이스를 골라야 한다")
    }
}
