import Testing
@testable import GameCore

@Suite("컵퐁 규칙")
struct CupPongTests {
    /// 좌석 0이 상대(좌석 1)의 컵 열 개를 인덱스 순으로 맞히는 힘. 각 행의 착지 y는 2825·2606·2400·2206이다.
    static let winningShots: [CupPong.Shot] = [
        .init(dx: -207, power: 500), .init(dx: -69, power: 500), .init(dx: 69, power: 500), .init(dx: 207, power: 500),
        .init(dx: -150, power: 450), .init(dx: 0, power: 450), .init(dx: 150, power: 450),
        .init(dx: -81, power: 400), .init(dx: 81, power: 400),
        .init(dx: 0, power: 350),
    ]

    @Test("처음에는 양쪽 컵이 열 개씩 남아 있고 좌석 0 차례다")
    func 초기() {
        let s = CupPong.initial()
        #expect(s.cups == [Array(repeating: true, count: 10), Array(repeating: true, count: 10)])
        #expect(CupPong.currentSeat(s) == 0 && CupPong.outcome(s) == nil && s.remaining(seat: 1) == 10)
    }

    @Test("착지는 정수 수식이라 같은 힘이면 항상 같다")
    func 결정성() {
        let a = CupPong.landing(of: .init(dx: 123, power: 456), against: Array(repeating: true, count: 10))
        let b = CupPong.landing(of: .init(dx: 123, power: 456), against: Array(repeating: true, count: 10))
        #expect(a == b)
        // L = 1200 + 912 + 519 = 2631, X = 123 * 2631 / 1500 = 215
        #expect(a.x == 215 && a.y == 2631)
    }

    @Test("맨 앞 컵을 맞히면 컵이 비고 차례를 유지한다")
    func 맞힘() {
        var s = CupPong.initial()
        let shot = CupPong.Shot(dx: 0, power: 350)      // L = 1200 + 700 + 306 = 2206 → 컵 9 (0, 2200)
        #expect(CupPong.canApply(shot, to: s))
        s = CupPong.apply(shot, to: s)
        #expect(s.lastShot == CupPong.Landing(x: 0, y: 2206, cup: 9))
        #expect(s.cups[1][9] == false && s.remaining(seat: 1) == 9)
        #expect(CupPong.currentSeat(s) == 0)
    }

    @Test("빗나가면 차례가 넘어간다 — 짧게, 길게, 옆으로")
    func 빗나감() {
        for shot in [CupPong.Shot(dx: 0, power: 0),        // L = 1200, 컵 앞
                     CupPong.Shot(dx: 0, power: 1000),     // L = 5700, 테이블 밖
                     CupPong.Shot(dx: 1000, power: 500)] { // X = 1883, 옆
            let s = CupPong.apply(shot, to: CupPong.initial())
            #expect(s.lastShot?.cup == nil, "\(shot)")
            #expect(s.cups[1].allSatisfy { $0 } && CupPong.currentSeat(s) == 1, "\(shot)")
        }
    }

    @Test("비운 컵은 다시 맞힐 수 없고 그 자리는 빗나감이다")
    func 빈_컵() {
        var s = CupPong.apply(.init(dx: 0, power: 350), to: CupPong.initial())
        s = CupPong.apply(.init(dx: 0, power: 350), to: s)
        #expect(s.lastShot?.cup == nil && CupPong.currentSeat(s) == 1)
    }

    @Test("열 개를 다 맞히면 이긴다")
    func 완주() {
        var s = CupPong.initial()
        for (i, shot) in Self.winningShots.enumerated() {
            #expect(CupPong.canApply(shot, to: s), "\(i)")
            s = CupPong.apply(shot, to: s)
            #expect(s.lastShot?.cup == i, "\(i)번째 힘이 컵 \(i)를 맞혀야 한다: \(String(describing: s.lastShot))")
        }
        #expect(CupPong.outcome(s) == .win(seat: 0) && CupPong.currentSeat(s) == nil)
        #expect(!CupPong.canApply(.init(dx: 0, power: 350), to: s))
    }

    @Test("범위 밖 힘은 거부한다")
    func 범위() {
        let s = CupPong.initial()
        #expect(!CupPong.canApply(.init(dx: 1001, power: 500), to: s))
        #expect(!CupPong.canApply(.init(dx: 0, power: -1), to: s))
        #expect(!CupPong.canApply(.init(dx: 0, power: 1001), to: s))
    }

    @Test("로그가 JSON으로 왕복한다")
    func 왕복() throws {
        var log = MoveLog<CupPong>()
        for shot in Self.winningShots.prefix(3) { let ok = log.append(shot); #expect(ok) }
        let data = try log.encoded()
        #expect(try MoveLog<CupPong>.decoded(from: data) == log)
    }
}
