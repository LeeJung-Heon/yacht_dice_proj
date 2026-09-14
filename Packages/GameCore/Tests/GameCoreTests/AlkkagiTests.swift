import Foundation
import Testing
@testable import GameCore

@Suite("알까기 규칙")
struct AlkkagiTests {
    typealias P = Alkkagi.Point

    /// 두 좌석의 기본 배치를 놓은 뒤, 좌석 0이 돌 i를 곧장 위로 세게 튕겨 같은 x의 백 돌을 떨어뜨리고
    /// 좌석 1은 힘 1로 제자리 튕김을 하는 열한 수다.
    static func winningMoves() -> [Alkkagi.Move] {
        var moves: [Alkkagi.Move] = [.setup(Alkkagi.defaultPlacement(seat: 0)), .setup(Alkkagi.defaultPlacement(seat: 1))]
        for i in 0..<5 {
            moves.append(.flick(.init(stone: i, dx: 0, dy: 1000, power: 1000)))
            if i < 4 { moves.append(.flick(.init(stone: i + 1, dx: 1000, dy: 0, power: 1))) }
        }
        return moves
    }

    @Test("판이 열리면 돌이 하나도 없고 좌석 0부터 놓는다")
    func 초기_배치_전() {
        let s = Alkkagi.initial()
        #expect(s.stones == [[Alkkagi.Point?]](repeating: [nil, nil, nil, nil, nil], count: 2))
        #expect(s.phase == .setup && s.placed == [false, false])
        #expect(Alkkagi.currentSeat(s) == 0 && s.remaining(seat: 0) == 0 && s.remaining(seat: 1) == 0)
        for seat in 0..<2 {
            let points = Alkkagi.defaultPlacement(seat: seat)
            #expect(points.count == 5)
            #expect(points.allSatisfy { Alkkagi.homeRange(seat: seat).contains($0.y) })
            #expect(Alkkagi.placementIsValid(points, seat: seat))
        }
    }

    @Test("배치는 다섯 점이 제 진영 교차점에 서로 떨어져 놓여야 한다")
    func 배치_검증() {
        let s = Alkkagi.initial()
        let 기본 = Alkkagi.defaultPlacement(seat: 0)
        #expect(Alkkagi.canApply(.setup(기본), to: s))
        // 개수가 다섯이 아니다
        #expect(!Alkkagi.placementIsValid(Array(기본.prefix(4)), seat: 0))
        #expect(!Alkkagi.placementIsValid(기본 + [P(x: 1000, y: 1000)], seat: 0))
        // 제 진영 밖(좌석 0의 y는 0…5000)
        #expect(!Alkkagi.placementIsValid([P(x: 4000, y: 6000)] + 기본.dropFirst(), seat: 0))
        #expect(!Alkkagi.placementIsValid([P(x: 13000, y: 2000)] + 기본.dropFirst(), seat: 0))
        // 교차점이 아니다
        #expect(!Alkkagi.placementIsValid([P(x: 4500, y: 2000)] + 기본.dropFirst(), seat: 0))
        #expect(!Alkkagi.placementIsValid([P(x: 4000, y: 2500)] + 기본.dropFirst(), seat: 0))
        // 서로 800 미만으로 붙었다(같은 점은 거리 0)
        #expect(!Alkkagi.placementIsValid([P(x: 5000, y: 2000)] + 기본.dropFirst(), seat: 0))
        // 남의 진영에는 못 놓는다
        #expect(!Alkkagi.placementIsValid(Alkkagi.defaultPlacement(seat: 1), seat: 0))
        #expect(!Alkkagi.canApply(.setup(Alkkagi.defaultPlacement(seat: 1)), to: s))
        // 같은 좌석이 두 번 놓을 수는 없다
        let 놓은 = Alkkagi.apply(.setup(기본), to: s)
        #expect(!Alkkagi.canApply(.setup(기본), to: 놓은))
    }

