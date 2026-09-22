import RealityKit
import UIKit

/// 사출 플라스틱과 코팅 테이블의 서로 다른 반사·표면 결. 장면마다 텍스처를 다시 굽지 않는다.
@MainActor
enum CupPongMaterials {
    static let redPlastic: PhysicallyBasedMaterial = {
        var material = base(UIColor(red: 0.63, green: 0.025, blue: 0.038, alpha: 1), roughness: 0.24)
        material.clearcoat = .init(floatLiteral: 0.5)
        material.clearcoatRoughness = .init(floatLiteral: 0.2)
        return material
    }()

    static let innerPlastic = base(UIColor(red: 0.93, green: 0.90, blue: 0.83, alpha: 1), roughness: 0.29)
    static let rim = base(UIColor(red: 0.97, green: 0.95, blue: 0.88, alpha: 1), roughness: 0.2)
    static let ball = base(UIColor(red: 0.98, green: 0.95, blue: 0.87, alpha: 1), roughness: 0.58)
    static let metal = base(UIColor(white: 0.14, alpha: 1), roughness: 0.32, metallic: 0.8)
    static let brass = base(UIColor(red: 0.62, green: 0.45, blue: 0.22, alpha: 1), roughness: 0.32, metallic: 0.8)
    static let water: PhysicallyBasedMaterial = {
        var material = base(UIColor(red: 0.21, green: 0.11, blue: 0.035, alpha: 1), roughness: 0.10)
        material.clearcoat = .init(floatLiteral: 1)
        material.clearcoatRoughness = .init(floatLiteral: 0.06)
        return material
    }()

    static let tabletop: PhysicallyBasedMaterial = {
        var material = base(.white, roughness: 0.48)
        var canvas = PixelCanvas(width: 256, height: 256)
        canvas.fill { u, v in
            let grain = Noise.value(u * 160, v * 160, period: 160, seed: 81)
            let patch = Noise.fbm(u * 4, v * 4, period: 4, octaves: 3, seed: 82)
            let shade = 0.86 + grain * 0.07 + patch * 0.14
            return SIMD4(SIMD3<Float>(0.055, 0.21, 0.185) * shade, 1)
        }
        if let image = canvas.makeImage(), let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            material.baseColor = .init(texture: .init(texture))
        }
        let normal = PixelCanvas.normalMap(from: { u, v in
            Noise.value(u * 160, v * 160, period: 160, seed: 81)
        }, size: 256, strength: 0.00015)
        if let image = normal.makeImage(), let texture = try? TextureResource(image: image, options: .init(semantic: .normal)) {
            material.normal = .init(texture: .init(texture))
        }
        material.clearcoat = .init(floatLiteral: 0.2)
        material.clearcoatRoughness = .init(floatLiteral: 0.42)
        return material
    }()

    /// 접지 부근의 부드러운 주변광 차폐. 방향광 그림자와 함께 컵이 판 위에 앉아 보이게 한다.
    static let contactShadow: UnlitMaterial = {
        var canvas = PixelCanvas(width: 128, height: 128)
        canvas.fill { u, v in
            let r = sqrt((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5)) * 2
            return SIMD4<Float>(0.015, 0.025, 0.02, max(0, 1 - r) * max(0, 1 - r) * 0.52)
        }
        var material = UnlitMaterial()
        if let image = canvas.makeImage(), let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            material.color = .init(texture: .init(texture))
        }
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        return material
    }()

    static func base(_ color: UIColor, roughness: Float, metallic: Float = 0) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)
        material.specular = .init(floatLiteral: 0.5)
        return material
    }
}
