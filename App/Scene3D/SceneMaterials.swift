import Foundation
import CoreGraphics
import RealityKit
import simd

/// 씬의 재질. 전부 코드로 그린 절차적 텍스처다 — 외부 3D 아티스트 없이 진행한다 (스펙 §13).
///
/// 원칙: 색은 baseColor 텍스처가, 질감은 normal 텍스처가, 광택은 roughness 값이 맡는다.
/// 단색 PBR은 어떤 조명 아래서도 플라스틱 장난감처럼 보인다 — 이 파일이 있는 이유다.
@MainActor
enum SceneMaterials {

    // MARK: - 가죽 (트레이 바닥, 선반 인레이)

    /// 어두운 버건디 가죽. 결이 있고, 가장자리로 갈수록 살짝 어두워져 트레이 안쪽이 깊어 보인다.
    /// - Parameter tiling: UV 반복 배수. 가로세로 비율이 다른 면에 붙일 때 결 알갱이가 늘어나지 않게 맞춘다.
    static func leather(vignette: Bool = true, tiling: SIMD2<Float> = [1, 1]) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.textureCoordinateTransform = .init(scale: tiling)
        material.baseColor = .init(tint: .white, texture: cached("leather.albedo.\(vignette)") {
            texture(leatherAlbedo(vignette: vignette), semantic: .color)
        })
        material.normal = .init(texture: cached("leather.normal") { texture(leatherNormal(), semantic: .normal) })
        material.roughness = .init(floatLiteral: 0.72)
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: 0.35)
        return material
    }

    nonisolated static func leatherAlbedo(vignette: Bool, size: Int = 512) -> PixelCanvas {
        var canvas = PixelCanvas(width: size, height: size)
        let deep = SIMD3<Float>(0.30, 0.055, 0.065)
        let warm = SIMD3<Float>(0.46, 0.10, 0.10)
        canvas.fill { u, v in
            // 굵은 얼룩 + 잔 결
            let mottle = Noise.fbm(u * 6, v * 6, period: 6, octaves: 3, seed: 11)
            let grain = Noise.value(u * 160, v * 160, period: 160, seed: 23)
            var color = lerp(deep, warm, mottle * 0.8 + grain * 0.2)
            if vignette {
                let dx = (u - 0.5) * 2, dy = (v - 0.5) * 2
                let edge = max(abs(dx), abs(dy))
                let falloff = 1 - 0.28 * smoothstep(0.45, 1.0, edge)
                color *= falloff
            }
            return SIMD4(color, 1)
        }
        return canvas
    }

    nonisolated static func leatherNormal(size: Int = 512) -> PixelCanvas {
        PixelCanvas.normalMap(from: { u, v in
            Noise.fbm(u * 48, v * 48, period: 48, octaves: 3, seed: 31) * 0.7
                + Noise.value(u * 200, v * 200, period: 200, seed: 37) * 0.3
        }, size: size, strength: 0.012)
    }

    // MARK: - 호두나무 (트레이 테두리, 선반, 테이블)

    /// 기름 먹인 호두나무. 나이테 줄무늬가 `along` 축으로 흐른다.
    /// `tone`은 텍스처를 다시 굽지 않고 틴트로 어둡게 한다 — 테이블과 트레이가 같은 텍스처를 나눠 쓴다.
    static func walnut(along: GrainAxis, tone: Float = 1.0, tiling: Float = 1) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.textureCoordinateTransform = .init(scale: SIMD2(repeating: tiling))
        let tint = CGColor(red: CGFloat(tone), green: CGFloat(tone), blue: CGFloat(tone), alpha: 1)
        material.baseColor = .init(tint: .init(cgColor: tint), texture: cached("walnut.albedo.\(along)") {
            texture(walnutAlbedo(along: along), semantic: .color)
        })
        material.normal = .init(texture: cached("walnut.normal.\(along)") {
            texture(walnutNormal(along: along), semantic: .normal)
        })
        material.roughness = .init(floatLiteral: 0.42)
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: 0.5)
        material.clearcoat = .init(floatLiteral: 0.25)
        material.clearcoatRoughness = .init(floatLiteral: 0.35)
        return material
    }

    enum GrainAxis { case u, v }

    nonisolated static func walnutAlbedo(along: GrainAxis, size: Int = 512) -> PixelCanvas {
        var canvas = PixelCanvas(width: size, height: size)
        let light = SIMD3<Float>(0.40, 0.24, 0.13)
        let dark = SIMD3<Float>(0.19, 0.10, 0.055)
        canvas.fill { u, v in
            let (a, b) = along == .u ? (u, v) : (v, u)   // a: 결 방향, b: 결을 가로지르는 방향
            // 나이테: 결을 가로지르는 방향으로 촘촘하고, 결 방향으로는 천천히 흔들린다
            let wobble = Noise.fbm(a * 2, b * 2, period: 2, octaves: 3, seed: 41) * 2.4
            let rings = fract(b * 7 + wobble)
            let ring = smoothstep(0.0, 0.45, rings) * (1 - smoothstep(0.55, 1.0, rings))
            // 널찍한 색 편차 — 판자마다 색이 조금씩 다른 느낌
            let patch = Noise.fbm(a * 2, b * 4, period: 4, octaves: 2, seed: 45)
            // 잔 섬유질 줄
            let fiber = Noise.value(a * 40, b * 400, period: 400, seed: 43)
            let mix = simd_clamp(0.25 + ring * 0.35 + patch * 0.25 + fiber * 0.15, 0, 1)
            return SIMD4(lerp(dark, light, mix), 1)
        }
        return canvas
    }

    nonisolated static func walnutNormal(along: GrainAxis, size: Int = 256) -> PixelCanvas {
        PixelCanvas.normalMap(from: { u, v in
            let (a, b) = along == .u ? (u, v) : (v, u)
            return Noise.value(a * 30, b * 300, period: 300, seed: 47)
        }, size: size, strength: 0.004)
    }

    // MARK: - 상아색 주사위

    /// 상아색 주사위. 머티리얼 인덱스 순서대로 6장 — `DiePipTexture`의 배치를 따른다.
    /// 텍스처를 못 만들면 눈 없는 상아색 주사위 하나를 돌려준다. 게임이 시작조차 못 하는 것보다는 낫다.
    static func dice() -> [PhysicallyBasedMaterial] {
        var ivory = PhysicallyBasedMaterial()
        ivory.baseColor = .init(tint: .init(red: 0.96, green: 0.94, blue: 0.88, alpha: 1))
        ivory.roughness = .init(floatLiteral: 0.28)
        ivory.metallic = .init(floatLiteral: 0)
        ivory.specular = .init(floatLiteral: 0.6)
        ivory.clearcoat = .init(floatLiteral: 0.6)
        ivory.clearcoatRoughness = .init(floatLiteral: 0.12)

        guard let faces = DiePipTexture.makeFaceTextures(),
              let normals = DiePipTexture.makeFaceNormalMaps() else { return [ivory] }
        return zip(faces, normals).map { albedo, normal in
            var material = ivory
            if let texture = try? TextureResource(image: albedo, options: .init(semantic: .color)) {
                material.baseColor = .init(tint: .white, texture: .init(texture))
            }
            if let texture = try? TextureResource(image: normal, options: .init(semantic: .normal)) {
                material.normal = .init(texture: .init(texture))
            }
            return material
        }
    }

    // MARK: - 도구

    /// 같은 텍스처를 두 번 굽지 않는다. 벽 4면·선반·테이블이 호두나무 한 장을 나눠 쓴다.
    private static var textureCache: [String: MaterialParameters.Texture] = [:]

    private static func cached(_ key: String, _ make: () -> MaterialParameters.Texture?) -> MaterialParameters.Texture? {
        if let hit = textureCache[key] { return hit }
        let made = make()
        textureCache[key] = made
        return made
    }

    private static func texture(_ canvas: PixelCanvas, semantic: TextureResource.Semantic) -> MaterialParameters.Texture? {
        guard let image = canvas.makeImage(),
              let resource = try? TextureResource(image: image, options: .init(semantic: semantic))
        else { return nil }
        return .init(resource)
    }

    nonisolated private static func fract(_ x: Float) -> Float { x - floor(x) }

}
