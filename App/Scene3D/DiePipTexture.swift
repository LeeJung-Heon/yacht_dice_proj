import Foundation
import CoreGraphics
import RealityKit
import UIKit

/// 주사위 6면 눈을 코드로 그린다. 외부 3D 아티스트 없이 진행하기 위한 선택이다 (스펙 §13).
///
/// 면마다 텍스처가 하나씩 필요하다. `MeshResource.generateBox`는 가로로 이어붙인
/// 아틀라스를 기대하지 않는다 — 이 SDK에서 직접 확인한 결과, 아틀라스든 아니든
/// **텍스처 전체가 6면 각각에 그대로 매핑된다**(모든 면의 u가 [0…1]). 그래서
/// 아틀라스를 쓰면 여섯 칸이 한 면에 전부 짓눌려 줄무늬만 남는다.
///
/// 대신 `splitFaces: true`로 면을 6개 파트로 쪼개고 파트마다 다른 머티리얼을 준다.
/// 각 파트의 UV는 그 면 하나를 [0…1]로 덮는다.
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

    /// 눈 `value` 하나만 그린 정사각 텍스처. UV [0…1] 전체를 쓴다.
    static func makeFace(value: Int, size: Int = 256) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        let side = CGFloat(size)
        context.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))

        // 눈은 면 안쪽에만 찍힌다. 모서리 라운드(dieSize의 10%)에 걸리지 않게
        // pipLayout의 좌표가 0.26...0.74 안에 있고, 반지름을 더해도 0.17...0.83이다.
        context.setFillColor(UIColor(white: 0.11, alpha: 1).cgColor)
        let radius = side * 0.088
        for point in pipLayout(for: value) {
            context.fillEllipse(in: CGRect(
                x: point.x * side - radius, y: point.y * side - radius,
                width: radius * 2, height: radius * 2))
        }
        return context.makeImage()
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
}
