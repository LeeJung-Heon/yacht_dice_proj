import Foundation
import simd

/// 주사위 로컬 좌표계의 면 배치.
/// 서양식 오른손 주사위: 마주 보는 면의 합이 7이고, 1·2·3이 한 꼭짓점을 반시계로 돈다.
public enum DieFace {
    /// 배열로 두는 이유: Dictionary는 순회 순서가 정해지지 않아서
    /// upValue(for:)가 동점일 때 실행마다 다른 답을 낼 수 있다.
    public static let faces: [(value: Int, normal: SIMD3<Float>)] = [
        (1, SIMD3( 0,  1,  0)),
        (2, SIMD3( 0,  0,  1)),
        (3, SIMD3( 1,  0,  0)),
        (4, SIMD3(-1,  0,  0)),
        (5, SIMD3( 0,  0, -1)),
        (6, SIMD3( 0, -1,  0)),
    ]

    public static func normal(of value: Int) -> SIMD3<Float> {
        guard let face = faces.first(where: { $0.value == value }) else {
            preconditionFailure("주사위 눈은 1...6이다: \(value)")
        }
        return face.normal
    }

    /// 이 자세에서 월드 +Y를 향하는 눈.
    public static func upValue(for orientation: simd_quatf) -> Int {
        var best = faces[0].value
        var bestDot = -Float.infinity
        for face in faces {
            let dot = orientation.act(face.normal).y
            if dot > bestDot { bestDot = dot; best = face.value }
        }
        return best
    }

    /// 위를 향한 면의 법선이 +Y에서 얼마나 벗어났는가 (라디안).
    ///
    /// 정지 판정의 올바른 척도다. 24개 축정렬 자세와의 거리로 재면
    /// 바닥에 평평하게 누운 주사위도 자유로운 yaw 때문에 최대 45°가 나온다 (스펙 §7.3).
    public static func upFaceTiltRadians(for orientation: simd_quatf) -> Float {
        var bestDot = -Float.infinity
        for face in faces {
            bestDot = max(bestDot, orientation.act(face.normal).y)
        }
        return acos(min(1, max(-1, bestDot)))
    }
}