    @Test("좌석 0이 놓고 좌석 1이 놓으면 튕기기가 시작된다")
    func 배치_순서() {
        let s = Alkkagi.initial()
        // 배치 전에는 튕길 수 없다
        #expect(!Alkkagi.canApply(.flick(.init(stone: 0, dx: 0, dy: 1000, power: 500)), to: s))
        let 흑 = Alkkagi.apply(.setup(Alkkagi.defaultPlacement(seat: 0)), to: s)
        #expect(흑.placed == [true, false] && 흑.phase == .setup && Alkkagi.currentSeat(흑) == 1)
        #expect(흑.stones[0].compactMap { $0 } == Alkkagi.defaultPlacement(seat: 0) && 흑.remaining(seat: 1) == 0)
        #expect(!Alkkagi.canApply(.flick(.init(stone: 0, dx: 0, dy: 1000, power: 500)), to: 흑))
        let 백 = Alkkagi.apply(.setup(Alkkagi.defaultPlacement(seat: 1)), to: 흑)
        #expect(백.placed == [true, true] && 백.phase == .play && Alkkagi.currentSeat(백) == 0)
        #expect(Alkkagi.canApply(.flick(.init(stone: 0, dx: 0, dy: 1000, power: 500)), to: 백))
    }

    @Test("표준 시작은 두 기본 배치를 놓은 한 줄이다")
    func 표준_시작() {
        let s = Alkkagi.standardStart()
        #expect(s.stones[0] == (0..<5).map { P(x: 4000 + $0 * 1000, y: 2000) })
        #expect(s.stones[1] == (0..<5).map { P(x: 4000 + $0 * 1000, y: 10000) })
        #expect(s.phase == .play && s.placed == [true, true])
        #expect(Alkkagi.currentSeat(s) == 0 && s.remaining(seat: 0) == 5 && s.remaining(seat: 1) == 5)
    }

    @Test("정수 제곱근")
    func 제곱근() {
        #expect(Alkkagi.isqrt(0) == 0 && Alkkagi.isqrt(1) == 1 && Alkkagi.isqrt(15) == 3 && Alkkagi.isqrt(16) == 4)
        #expect(Alkkagi.isqrt(1_000_000_000_000) == 1_000_000)
        #expect(Alkkagi.isqrt(-1) == 0 && Alkkagi.isqrt(Int.min) == 0)
        #expect(Alkkagi.isqrt(Int.max) == 3_037_000_499)
    }

    @Test("같은 수는 같은 시뮬레이션이다")
    func 결정성() {
        let s = Alkkagi.standardStart()
        let f = Alkkagi.Flick(stone: 2, dx: 300, dy: 900, power: 700)
        #expect(Alkkagi.simulate(s, f) == Alkkagi.simulate(s, f))
    }

    @Test("옆으로 튕긴 돌은 마찰로 멈추고 판 위에 남는다")
    func 마찰() {
        let s = Alkkagi.standardStart()
        let sim = Alkkagi.simulate(s, .init(stone: 0, dx: -1000, dy: 0, power: 300))   // 속도 9000, 제동 거리 ≈ 3375
        let end = sim.final[0][0]!
        #expect((500...800).contains(end.x) && end.y == 2000, "\(end)")
        #expect(sim.events.isEmpty)
        #expect((20...26).contains(sim.frames.count), "프레임 \(sim.frames.count)")
        #expect(sim.frames.first?.stones == s.stones && sim.frames.last?.stones == sim.final)
    }

