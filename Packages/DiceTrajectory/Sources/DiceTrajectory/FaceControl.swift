import Foundation
import simd

/// 궤적을 다시 굴리지 않고 나오는 눈만 바꾸는 장치.
///
/// 궤적에서 실제로 위를 향한 눈이 u일 때, 눈 v가 위를 향하게 하려면
///
///     Δ ∈ O,  Δ(n_v) = n_u
///     q'(t) = q(t) · Δ
///
/// 를 쓴다. 정지 시 q_rest(n_u) ≈ +Y 이므로
/// q_rest(Δ(n_v)) = q_rest(n_u) ≈ +Y 가 되어 목표 눈이 위를 향한다.
///
/// Δ가 정육면체 대칭군의 원소이므로 회전된 주사위는 매 프레임 원본과
/// 같은 공간을 점유한다 (스펙 §7.3).
///
/// **정지 자세 전체가 아니라 위를 향한 눈에만 의존한다는 점이 중요하다.**
/// 바닥에 누운 주사위는 수직축 둘레 yaw가 연속적으로 자유롭다.
/// Δ를 q_rest⁻¹ · q_target 으로 계산하면 그 자유로운 yaw까지 되돌려
/// 멈춘 주사위가 최대 45° 홱 돌아간다.
public enum FaceControl {

    /// - Parameters:
    ///   - restUpFace: 이 궤적에서 실제로 위를 향한 눈 (1...6).
    ///   - value: 위로 오게 할 눈 (1...6).
    ///   - yawChoice: 조건을 만족하는 4개 중 하나. 굴림마다 다르게 주면 화면이 덜 반복적으로 보인다.
    public static func offset(restUpFace: Int, showing value: Int, yawChoice: Int) -> simd_quatf {
        let candidates = OctahedralGroup.elements(mapping: value, to: restUpFace)
        precondition(candidates.count == 4,
                     "눈 \(value)를 \(restUpFace)로 보내는 원소는 4개여야 하는데 \(candidates.count)개다")
        let index = ((yawChoice % candidates.count) + candidates.count) % candidates.count
        return simd_normalize(candidates[index])
    }

    /// 몸통 프레임 회전이므로 **오른쪽에서** 곱한다.
    /// 왼쪽에서 곱하면 궤적 전체가 월드 기준으로 회전해 주사위가 트레이 밖으로 나간다.
    public static func apply(_ offset: simd_quatf, to frame: simd_quatf) -> simd_quatf {
        simd_normalize(simd_mul(frame, offset))
    }
}
