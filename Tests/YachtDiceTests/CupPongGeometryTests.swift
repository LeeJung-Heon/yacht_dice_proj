import Testing
import Foundation
import GameCore
@testable import YachtDice

@Suite("컵퐁 기하")
struct CupPongGeometryTests {
    @Test("스와이프가 힘으로 바뀌고 범위를 지킨다")
    func 힘() throws {
        let straight = try #require(CupPongGeometry.shot(dx: 0, dy: 300, speed: 600, screenHeight: 600))
        #expect(straight.dx == 0 && (1...1000).contains(straight.power))
        let right = try #require(CupPongGeometry.shot(dx: 150, dy: 300, speed: 600, screenHeight: 600))
        #expect(right.dx == 500)
        let hard = try #require(CupPongGeometry.shot(dx: 5000, dy: 5000, speed: 100000, screenHeight: 600))
        #expect(hard.dx == 1000 && hard.power == 1000)
        #expect(CupPongGeometry.shot(dx: 10, dy: -50, speed: 600, screenHeight: 600) == nil)
        // 같은 입력은 같은 힘
        #expect(CupPongGeometry.shot(dx: 33, dy: 210, speed: 700, screenHeight: 600)
                == CupPongGeometry.shot(dx: 33, dy: 210, speed: 700, screenHeight: 600))
    }

    @Test("속도는 세기를 15%까지만 더한다")
    func 속도_기여() throws {
        let slow = try #require(CupPongGeometry.shot(dx: 0, dy: 250, speed: 0, screenHeight: 852)).power
        let fast = try #require(CupPongGeometry.shot(dx: 0, dy: 250, speed: 100000, screenHeight: 852)).power
        #expect(fast > slow)
        #expect(abs(fast - slow) <= slow * 15 / 100 + 1)
    }

    @Test("충돌 프레임 사이를 시간으로 보간하고 마지막 표본에 멈춘다")
    func collisionInterpolation() throws {
        let frames = [CupPong.Frame(step: 0, x: 0, y: 0, height: 80),
                      CupPong.Frame(step: 4, x: 40, y: 80, height: 35),
                      CupPong.Frame(step: 8, x: 80, y: 160, height: 70)]
        let falling = try #require(CupPongGeometry.ballFrame(in: frames, at: 2.0 / 240))
        #expect(falling.x == 20 && falling.y == 40 && abs(falling.height - 57.5) < 0.001)
        let bounce = try #require(CupPongGeometry.ballFrame(in: frames, at: 4.0 / 240))
        #expect(bounce.height == 35)
        let rising = try #require(CupPongGeometry.ballFrame(in: frames, at: 6.0 / 240))
        #expect(rising.height == 52.5)
        let end = try #require(CupPongGeometry.ballFrame(in: frames, at: 9))
        #expect(end.x == 80 && end.y == 160 && end.height == 70)
        #expect(CupPongGeometry.ballFrame(in: [], at: 0) == nil)
    }
}
