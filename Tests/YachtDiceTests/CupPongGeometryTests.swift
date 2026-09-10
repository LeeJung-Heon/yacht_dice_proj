import Testing
import Foundation
import GameCore
@testable import YachtDice

@Suite("컵퐁 기하")
struct CupPongGeometryTests {
    let size = CGSize(width: 400, height: 600)

    @Test("먼 쪽이 위이고 좁다")
    func 원근() {
        let near = CupPongGeometry.project(x: -1000, y: 0, in: size)
        let far = CupPongGeometry.project(x: -1000, y: 3000, in: size)
        #expect(far.y < near.y)
        #expect(abs(far.x - size.width / 2) < abs(near.x - size.width / 2))
        #expect(CupPongGeometry.project(x: 0, y: 1500, in: size).x == size.width / 2)
        #expect(CupPongGeometry.scale(y: 3000, in: size) < CupPongGeometry.scale(y: 0, in: size))
    }

    @Test("스와이프가 힘으로 바뀌고 범위를 지킨다")
    func 힘() throws {
        let straight = try #require(CupPongGeometry.shot(dx: 0, dy: 300, duration: 0.3, screenHeight: 600))
        #expect(straight.dx == 0 && (0...1000).contains(straight.power) && straight.power > 0)
        let right = try #require(CupPongGeometry.shot(dx: 150, dy: 300, duration: 0.3, screenHeight: 600))
        #expect(right.dx == 500)
        let hard = try #require(CupPongGeometry.shot(dx: 5000, dy: 5000, duration: 0.01, screenHeight: 600))
        #expect(hard.dx == 1000 && hard.power == 1000)
        #expect(CupPongGeometry.shot(dx: 10, dy: -50, duration: 0.3, screenHeight: 600) == nil)
        // 같은 입력은 같은 힘
        #expect(CupPongGeometry.shot(dx: 33, dy: 210, duration: 0.25, screenHeight: 600)
                == CupPongGeometry.shot(dx: 33, dy: 210, duration: 0.25, screenHeight: 600))
    }

    @Test("공은 던지는 곳에서 출발해 착지점에 닿고 중간에 가장 높다")
    func 포물선() {
        let landing = CupPong.Landing(x: 200, y: 2400, cup: nil)
        let start = CupPongGeometry.ballPath(to: landing, progress: 0)
        let mid = CupPongGeometry.ballPath(to: landing, progress: 0.5)
        let end = CupPongGeometry.ballPath(to: landing, progress: 1)
        #expect(start.x == 0 && start.y == 0 && start.height == 0)
        #expect(end.x == 200 && end.y == 2400 && end.height == 0)
        #expect(mid.height > start.height && mid.height > end.height)
    }
}
