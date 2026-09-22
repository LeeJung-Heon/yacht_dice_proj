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
        for p in [P(x: 0, y: 0), P(x: 16000, y: 16000), P(x: 14000, y: 2000), P(x: 6500, y: 9100)] {
            let s = AlkkagiGeometry.project(p, in: size, flipped: false)
            let back = AlkkagiGeometry.point(at: s, in: size, flipped: false)
            #expect(abs(back.x - p.x) <= 2 && abs(back.y - p.y) <= 2, "\(p) → \(back)")
            let f = AlkkagiGeometry.project(p, in: size, flipped: true)
            #expect(abs((f.x + s.x) - size.width) < 0.5 && abs((f.y + s.y) - size.height) < 0.5)
        }
        // 흑(y 작음)은 뒤집지 않으면 아래, 뒤집으면 위
        let black = AlkkagiGeometry.project(P(x: 6000, y: 2000), in: size, flipped: false)
        let white = AlkkagiGeometry.project(P(x: 6000, y: 10000), in: size, flipped: false)
        #expect(black.y > white.y)
    }

    @Test("모서리 돌 전체가 보이며 확대된 판은 화면을 거의 다 쓴다")
    func 여백() {
        let u = AlkkagiGeometry.unit(in: size)
        let corner = AlkkagiGeometry.project(P(x: 0, y: 0), in: size, flipped: false)
        let far = AlkkagiGeometry.project(P(x: 16000, y: 0), in: size, flipped: false)
        let radius = AlkkagiGeometry.stoneRadius(in: size)
        #expect(corner.x - radius >= -0.5 && far.x + radius <= size.width + 0.5)
        #expect(far.x - corner.x >= size.width * 0.95)
        #expect(u > 0)
    }

    @Test("놓은 자리는 가장 가까운 교차점으로 붙고 판 안에 묶인다")
    func 교차점_붙이기() {
        #expect(AlkkagiGeometry.snap(P(x: 4499, y: 5501)) == P(x: 4000, y: 6000))
        #expect(AlkkagiGeometry.snap(P(x: -300, y: 16800)) == P(x: 0, y: 16000))
    }

    @Test("누른 자리의 돌을 찾는다")
    func 돌_찾기() {
        let stones = Alkkagi.standardStart().stones[0]
        let on = AlkkagiGeometry.project(P(x: 7000, y: 3000), in: size, flipped: false)
        #expect(AlkkagiGeometry.stone(at: on, stones: stones, in: size, flipped: false) == 1)
        let off = AlkkagiGeometry.project(P(x: 5000, y: 5000), in: size, flipped: false)
        #expect(AlkkagiGeometry.stone(at: off, stones: stones, in: size, flipped: false) == nil)
        // 돌 1(7000)과 돌 2(8000) 사이지만 2에 더 가깝다.
        let between = AlkkagiGeometry.project(P(x: 7505, y: 3000), in: size, flipped: false)
        #expect(AlkkagiGeometry.stone(at: between, stones: stones, in: size, flipped: false) == 2)
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

    @Test("강한 샷도 예상선은 최대 두 칸 반까지만 보인다")
    func 강한_샷_미리보기() throws {
        let state = Alkkagi.standardStart()
        let path = AlkkagiGeometry.preview(state: state, flick: .init(stone: 0, dx: 0, dy: 1000, power: 1000))
        let first = try #require(path.first), last = try #require(path.last)
        #expect(first == P(x: 6000, y: 3000))
        #expect((2000...2500).contains(last.y - first.y))
        #expect(path.allSatisfy { $0.x == 6000 && $0.y <= 5500 })
    }

    @Test("중간 세기의 예상선은 첫 0.2초 이후 위치를 보여주지 않는다")
    func 미리보기_시간_제한() throws {
        let state = Alkkagi.State(stones: [[P(x: 8000, y: 3000), nil, nil, nil, nil],
                                          [P(x: 14000, y: 13000), nil, nil, nil, nil]], nextSeat: 0, outcome: nil)
        let path = AlkkagiGeometry.preview(state: state, flick: .init(stone: 0, dx: 0, dy: 1000, power: 450))
        // 초기 속도 13500에서 마찰 100/스텝을 적용한 첫 24스텝의 정수 이동 합은 2460이다.
        let last = try #require(path.last)
        #expect(last == P(x: 8000, y: 5460))
    }

    @Test("최소 당김에 가까운 약한 샷도 최종 정지점까지 노출하지 않는다")
    func 약한_샷_미리보기() throws {
        let state = Alkkagi.standardStart()
        let flick = Alkkagi.Flick(stone: 0, dx: 0, dy: 1000, power: 62)
        let path = AlkkagiGeometry.preview(state: state, flick: flick)
        let last = try #require(path.last)
        let final = try #require(Alkkagi.simulate(state, flick).final[0][0])
        #expect(last.y > 3000)
        #expect((last.y - 3000) * 3 <= final.y - 3000)
        #expect(last != final)
    }

    @Test("첫 프레임 전에 돌이나 범퍼에 닿으면 반사 궤적을 드러내지 않는다", arguments: [false, true])
    func 접촉_뒤_미리보기_숨김(bumper: Bool) {
        let state = Alkkagi.State(stones: [[P(x: 8000, y: bumper ? 5900 : 3000), nil, nil, nil, nil],
                                          [P(x: bumper ? 14000 : 8000, y: bumper ? 13000 : 3800), nil, nil, nil, nil]],
                                  nextSeat: 0, outcome: nil, roundNumber: bumper ? 3 : 1)
        let flick = Alkkagi.Flick(stone: 0, dx: 0, dy: 1000, power: 1000)
        let sim = Alkkagi.simulate(state, flick)
        #expect(sim.events.first?.step == 1, "첫 접촉이 첫 프레임보다 빠른 실제 물리 사례")
        #expect(AlkkagiGeometry.preview(state: state, flick: flick).isEmpty)
    }

    @Test("실제 이동이 없는 아주 작은 힘과 무효 입력에는 예상선을 그리지 않는다")
    func 미리보기_없는_입력() {
        let state = Alkkagi.standardStart()
        #expect(AlkkagiGeometry.preview(state: state, flick: .init(stone: 0, dx: 0, dy: 1000, power: 1)).isEmpty)
        #expect(AlkkagiGeometry.preview(state: state, flick: .init(stone: 0, dx: 0, dy: 0, power: 500)).isEmpty)
    }
}
