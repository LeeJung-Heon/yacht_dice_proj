import Foundation
import simd

/// 정육면체를 자기 자신으로 보내는 24개 회전.
///
/// 스펙 §7.3의 정확성 논증이 이 군 위에 서 있다.
/// 궤적의 정지 자세를 이 24개 중 하나로 스냅해두면
/// Δ = q_rest⁻¹ · q_target 이 반드시 이 군의 원소가 되고,
/// 그러면 회전된 주사위가 매 프레임 원본과 정확히 같은 공간을 점유한다.
public enum OctahedralGroup {

    public static let elements: [simd_quatf] = buildByClosure()

    /// 90도 회전 3개에서 시작해 곱셈 폐포를 구한다.
    /// 오일러각을 훑어 중복을 거르는 방식보다 개수 보장이 확실하다.
    private static func buildByClosure() -> [simd_quatf] {
        let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        let generators = [
            simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0)),
            simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0)),
            simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1)),
        ]
        var found: [simd_quatf] = [identity]
        var frontier: [simd_quatf] = [identity]

        while !frontier.isEmpty {
            var next: [simd_quatf] = []
            for element in frontier {
                for generator in generators {
                    let candidate = simd_normalize(simd_mul(generator, element))
                    if !found.contains(where: { isSameRotation($0, candidate) }) {
                        found.append(candidate)
                        next.append(candidate)
                    }
                }
            }
            frontier = next
        }
        return found
    }

    /// 쿼터니언 q와 -q는 같은 회전이므로 내적의 절댓값으로 비교한다.
    public static func isSameRotation(_ a: simd_quatf, _ b: simd_quatf, tolerance: Float = 1e-4) -> Bool {
        abs(simd_dot(simd_normalize(a.vector), simd_normalize(b.vector))) > 1 - tolerance
    }

    public static func angle(between a: simd_quatf, and b: simd_quatf) -> Float {
        let dot = min(1, abs(simd_dot(simd_normalize(a.vector), simd_normalize(b.vector))))
        return 2 * acos(dot)
    }

    /// 눈 `source`의 법선을 눈 `destination`의 법선으로 보내는 원소들.
    ///
    /// O는 6개 면 법선에 추이적으로 작용하고 각 법선의 안정자군 위수가 4이므로
    /// 결과는 항상 정확히 4개다. 이 4개가 회전 오프셋의 yaw 다양성을 만든다.
    public static func elements(mapping source: Int, to destination: Int) -> [simd_quatf] {
        let target = DieFace.normal(of: destination)
        let origin = DieFace.normal(of: source)
        return elements.filter { simd_length($0.act(origin) - target) < 1e-4 }
    }

    /// q가 정육면체를 자기 자신으로 보내는가 —
    /// 6개 면 법선 집합을 자기 자신으로 옮기는지로 판정한다.
    public static func preservesCube(_ q: simd_quatf, tolerance: Float = 1e-4) -> Bool {
        let normals = DieFace.faces.map(\.normal)
        for normal in normals {
            let rotated = q.act(normal)
            let matched = normals.contains { simd_length(rotated - $0) < tolerance }
            if !matched { return false }
        }
        return true
    }
}
