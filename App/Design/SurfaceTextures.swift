import SwiftUI
import CoreGraphics

/// 종이·가죽·나무 질감. 3D 트레이와 같은 생성기(`SceneMaterials`)를 써서 화면과 트레이의 재질이 같다.
///
/// 나무와 가죽은 색이 있는 텍스처를 그대로 깐다. 종이는 회색 결을 알파에 담아 종이색 위에 얹는다.
/// `scale: 2`로 만들어 512px가 256pt가 되게 한다 — 1x로 깔면 화면에서 픽셀이 세 배로 뭉개져 얼룩처럼 보인다.
@MainActor
enum SurfaceTextures {
    enum Kind: CaseIterable, Sendable { case paper, leather, wood }

    private static var cache: [Kind: Image] = [:]

    static var paper: Image { image(.paper) }
    static var leather: Image { image(.leather) }
    static var wood: Image { image(.wood) }

    private static func image(_ kind: Kind) -> Image {
        if let hit = cache[kind] { return hit }
        let made = makeGrain(kind: kind, size: 512).map { Image(decorative: $0, scale: 2) } ?? Image(systemName: "square")
        cache[kind] = made
        return made
    }

    nonisolated static func makeGrain(kind: Kind, size: Int) -> CGImage? {
        switch kind {
        case .wood:
            return SceneMaterials.walnutAlbedo(along: .u, size: size).makeImage()
        case .leather:
            return SceneMaterials.leatherAlbedo(vignette: false, size: size).makeImage()
        case .paper:
            // 잔 섬유 결. 알파는 작게 — 종이는 거의 평평해야 한다.
            var canvas = PixelCanvas(width: size, height: size)
            canvas.fill { u, v in
                let fiber = Noise.fbm(u * 128, v * 128, period: 128, octaves: 2, seed: 101)
                let speck = Noise.value(u * 300, v * 300, period: 300, seed: 103)
                let n = fiber * 0.6 + speck * 0.4 - 0.5
                let bright: Float = n > 0 ? 1 : 0
                return SIMD4(bright, bright, bright, min(1, abs(n) * 1.6))
            }
            return canvas.makeImage()
        }
    }
}
