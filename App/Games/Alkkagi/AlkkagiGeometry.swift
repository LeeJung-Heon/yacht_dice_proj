import Foundation
import GameCore

/// 격자(0…12000) ↔ 화면. 판은 정사각형에 맞추고 바깥 여백은 칸 하나다. 규칙은 화면을 모른다.
enum AlkkagiGeometry {
    static let maxPull = 3200
    static let minPull = 200
    /// 격자 단위 하나가 화면에서 몇 pt인지.
    static func unit(in size: CGSize) -> CGFloat {
        min(size.width, size.height) / CGFloat(Alkkagi.boardMax + 2 * Alkkagi.spacing)
    }

    static func project(_ p: Alkkagi.Point, in size: CGSize, flipped: Bool) -> CGPoint {
        let u = unit(in: size)
        let side = min(size.width, size.height)
        let ox = (size.width - side) / 2, oy = (size.height - side) / 2
        var x = ox + (CGFloat(p.x + Alkkagi.spacing)) * u
        var y = oy + side - (CGFloat(p.y + Alkkagi.spacing)) * u     // y가 클수록 위
        if flipped { x = size.width - x; y = size.height - y }
        return CGPoint(x: x, y: y)
    }

    static func point(at s: CGPoint, in size: CGSize, flipped: Bool) -> Alkkagi.Point {
        let u = unit(in: size)
        let side = min(size.width, size.height)
        let ox = (size.width - side) / 2, oy = (size.height - side) / 2
        var sx = s.x, sy = s.y
        if flipped { sx = size.width - sx; sy = size.height - sy }
        let gx = (sx - ox) / u - CGFloat(Alkkagi.spacing)
        let gy = (oy + side - sy) / u - CGFloat(Alkkagi.spacing)
        return Alkkagi.Point(x: Int(gx.rounded()), y: Int(gy.rounded()))
    }

    static func stoneRadius(in size: CGSize) -> CGFloat { CGFloat(Alkkagi.stoneRadius) * unit(in: size) }

    static func stone(at s: CGPoint, stones: [Alkkagi.Point?], in size: CGSize, flipped: Bool) -> Int? {
        let r = stoneRadius(in: size) * 1.3     // 손가락 여유
        return stones.indices.first { i in
            guard let p = stones[i] else { return false }
            let c = project(p, in: size, flipped: flipped)
            return (c.x - s.x) * (c.x - s.x) + (c.y - s.y) * (c.y - s.y) <= r * r
        }
    }

    /// 돌에서 손가락까지의 격자 벡터가 당김이다. 힘은 반대 방향으로, 길이에 비례한다.
    static func flick(stone: Int, from origin: Alkkagi.Point, to finger: Alkkagi.Point) -> Alkkagi.Flick? {
        let gx = finger.x - origin.x, gy = finger.y - origin.y
        let len = Alkkagi.isqrt(gx * gx + gy * gy)
        guard len >= minPull else { return nil }
        let power = max(1, min(1000, len * 1000 / maxPull))
        return Alkkagi.Flick(stone: stone, dx: -gx * 1000 / len, dy: -gy * 1000 / len, power: power)
    }
}
