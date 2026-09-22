import Foundation
import Testing
@testable import GameCore

@Suite("컵퐁 실제 비행과 충돌")
struct CupPongPhysicsTests {
    private let noCups = [Bool](repeating: false, count: 10)

    @Test("같은 수는 모든 비행 프레임과 충돌 시점까지 재현한다")
    func deterministicReplay() {
        let shot = CupPong.Shot(dx: 50, power: 350)
        let cups = [Bool](repeating: true, count: 10)
        let a = CupPong.simulate(shot, against: cups)
        let b = CupPong.simulate(shot, against: cups)
        #expect(a == b)
        #expect(a.frames.count > 20)
        #expect(a.frames != CupPong.simulate(.init(dx: 100, power: 350), against: cups).frames)
    }

    @Test("공은 중력으로 정점을 지난 뒤 실제 테이블 높이까지 떨어진다")
    func gravity() throws {
        let simulation = CupPong.simulate(.init(dx: 0, power: 0), against: noCups)
        let first = try #require(simulation.frames.first)
        let apex = try #require(simulation.frames.max(by: { $0.height < $1.height }))
        let impact = try #require(simulation.events.first { $0.kind == .tableBounce })
        #expect(apex.height > first.height + 500)
        #expect(apex.step > first.step && apex.step < impact.step)
        #expect(simulation.frames.contains { $0.step >= impact.step && $0.height <= CupPong.ballRadius + 30 })
    }

    @Test("테이블에 맞은 공은 다시 뜨고 다음 바운드에서 에너지를 잃는다")
    func tableBounceLosesEnergy() throws {
        let simulation = CupPong.simulate(.init(dx: 0, power: 0), against: noCups)
        let bounces = simulation.events.filter { $0.kind == .tableBounce }
        #expect(bounces.count >= 2)
        let first = try #require(bounces.first)
        let second = try #require(bounces.dropFirst().first)
        let incomingApex = try #require(simulation.frames.filter { $0.step < first.step }.map(\.height).max())
        let reboundApex = try #require(simulation.frames.filter { $0.step > first.step && $0.step < second.step }.map(\.height).max())
        #expect(reboundApex > CupPong.ballRadius + 100)
        #expect(reboundApex < incomingApex)
    }

    @Test("바운드 프레임이 실제 접촉 높이를 담아 보간 중 공중에서 튕기지 않는다")
    func recordsExactImpactFrame() throws {
        let simulation = CupPong.simulate(.init(dx: 0, power: 0), against: noCups)
        let impact = try #require(simulation.events.first { $0.kind == .tableBounce })
        let frame = try #require(simulation.frames.first { $0.step == impact.step })
        #expect(frame.height == CupPong.ballRadius)
    }

    @Test("공이 들어갈 여유가 없는 가장자리 타격은 림에 튕긴다")
    func rimDeflects() {
        var cups = noCups
        cups[9] = true
        let simulation = CupPong.simulate(.init(dx: 80, power: 350), against: cups)
        #expect(simulation.events.contains { $0.kind == .rim(cup: 9) })
        #expect(simulation.landing.cup == nil)
    }

    @Test("림 안쪽에 맞은 공은 컵 안으로 굴절되어 득점할 수 있다")
    func innerRimCanSink() throws {
        var cups = noCups
        cups[9] = true
        let simulation = CupPong.simulate(.init(dx: 50, power: 350), against: cups)
        let rim = try #require(simulation.events.first { $0.kind == .rim(cup: 9) })
        let sunk = try #require(simulation.events.first { $0.kind == .sunk(cup: 9) })
        #expect(rim.step < sunk.step)
        #expect(simulation.landing.cup == 9)
    }

    @Test("낮게 날아오는 공은 컵 바깥 벽에서 되돌아온다")
    func cupWallDeflects() throws {
        var cups = noCups
        cups[9] = true
        let simulation = CupPong.simulate(.init(dx: 0, power: 320), against: cups)
        let impact = try #require(simulation.events.first { $0.kind == .cupWall(cup: 9) })
        let before = try #require(simulation.frames.last { $0.step < impact.step })
        let later = try #require(simulation.frames.first { $0.step >= impact.step + 20 })
        #expect(later.y < before.y)
        #expect(simulation.landing.cup == nil)
    }

    @Test("입구 가장자리로 들어온 공은 안쪽 벽을 통과하지 않고 컵 안에 남는다")
    func innerWallContainsGlancingEntry() {
        var cups = noCups
        cups[9] = true
        let simulation = CupPong.simulate(.init(dx: 40, power: 365), against: cups)
        #expect(simulation.events.contains { $0.kind == .cupWall(cup: 9) })
        #expect(simulation.landing.cup == 9)
    }

    @Test("비운 컵은 림과 벽의 충돌에서도 사라진다")
    func removedCupHasNoCollider() {
        let simulation = CupPong.simulate(.init(dx: 80, power: 350), against: noCups)
        #expect(!simulation.events.contains { $0.kind == .rim(cup: 9) || $0.kind == .cupWall(cup: 9) })
        #expect(simulation.landing.cup == nil)
    }

    @Test("저장한 상태는 재생 프레임 없이도 규칙 상태를 보존한다")
    func stateRoundTrip() throws {
        let state = CupPong.apply(.init(dx: 0, power: 350), to: CupPong.initial())
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CupPong.State.self, from: data)
        #expect(decoded == state)
        #expect(decoded.lastSimulation == nil)
        #expect(decoded.lastShot?.cup == 9)
    }

    @Test("테이블 밖으로 빗나간 공은 떨어지고 유한한 시간에 종료한다")
    func missFallsOffTable() throws {
        let simulation = CupPong.simulate(.init(dx: 1000, power: 1000), against: noCups)
        #expect(simulation.landing.cup == nil)
        #expect(simulation.events.contains { $0.kind == .leftTable })
        #expect(try #require(simulation.frames.last).height < 0)
        #expect(simulation.steps <= CupPong.stepsPerSecond * 5)
    }

    @Test("컵에 들어간 뒤에는 컵 안으로 내려가며 판정과 재생이 일치한다")
    func sinkInsideCup() throws {
        let simulation = CupPong.simulate(.init(dx: 0, power: 350), against: [Bool](repeating: true, count: 10))
        #expect(simulation.landing.cup == 9)
        let sunk = try #require(simulation.events.first { $0.kind == .sunk(cup: 9) })
        let last = try #require(simulation.frames.last)
        #expect(last.step > sunk.step)
        #expect(last.height < CupPong.cupHeight - CupPong.ballRadius)
        let state = CupPong.apply(.init(dx: 0, power: 350), to: CupPong.initial())
        #expect(state.lastSimulation == simulation)
        #expect(state.lastShot == simulation.landing && state.cups[1][9] == false)
    }

    @Test("컵 안의 가벼운 공은 수면 아래로 가라앉지 않고 일부가 잠긴 채 뜬다")
    func settledBallFloatsAtLiquidSurface() throws {
        let simulation = CupPong.simulate(.init(dx: 0, power: 350), against: [Bool](repeating: true, count: 10))
        let last = try #require(simulation.frames.last)
        // 화면의 액체 높이 75에서 공 중심은 위에, 공 바닥은 아래에 놓인다.
        #expect(last.height > 75)
        #expect(last.height - CupPong.ballRadius < 75)
    }
}
