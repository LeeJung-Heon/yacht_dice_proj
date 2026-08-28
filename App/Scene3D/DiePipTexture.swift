import Foundation
import CoreGraphics
import RealityKit
import UIKit

/// 주사위 6면 눈을 코드로 그려 하나의 아틀라스 텍스처로 만든다.
/// 외부 3D 아티스트 없이 진행하기 위한 선택이다 (스펙 §13).
enum DiePipTexture {
    /// generateBox의 UV는 6면이 가로로 이어진 아틀라스를 기대한다.
    static func makeAtlas(faceSize: Int = 256) -> CGImage? {
        let width = faceSize * 6
        let height = faceSize
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        context.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(UIColor(white: 0.12, alpha: 1).cgColor)

        // generateBox의 면 순서: +X, -X, +Y, -Y, +Z, -Z
        // DieFace의 배치와 맞춘다: +X=3, -X=4, +Y=1, -Y=6, +Z=2, -Z=5
        let facesInAtlasOrder = [3, 4, 1, 6, 2, 5]
        let radius = CGFloat(faceSize) * 0.09

        for (slot, value) in facesInAtlasOrder.enumerated() {
            let originX = CGFloat(slot * faceSize)
            for point in pipLayout(for: value) {
                let center = CGPoint(
                    x: originX + point.x * CGFloat(faceSize),
                    y: point.y * CGFloat(faceSize))
                context.fillEllipse(in: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2))
            }
        }
        return context.makeImage()
    }

    /// 면 안에서의 상대 좌표 (0...1).
    private static func pipLayout(for value: Int) -> [CGPoint] {
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
