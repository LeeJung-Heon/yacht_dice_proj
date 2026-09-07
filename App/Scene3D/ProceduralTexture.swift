import Foundation
import CoreGraphics
import simd

/// 코드로 텍스처를 그리기 위한 최소 도구. 외부 이미지 에셋 없이 진행한다 (스펙 §13).
///
/// RGBA8 픽셀 버퍼 하나와, 그 위에 그릴 때 쓰는 결정적 노이즈다.
/// 시드가 같으면 어느 기기에서든 같은 그림이 나온다.
struct PixelCanvas {
    let width: Int
    let height: Int
    private(set) var rgba: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        rgba = [UInt8](repeating: 255, count: width * height * 4)
    }

    /// 픽셀마다 (u, v) ∈ [0, 1)²를 주고 색(0...1)을 돌려받는다.
    mutating func fill(_ shader: (_ u: Float, _ v: Float) -> SIMD4<Float>) {
        let du = 1 / Float(width), dv = 1 / Float(height)
        for y in 0..<height {
            let v = (Float(y) + 0.5) * dv
            for x in 0..<width {
                let color = simd_clamp(shader((Float(x) + 0.5) * du, v), .zero, .one)
                let offset = (y * width + x) * 4
                rgba[offset]     = UInt8(color.x * 255 + 0.5)
                rgba[offset + 1] = UInt8(color.y * 255 + 0.5)
                rgba[offset + 2] = UInt8(color.z * 255 + 0.5)
                rgba[offset + 3] = UInt8(color.w * 255 + 0.5)
            }
        }
    }

    func makeImage() -> CGImage? {
        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// 높이맵(0...1)을 접선 공간 노멀맵으로 바꾼다. 이어 붙여도 끊기지 않게 가장자리는 감싼다.
    ///
    /// 기울기는 픽셀 단위가 아니라 **UV 단위**로 잰다 — 그래야 `strength`가 텍스처 해상도와
    /// 무관하게 "높이 1이 UV 1에 걸쳐 오를 때의 경사"를 뜻한다. 픽셀 단위로 재면 256px 텍스처에서
    /// 경사가 1/256로 쪼그라들어 눈의 홈이 사실상 평평해진다.
    static func normalMap(from height: (_ u: Float, _ v: Float) -> Float,
                          size: Int, strength: Float) -> PixelCanvas {
        var canvas = PixelCanvas(width: size, height: size)
        let step = 1 / Float(size)
        canvas.fill { u, v in
            let left = height(wrap(u - step), v), right = height(wrap(u + step), v)
            let down = height(u, wrap(v - step)), up = height(u, wrap(v + step))
            let slopeU = (left - right) / (2 * step) * strength
            let slopeV = (down - up) / (2 * step) * strength
            let normal = simd_normalize(SIMD3(slopeU, slopeV, 1))
            return SIMD4(normal * 0.5 + 0.5, 1)
        }
        return canvas
    }

    private static func wrap(_ t: Float) -> Float { t - floor(t) }
}

/// 결정적 값 노이즈. `period`로 격자를 감싸서 텍스처를 이어 붙여도 이음매가 없다.
enum Noise {
    /// (0...1). `period`는 격자 한 변의 칸 수다 — x, y에 곱해진 스케일과 같게 주면 tileable하다.
    static func value(_ x: Float, _ y: Float, period: Int, seed: UInt32) -> Float {
        let x0 = floor(x), y0 = floor(y)
        let fx = smooth(x - x0), fy = smooth(y - y0)
        let ix = Int(x0), iy = Int(y0)
        let a = lattice(ix, iy, period, seed), b = lattice(ix + 1, iy, period, seed)
        let c = lattice(ix, iy + 1, period, seed), d = lattice(ix + 1, iy + 1, period, seed)
        return simd_mix(simd_mix(a, b, fx), simd_mix(c, d, fx), fy)
    }

    /// 여러 옥타브를 겹친 값 노이즈 (0...1 근방).
    static func fbm(_ x: Float, _ y: Float, period: Int, octaves: Int, seed: UInt32) -> Float {
        var sum: Float = 0, amplitude: Float = 0.5, total: Float = 0
        var frequency: Float = 1
        var currentPeriod = period
        for octave in 0..<octaves {
            sum += value(x * frequency, y * frequency, period: currentPeriod, seed: seed &+ UInt32(octave) &* 7919) * amplitude
            total += amplitude
            amplitude *= 0.5
            frequency *= 2
            currentPeriod *= 2
        }
        return sum / total
    }

    private static func smooth(_ t: Float) -> Float { t * t * (3 - 2 * t) }

    private static func lattice(_ x: Int, _ y: Int, _ period: Int, _ seed: UInt32) -> Float {
        let px = UInt32(((x % period) + period) % period)
        let py = UInt32(((y % period) + period) % period)
        var h = seed &+ px &* 374_761_393 &+ py &* 668_265_263
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0xFFFFFF) / Float(0xFFFFFF)
    }
}

/// 색 두 개를 스칼라로 섞는다. `simd_mix`는 t도 벡터로 요구해서 셰이더 코드가 지저분해진다.
func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

/// GLSL의 smoothstep. edge0 아래는 0, edge1 위는 1, 사이는 부드러운 S자.
func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = simd_clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
}
