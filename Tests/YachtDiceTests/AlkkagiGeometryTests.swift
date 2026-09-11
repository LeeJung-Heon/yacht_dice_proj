import Testing
import Foundation
import GameCore
@testable import YachtDice

@Suite("알까기 기하")
struct AlkkagiGeometryTests {
    typealias P = Alkkagi.Point
    let size = CGSize(width: 390, height: 390)

    @Test("격자와 화면이 왕복하고 뒤집으면 대칭이다")
    func 왕복() {
        for p in [P(x: 0, y: 0), P(x: 12000, y: 12000), P(x: 4000, y: 2000), P(x: 6500, y: 9100)] {
            let s = AlkkagiGeometry.project(p, in: size, flipped: false)
            let back = AlkkagiGeometry.point(at: s, in: size, flipped: false)
            #expect(abs(back.x - p.x) <= 40 && abs(back.y - p.y) <= 40, "\(p) → \(back)")
            let f = AlkkagiGeometry.project(p, in: size, flipped: true)
            #expect(abs((f.x + s.x) - size.width) < 0.5 && abs((f.y + s.y) - size.height) < 0.5)
        }
        // 흑(y 작음)은 뒤집지 않으면 아래, 뒤집으면 위
        let black = AlkkagiGeometry.project(P(x: 6000, y: 2000), in: size, flipped: false)
        let white = AlkkagiGeometry.project(P(x: 6000, y: 10000), in: size, flipped: false)
        #expect(black.y > white.y)
    }

    @Test("누른 자리의 돌을 찾는다")
    func 돌_찾기() {
        let stones = Alkkagi.initial().stones[0]
        let on = AlkkagiGeometry.project(P(x: 5000, y: 2000), in: size, flipped: false)
        #expect(AlkkagiGeometry.stone(at: on, stones: stones, in: size, flipped: false) == 1)
        let off = AlkkagiGeometry.project(P(x: 5000, y: 5000), in: size, flipped: false)
        #expect(AlkkagiGeometry.stone(at: off, stones: stones, in: size, flipped: false) == nil)
    }

    @Test("당김 → 힘: 반대 방향, 길이 비례, 범위와 최소 길이")
    func 당김() throws {
        let origin = P(x: 6000, y: 2000)
        let up = try #require(AlkkagiGeometry.flick(stone: 2, from: origin, to: P(x: 6000, y: 400)))   // 아래로 1600 당김
        #expect(up.stone == 2 && up.dx == 0 && up.dy == 1000 && up.power == 500)
        let diag = try #require(AlkkagiGeometry.flick(stone: 2, from: origin, to: P(x: 6000 + 3200, y: 2000 + 3200)))
        #expect(diag.dx == -707 && diag.dy == -707 && diag.power == 1000)   // 4525 > 3200 → 최대
        #expect(AlkkagiGeometry.flick(stone: 0, from: origin, to: P(x: 6100, y: 2000)) == nil)   // 100 < 200
        let tiny = try #require(AlkkagiGeometry.flick(stone: 0, from: origin, to: P(x: 6200, y: 2000)))
        #expect(tiny.power == 62 && tiny.dx == -1000 && tiny.dy == 0)
    }
}
