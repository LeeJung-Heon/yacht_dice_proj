import Foundation
import GameCore

/// 격자(0…12000) ↔ 화면. 판은 정사각형에 맞추고 바깥 여백은 반 칸이다. 규칙은 화면을 모른다.
enum AlkkagiGeometry {
    static let maxPull = 3200
    static let minPull = 200
    /// 판 가장자리 바깥으로 남기는 여백. 반 칸이면 가장자리 돌이 판에 얹히면서도 판이 화면을 거의 다 쓴다.
    static let margin = Alkkagi.spacing / 2
    /// 격자 단위 하나가 화면에서 몇 pt인지.
    static func unit(in size: CGSize) -> CGFloat {
        min(size.width, size.height) / CGFloat(Alkkagi.boardMax + 2 * margin)
    }

    static func project(_ p: Alkkagi.Point, in size: CGSize, flipped: Bool) -> CGPoint {
        let u = unit(in: size)
        let side = min(size.width, size.height)
        let ox = (size.width - side) / 2, oy = (size.height - side) / 2
        var x = ox + (CGFloat(p.x + margin)) * u
        var y = oy + side - (CGFloat(p.y + margin)) * u     // y가 클수록 위
        if flipped { x = size.width - x; y = size.height - y }
        return CGPoint(x: x, y: y)
    }

    static func point(at s: CGPoint, in size: CGSize, flipped: Bool) -> Alkkagi.Point {
        let u = unit(in: size)
        guard u > 0 else { return Alkkagi.Point(x: 0, y: 0) }   // 크기를 아직 못 받은 판에서는 나눌 것이 없다
        let side = min(size.width, size.height)
        let ox = (size.width - side) / 2, oy = (size.height - side) / 2
        var sx = s.x, sy = s.y
        if flipped { sx = size.width - sx; sy = size.height - sy }
        let gx = (sx - ox) / u - CGFloat(margin)
        let gy = (oy + side - sy) / u - CGFloat(margin)
        return Alkkagi.Point(x: Int(gx.rounded()), y: Int(gy.rounded()))
    }

    static func stoneRadius(in size: CGSize) -> CGFloat { CGFloat(Alkkagi.stoneRadius) * unit(in: size) }

    /// 가장 가까운 교차점으로 붙인다. 판 밖으로 나간 손끝은 가장자리 줄에 묶여 배치가 판을 벗어나지 않는다.
    static func snap(_ p: Alkkagi.Point) -> Alkkagi.Point {
        func line(_ v: Int) -> Int {
            let nearest = Int((Double(v) / Double(Alkkagi.spacing)).rounded()) * Alkkagi.spacing
            return min(max(nearest, 0), Alkkagi.boardMax)
        }
        return Alkkagi.Point(x: line(p.x), y: line(p.y))
    }

    /// 여유 안에 든 돌 가운데 가장 가까운 것을 잡는다. 붙어 선 두 돌 사이를 눌러도 손끝에 가까운 쪽이 온다.
    static func stone(at s: CGPoint, stones: [Alkkagi.Point?], in size: CGSize, flipped: Bool) -> Int? {
        let r = stoneRadius(in: size) * 1.6     // 손가락 여유
        return stones.indices.compactMap { i -> (index: Int, d2: CGFloat)? in
            guard let p = stones[i] else { return nil }
            let c = project(p, in: size, flipped: flipped)
            let d2 = (c.x - s.x) * (c.x - s.x) + (c.y - s.y) * (c.y - s.y)
            return d2 <= r * r ? (i, d2) : nil
        }.min { $0.d2 < $1.d2 }?.index
    }

    /// 최대 당김을 넘긴 손가락을 그 방향의 끝점으로 줄인다. 힘이 1000에 묶인 뒤에도 선만 자라면 더 셀 것처럼 보인다.
    static func clampPull(from origin: Alkkagi.Point, to finger: Alkkagi.Point) -> Alkkagi.Point {
        let gx = finger.x - origin.x, gy = finger.y - origin.y
        let len = Alkkagi.isqrt(gx * gx + gy * gy)
        guard len > maxPull else { return finger }
        return Alkkagi.Point(x: origin.x + gx * maxPull / len, y: origin.y + gy * maxPull / len)
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
