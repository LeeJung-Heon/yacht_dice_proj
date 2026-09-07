import Testing
import Foundation
import CoreGraphics
import simd
@testable import YachtDice

/// 절차적 텍스처가 "그림이 되는가"를 지킨다. 노이즈가 이음매 없이 이어지는지,
/// 노멀맵이 평평한 곳에서 (0.5, 0.5, 1)을 주는지, 재질 텍스처가 실제로 만들어지는지.
@Suite("절차적 텍스처")
struct ProceduralTextureTests {

    @Test("값 노이즈는 period마다 정확히 반복된다 — 이어 붙여도 이음매가 없다")
    func 노이즈_주기() {
        for (x, y) in [(0.3, 0.7), (2.25, 5.5), (7.9, 0.1)] as [(Float, Float)] {
            let a = Noise.value(x, y, period: 8, seed: 5)
            let b = Noise.value(x + 8, y - 16, period: 8, seed: 5)
            #expect(abs(a - b) < 1e-5, "(\(x), \(y))에서 \(a) vs \(b)")
        }
    }

    @Test("노이즈는 결정적이고 0...1 안에 있다")
    func 노이즈_범위() {
        var minimum: Float = 1, maximum: Float = 0
        for i in 0..<64 {
            for j in 0..<64 {
                let v = Noise.fbm(Float(i) * 0.37, Float(j) * 0.29, period: 16, octaves: 3, seed: 9)
                #expect(v == Noise.fbm(Float(i) * 0.37, Float(j) * 0.29, period: 16, octaves: 3, seed: 9))
                minimum = min(minimum, v); maximum = max(maximum, v)
            }
        }
        #expect(minimum >= 0 && maximum <= 1)
        #expect(maximum - minimum > 0.2, "노이즈가 거의 평평하다: \(minimum)...\(maximum)")
    }

    @Test("평평한 높이맵의 노멀맵은 전부 위를 향한다")
    func 평평한_노멀() {
        let canvas = PixelCanvas.normalMap(from: { _, _ in 0.5 }, size: 8, strength: 2)
        let image = canvas.makeImage()!
        let pixels = bytes(of: image)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            #expect(pixels[offset] == 128 && pixels[offset + 1] == 128 && pixels[offset + 2] == 255,
                    "픽셀 \(offset / 4): \(pixels[offset]), \(pixels[offset + 1]), \(pixels[offset + 2])")
        }
    }

    @Test("주사위 눈 노멀맵은 눈 한가운데는 평평하고, 눈 테두리에서는 기울어진다")
    func 눈_노멀() throws {
        let size = 128
        let image = try #require(DiePipTexture.makeFaceNormalMap(value: 1, size: size))
        let pixels = bytes(of: image)
        func normal(_ u: Float, _ v: Float) -> SIMD3<Int> {
            let x = Int(u * Float(size)), y = Int(v * Float(size))
            let o = (y * size + x) * 4
            return SIMD3(Int(pixels[o]), Int(pixels[o + 1]), Int(pixels[o + 2]))
        }
        // 정확한 중심은 픽셀 네 개의 경계에 있다. 네 픽셀의 평균이 평평해야 한다.
        let half = 0.5 / Float(size)
        let center = normal(0.5 - half, 0.5 - half) &+ normal(0.5 + half, 0.5 - half)
            &+ normal(0.5 - half, 0.5 + half) &+ normal(0.5 + half, 0.5 + half)
        #expect(abs(center.x - 512) <= 4 && abs(center.y - 512) <= 4 && center.z >= 4 * 254,
                "눈 한가운데가 평평하지 않다: \(center)")
        #expect(normal(0.05, 0.05) == SIMD3(128, 128, 255), "눈 밖이 평평하지 않다")
        let rim = normal(0.5 + DiePipTexture.pipRadius * 0.85, 0.5)
        #expect(rim.z < 250, "눈 테두리가 기울지 않았다: \(rim)")
    }

    @Test("재질 텍스처가 전부 만들어지고 크기가 맞는다")
    func 재질_텍스처() throws {
        let leather = try #require(SceneMaterials.leatherAlbedo(vignette: true, size: 64).makeImage())
        #expect(leather.width == 64 && leather.height == 64)
        let wood = try #require(SceneMaterials.walnutAlbedo(along: .u, size: 64).makeImage())
        #expect(wood.width == 64)
        let env = try #require(SceneLighting.makeStudioEnvironment(width: 64, height: 32).makeImage())
        #expect(env.width == 64 && env.height == 32)
    }

    @Test("환경광은 천장이 바닥보다 밝고, 소프트박스가 천장보다 밝다")
    func 환경광_밝기() throws {
        let image = try #require(SceneLighting.makeStudioEnvironment(width: 128, height: 64).makeImage())
        let pixels = bytes(of: image)
        func luma(_ u: Float, _ v: Float) -> Int {
            let o = (Int(v * 64) * 128 + Int(u * 128)) * 4
            return Int(pixels[o]) + Int(pixels[o + 1]) + Int(pixels[o + 2])
        }
        #expect(luma(0.25, 0.05) > luma(0.25, 0.95), "천장이 바닥보다 어둡다")
        #expect(luma(0.5, 0.18) >= 3 * 250, "소프트박스가 흰색에 가깝지 않다")
        #expect(luma(0.5, 0.18) > luma(0.25, 0.05), "소프트박스가 천장보다 밝지 않다")
    }

    @Test("가죽 바닥은 가장자리가 가운데보다 어둡다 (비네트)")
    func 가죽_비네트() throws {
        let image = try #require(SceneMaterials.leatherAlbedo(vignette: true, size: 64).makeImage())
        let pixels = bytes(of: image)
        func red(_ x: Int, _ y: Int) -> Int { Int(pixels[(y * 64 + x) * 4]) }
        var center = 0, edge = 0
        for i in 28..<36 { center += red(i, 32); edge += red(i, 1) }
        #expect(edge < center, "가장자리(\(edge))가 가운데(\(center))보다 어둡지 않다")
    }

    private func bytes(of image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data as Data? else { return [] }
        return [UInt8](data)
    }
}
