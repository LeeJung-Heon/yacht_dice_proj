import SwiftUI
import CoreGraphics

/// 종이·가죽·나무 결. 회색 픽셀의 알파에 노이즈를 넣어 어떤 배경색 위에든 얹는다.
/// 3D 씬과 같은 노이즈(`ProceduralTexture`)를 써서 화면과 트레이의 재질 언어가 같다.
@MainActor
enum SurfaceTextures {
    enum Kind: CaseIterable, Sendable { case paper, leather, wood }

    private static var cache: [Kind: Image] = [:]

    static var paper: Image { image(.paper) }
    static var leather: Image { image(.leather) }
    static var wood: Image { image(.wood) }

    private static func image(_ kind: Kind) -> Image {
        if let hit = cache[kind] { return hit }
        let made = makeGrain(kind: kind, size: 512).map { Image(decorative: $0, scale: 1) } ?? Image(systemName: "square")
        cache[kind] = made
        return made
    }

    /// 밝은 점은 흰색, 어두운 점은 검정. 알파가 결의 세기라 배경의 밝기만 흔든다.
    nonisolated static func makeGrain(kind: Kind, size: Int) -> CGImage? {
        var canvas = PixelCanvas(width: size, height: size)
        canvas.fill { u, v in
            let n: Float
            switch kind {
            case .paper:
                n = Noise.fbm(u * 64, v * 64, period: 64, octaves: 3, seed: 101)
            case .leather:
                n = Noise.fbm(u * 24, v * 24, period: 24, octaves: 3, seed: 103) * 0.7
                    + Noise.value(u * 160, v * 160, period: 160, seed: 107) * 0.3
            case .wood:
                let wobble = Noise.fbm(u * 2, v * 2, period: 2, octaves: 3, seed: 109) * 2.4
                let rings = (v * 7 + wobble).truncatingRemainder(dividingBy: 1)
                n = smoothstep(0, 0.45, rings) * (1 - smoothstep(0.55, 1, rings)) * 0.7
                    + Noise.value(u * 40, v * 400, period: 400, seed: 113) * 0.3
            }
            let bright: Float = n > 0.5 ? 1 : 0
            return SIMD4(bright, bright, bright, abs(n - 0.5) * 2)
        }
        return canvas.makeImage()
    }
}
