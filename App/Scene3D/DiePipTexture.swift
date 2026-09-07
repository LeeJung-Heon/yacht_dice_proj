import Foundation
import CoreGraphics
import simd

/// 주사위 6면 눈을 코드로 그린다. 외부 3D 아티스트 없이 진행하기 위한 선택이다 (스펙 §13).
///
/// 면마다 텍스처가 하나씩 필요하다. `MeshResource.generateBox`는 가로로 이어붙인
/// 아틀라스를 기대하지 않는다 — 이 SDK에서 직접 확인한 결과, 아틀라스든 아니든
/// **텍스처 전체가 6면 각각에 그대로 매핑된다**(모든 면의 u가 [0…1]). 그래서
/// 아틀라스를 쓰면 여섯 칸이 한 면에 전부 짓눌려 줄무늬만 남는다.
///
/// 대신 `splitFaces: true`로 면을 6개 파트로 쪼개고 파트마다 다른 머티리얼을 준다.
/// 각 파트의 UV는 그 면 하나를 [0…1]로 덮는다.
///
/// 색 텍스처는 눈의 색을, 노멀맵은 눈이 오목하게 파인 질감을 맡는다.
enum DiePipTexture {

    /// `generateBox(..., splitFaces: true)`가 만드는 머티리얼 인덱스 → 그 면이 향하는 축.
    /// 이 SDK에서 파트별 법선을 직접 찍어 확인했다 (DiePipTextureTests가 매번 다시 확인한다).
    static let faceNormalsByMaterialIndex: [SIMD3<Float>] = [
        SIMD3( 0,  0,  1),   // 0 → +Z
        SIMD3( 0,  1,  0),   // 1 → +Y
        SIMD3( 0,  0, -1),   // 2 → -Z
        SIMD3( 0, -1,  0),   // 3 → -Y
        SIMD3( 1,  0,  0),   // 4 → +X
        SIMD3(-1,  0,  0),   // 5 → -X
    ]

    /// 위 축 배치를 `DieFace`의 눈 배치(+Y=1, +Z=2, +X=3, -X=4, -Z=5, -Y=6)로 옮긴 것.
    /// 머티리얼 배열은 반드시 이 순서여야 한다.
    static let faceValuesByMaterialIndex = [2, 1, 5, 6, 3, 4]

    /// 눈 반지름 (면 한 변 = 1). 모서리 라운드(dieSize의 10%)에 걸리지 않게
    /// pipLayout의 좌표가 0.26...0.74 안에 있고, 반지름을 더해도 0.17...0.83이다.
    static let pipRadius: Float = 0.088

    /// 눈 `value` 하나만 그린 정사각 텍스처. UV [0…1] 전체를 쓴다.
    static func makeFace(value: Int, size: Int = 256) -> CGImage? {
        let ivory = SIMD3<Float>(0.96, 0.94, 0.88)
        let ink = SIMD3<Float>(0.07, 0.06, 0.07)
        let pips = pipLayout(for: value)
        let edge: Float = 1.5 / Float(size)   // 안티에일리어싱 폭

        var canvas = PixelCanvas(width: size, height: size)
        canvas.fill { u, v in
            let distance = nearestPipDistance(u, v, pips: pips)
            // 눈 안쪽은 검고, 가장자리로 갈수록 상아색으로 이어진다.
            // 눈 테두리 바로 바깥은 살짝 어둡게 — 오목한 홈의 그늘이다.
            let inside = 1 - smoothstep(pipRadius - edge, pipRadius + edge, distance)
            let rim = (1 - smoothstep(pipRadius, pipRadius * 1.25, distance)) * 0.18
            let color = lerp(ivory * (1 - rim), ink, inside)
            return SIMD4(color, 1)
        }
        return canvas.makeImage()
    }

    /// 눈이 구면으로 파인 노멀맵. 눈 없는 자리는 평평하다 (0.5, 0.5, 1).
    static func makeFaceNormalMap(value: Int, size: Int = 256) -> CGImage? {
        let pips = pipLayout(for: value)
        let depth: Float = 0.06
        return PixelCanvas.normalMap(from: { u, v in
            let r = nearestPipDistance(u, v, pips: pips) / pipRadius
            guard r < 1 else { return 1 }
            return 1 - depth * (1 - r * r).squareRoot()
        }, size: size, strength: 0.9).makeImage()
    }

    /// 머티리얼 인덱스 순서대로 6장. 하나라도 실패하면 nil —
    /// 일부만 붙은 주사위는 눈이 없는 주사위보다 더 헷갈린다.
    static func makeFaceTextures(size: Int = 256) -> [CGImage]? {
        var images: [CGImage] = []
        for value in faceValuesByMaterialIndex {
            guard let image = makeFace(value: value, size: size) else { return nil }
            images.append(image)
        }
        return images
    }

    /// 머티리얼 인덱스 순서대로 노멀맵 6장.
    static func makeFaceNormalMaps(size: Int = 256) -> [CGImage]? {
        var images: [CGImage] = []
        for value in faceValuesByMaterialIndex {
            guard let image = makeFaceNormalMap(value: value, size: size) else { return nil }
            images.append(image)
        }
        return images
    }

    /// 면 안에서의 상대 좌표 (0...1).
    static func pipLayout(for value: Int) -> [CGPoint] {
        let a: CGFloat = 0.26, b: CGFloat = 0.5, c: CGFloat = 0.74
        switch value {
        case 1: return [CGPoint(x: b, y: b)]
        case 2: return [CGPoint(x: a, y: c), CGPoint(x: c, y: a)]
        case 3: return [CGPoint(x: a, y: c), CGPoint(x: b, y: b), CGPoint(x: c, y: a)]
        case 4: return [CGPoint(x: a, y: a), CGPoint(x: a, y: c), CGPoint(x: c, y: a), CGPoint(x: c, y: c)]
        case 5: return [CGPoint(x: a, y: a), CGPoint(x: a, y: c), CGPoint(x: b, y: b),
                        CGPoint(x: c, y: a), CGPoint(x: c, y: c)]
        case 6: return [CGPoint(x: a, y: a), CGPoint(x: a, y: b), CGPoint(x: a, y: c),
                        CGPoint(x: c, y: a), CGPoint(x: c, y: b), CGPoint(x: c, y: c)]
        default: preconditionFailure("주사위 눈은 1...6이다: \(value)")
        }
    }

    private static func nearestPipDistance(_ u: Float, _ v: Float, pips: [CGPoint]) -> Float {
        var best = Float.infinity
        for pip in pips {
            let dx = u - Float(pip.x), dy = v - Float(pip.y)
            best = min(best, (dx * dx + dy * dy).squareRoot())
        }
        return best
    }
}