    @Test("정면 충돌: 맞은 돌이 밀리고 친 돌이 거의 멈춘다")
    func 충돌() {
        let s = Alkkagi.standardStart()
        let sim = Alkkagi.simulate(s, .init(stone: 2, dx: 0, dy: 1000, power: 450))   // 접촉 시 속도 ≈ 3000
        let black = sim.final[0][2]!, white = sim.final[1][2]!
        #expect(black == P(x: 6000, y: 9210), "흑 \(black)")
        #expect(white == P(x: 6000, y: 10345), "백 \(white)")
        #expect(sim.events == [.init(step: 105, kind: .collision(a: .init(seat: 0, stone: 2), b: .init(seat: 1, stone: 2)))],
                "\(sim.events)")
    }

    /// 딱 붙은 두 돌을 정면으로 쳐 반발 9/10이 법선 속도를 바꾸는 것을 본다.
    /// 속도 3000으로 친 흑은 첫 스텝에 마찰로 2900이 되어 닿고, 백은 (2900 + 0) / 2 + 9 * 2900 / 20 = 2755를,
    /// 흑은 145를 가진다. 백은 2755 / 100 ≈ 28스텝 동안 2755² / (2 * 100 * 120) ≈ 316만큼 굴러 2813에서 3129쯤에 서고,
    /// 스텝마다 버리는 소수 때문에 실제로는 29스텝에 3126이다.
    @Test("정면으로 치면 맞은 돌이 반발만큼 받고 친 돌은 거의 선다")
    func 충돌_속도() {
        let empty: [Alkkagi.Point?] = [nil, nil, nil, nil, nil]
        var stones: [[Alkkagi.Point?]] = [empty, empty]
        stones[0][0] = P(x: 6000, y: 2000)
        stones[1][0] = P(x: 6000, y: 2800)
        let s = Alkkagi.State(stones: stones, nextSeat: 0, outcome: nil)
        let sim = Alkkagi.simulate(s, .init(stone: 0, dx: 0, dy: 1000, power: 100))
        let black = sim.final[0][0]!, white = sim.final[1][0]!
        #expect(sim.events == [.init(step: 1, kind: .collision(a: .init(seat: 0, stone: 0), b: .init(seat: 1, stone: 0)))],
                "\(sim.events)")
        #expect(white.y > 2800 && abs(white.y - 3126) <= 30, "백 \(white)")
        #expect(abs(black.y - 2000) < 60 && black.x == 6000, "흑 \(black)")
    }

    @Test("규칙에 맞지 않는 수는 아무것도 움직이지 않는다")
    func 무효_수_시뮬레이션() {
        let s = Alkkagi.standardStart()
        let sim = Alkkagi.simulate(s, .init(stone: 0, dx: 0, dy: 0, power: 5))
        #expect(sim.steps == 0 && sim.final == s.stones && sim.events.isEmpty)
        #expect(sim.frames == [.init(stones: s.stones)])
        #expect(Alkkagi.simulate(s, .init(stone: 9, dx: 0, dy: 1000, power: 5)).final == s.stones)
        // 배치가 덜 끝난 판에서는 튕김이 아무것도 움직이지 않는다
        let 배치중 = Alkkagi.initial()
        #expect(Alkkagi.simulate(배치중, .init(stone: 0, dx: 0, dy: 1000, power: 500)).steps == 0)
    }

    @Test("세게 치면 상대 돌이 떨어지고 지워진다")
    func 낙하() {
        var s = Alkkagi.standardStart()
        let f = Alkkagi.Flick(stone: 0, dx: 0, dy: 1000, power: 1000)
        let sim = Alkkagi.simulate(s, f)
        #expect(sim.final[1][0] == nil)
        #expect(sim.events.contains { $0.kind == .dropped(.init(seat: 1, stone: 0)) })
        #expect(sim.steps <= Alkkagi.maxSteps && sim.frames.count <= Alkkagi.maxSteps / Alkkagi.frameEvery + 2)
        s = Alkkagi.apply(.flick(f), to: s)
        #expect(s.stones[1][0] == nil && s.remaining(seat: 1) == 4 && s.remaining(seat: 0) == 5)
        #expect(Alkkagi.currentSeat(s) == 1 && s.lastSimulation == sim)
    }

    @Test("내 돌만 나가면 내 돌만 준다")
    func 자멸() {
        let s = Alkkagi.State(stones: [[P(x: 6000, y: 12000), nil, nil, nil, nil], [P(x: 1000, y: 1000), nil, nil, nil, nil]],
                              nextSeat: 0, outcome: nil)
        let next = Alkkagi.apply(.flick(.init(stone: 0, dx: 0, dy: 1000, power: 1000)), to: s)
        #expect(next.stones[0][0] == nil && next.stones[1][0] != nil)
        #expect(Alkkagi.outcome(next) == .win(seat: 1))
    }

    @Test("승패 규칙: 상대 0이면 승리, 둘 다 0이면 무승부, 아니면 차례 이동")
    func 판정() {
        let one: [Alkkagi.Point?] = [P(x: 1, y: 1), nil, nil, nil, nil]
        let none: [Alkkagi.Point?] = [nil, nil, nil, nil, nil]
        let a = Alkkagi.resolve(stones: [one, none], seat: 0)
        #expect(a.outcome == .win(seat: 0) && a.nextSeat == nil)
        let b = Alkkagi.resolve(stones: [none, none], seat: 0)
        #expect(b.outcome == .draw && b.nextSeat == nil)
        let c = Alkkagi.resolve(stones: [none, one], seat: 0)
        #expect(c.outcome == .win(seat: 1))
        let d = Alkkagi.resolve(stones: [one, one], seat: 0)
        #expect(d.outcome == nil && d.nextSeat == 1)
    }

    @Test("배치 두 수와 아홉 수로 완주하면 좌석 0이 이긴다")
    func 완주() {
        var s = Alkkagi.initial()
        for (i, m) in Self.winningMoves().enumerated() {
            #expect(Alkkagi.canApply(m, to: s), "\(i)번째 \(m)")
            s = Alkkagi.apply(m, to: s)
        }
        #expect(Alkkagi.outcome(s) == .win(seat: 0), "남은 백 돌 \(s.remaining(seat: 1)), 흑 \(s.stones[0])")
    }

    @Test("남의 돌·빈 돌·범위 밖·힘 0은 거부한다")
    func 검증() {
        var s = Alkkagi.standardStart()
        #expect(!Alkkagi.canApply(.flick(.init(stone: 5, dx: 0, dy: 1000, power: 500)), to: s))
        #expect(!Alkkagi.canApply(.flick(.init(stone: 0, dx: 0, dy: 0, power: 500)), to: s))
        #expect(!Alkkagi.canApply(.flick(.init(stone: 0, dx: 1001, dy: 0, power: 500)), to: s))
        #expect(!Alkkagi.canApply(.flick(.init(stone: 0, dx: 0, dy: 1000, power: 0)), to: s))
        #expect(Alkkagi.canApply(.flick(.init(stone: 0, dx: 0, dy: 1000, power: 1)), to: s))
        // 튕기기 시작한 판에는 배치를 다시 둘 수 없다
        #expect(!Alkkagi.canApply(.setup(Alkkagi.defaultPlacement(seat: 0)), to: s))
        s.stones[0][0] = nil
        #expect(!Alkkagi.canApply(.flick(.init(stone: 0, dx: 0, dy: 1000, power: 500)), to: s))
    }

    @Test("상태를 저장하면 재생은 빠지고 나머지는 그대로 돌아온다")
    func 상태왕복() throws {
        var s = Alkkagi.standardStart()
        s = Alkkagi.apply(.flick(.init(stone: 0, dx: 0, dy: 1000, power: 1000)), to: s)
        #expect(s.lastSimulation != nil)
        let back = try JSONDecoder().decode(Alkkagi.State.self, from: JSONEncoder().encode(s))
        #expect(back.stones == s.stones && back.nextSeat == s.nextSeat && back.outcome == s.outcome)
        #expect(back.placed == s.placed && back.phase == s.phase)
        #expect(back.lastSimulation == nil)
    }

    @Test("로그가 왕복하고 상태는 수에서 다시 만들어진다")
    func 왕복() throws {
        var log = MoveLog<Alkkagi>()
        for m in Self.winningMoves().prefix(3) { let ok = log.append(m); #expect(ok) }
        let data = try log.encoded()
        let back = try MoveLog<Alkkagi>.decoded(from: data)
        #expect(back == log && back.state.stones == log.state.stones && back.state.lastSimulation != nil)
    }
}
