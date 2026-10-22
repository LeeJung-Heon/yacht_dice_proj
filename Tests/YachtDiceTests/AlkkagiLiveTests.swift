import Testing
import Foundation
import GameCore
@testable import YachtDice

@Suite("알까기 - 상대의 당김과 배치")
struct AlkkagiLiveTests {
    private typealias P = Alkkagi.Point

    /// 두 좌석이 기본 배치를 마친 플레이 단계.
    private func playState() -> Alkkagi.State {
        var log = MoveLog<Alkkagi>()
        for _ in 0..<2 {
            let seat = Alkkagi.currentSeat(log.state)!
            _ = log.append(.setup(Alkkagi.defaultPlacement(seat: seat)))
        }
        #expect(log.state.phase == .play)
        return log.state
    }

    @Test("두 경우 모두 인코딩을 왕복한다")
    func 왕복() throws {
        let values: [AlkkagiLive] = [
            .pull(stone: 2, to: P(x: 4000, y: 3000)),
            .setup(draft: Alkkagi.defaultPlacement(seat: 0), dragging: .init(stone: 1, at: P(x: 500, y: 700))),
            .setup(draft: Alkkagi.defaultPlacement(seat: 1), dragging: nil),
        ]
        for value in values {
            #expect(try JSONDecoder().decode(AlkkagiLive.self, from: JSONEncoder().encode(value)) == value)
        }
    }

    @Test("범위 밖 돌 번호와 판에 없는 돌은 당김을 그리지 않는다")
    func 나쁜_돌() {
        let state = playState()
        #expect(AlkkagiLive.pull(stone: Alkkagi.stonesPerSeat, to: P(x: 0, y: 0)).aim(in: state) == nil)
        #expect(AlkkagiLive.pull(stone: -1, to: P(x: 0, y: 0)).aim(in: state) == nil)
        var dropped = state
        let seat = Alkkagi.currentSeat(state)!
        dropped.stones[seat][0] = nil
        #expect(AlkkagiLive.pull(stone: 0, to: P(x: 0, y: 0)).aim(in: dropped) == nil)
    }

    @Test("배치 단계에는 당김을 그리지 않는다")
    func 배치_중_당김() {
        #expect(AlkkagiLive.pull(stone: 0, to: P(x: 0, y: 0)).aim(in: MoveLog<Alkkagi>().state) == nil)
    }

    @Test("올바른 당김은 그 돌의 자리에서 시작한다")
    func 당김() throws {
        let state = playState()
        let seat = Alkkagi.currentSeat(state)!
        let aim = try #require(AlkkagiLive.pull(stone: 3, to: P(x: 1234, y: 5678)).aim(in: state))
        #expect(aim.stone == 3 && aim.from == state.stones[seat][3] && aim.to == P(x: 1234, y: 5678))
    }

    @Test("초안이 다섯이 아니거나 끄는 돌 번호가 범위 밖이면 버린다")
    func 나쁜_초안() {
        let five = Alkkagi.defaultPlacement(seat: 0)
        #expect(AlkkagiLive.setup(draft: Array(five.prefix(4)), dragging: nil).draft() == nil)
        #expect(AlkkagiLive.setup(draft: five + [P(x: 0, y: 0)], dragging: nil).draft() == nil)
        #expect(AlkkagiLive.setup(draft: five, dragging: .init(stone: 5, at: P(x: 0, y: 0))).draft() == nil)
        #expect(AlkkagiLive.setup(draft: five, dragging: .init(stone: 4, at: P(x: 0, y: 0))).draft()?.points == five)
        #expect(AlkkagiLive.pull(stone: 0, to: P(x: 0, y: 0)).draft() == nil)
    }

    @Test("보간은 0ms에 직전 값, 50ms에 중간, 100ms 뒤에 새 값이다")
    func 보간() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        var track = AlkkagiLiveTrack(P(x: 0, y: 0), at: t0)
        #expect(track.point(at: t0) == P(x: 0, y: 0) && !track.isMoving(at: t0))
        track.update(P(x: 1000, y: 2000), at: t0)
        #expect(track.point(at: t0) == P(x: 0, y: 0))
        #expect(track.point(at: t0.addingTimeInterval(0.05)) == P(x: 500, y: 1000))
        #expect(track.isMoving(at: t0.addingTimeInterval(0.05)))
        #expect(track.point(at: t0.addingTimeInterval(0.1)) == P(x: 1000, y: 2000))
        #expect(!track.isMoving(at: t0.addingTimeInterval(0.1)))
        // 움직이는 도중에 새 값이 오면 그 시각의 자리에서 다시 잇는다
        track.update(P(x: 0, y: 0), at: t0.addingTimeInterval(0.15))
        #expect(track.point(at: t0.addingTimeInterval(0.15)) == P(x: 1000, y: 2000))
    }
}
