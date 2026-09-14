import Testing
import GameCore
@testable import YachtDice

@Suite("알까기 재생 보간")
struct AlkkagiInterpolationTests {
    /// 흑 돌 0을 정면으로 튕겨 백 돌 0을 맞히고 판 밖으로 밀어내는 한 수. 날아가는 중에 사라지는 돌이 있다.
    private var 한판: Alkkagi.Simulation {
        Alkkagi.simulate(Alkkagi.standardStart(), Alkkagi.Flick(stone: 0, dx: 0, dy: 1000, power: 1000))
    }

    @Test("흐르기 전에는 첫 프레임 그대로다")
    @MainActor
    func 시작은_첫_프레임() {
        let sim = 한판
        #expect(AlkkagiScreen.interpolated(sim, elapsedSteps: 0) == sim.frames[0].stones)
        #expect(AlkkagiScreen.interpolated(sim, elapsedSteps: -5) == sim.frames[0].stones, "음수는 시작에 묶인다")
    }

    @Test("프레임 한가운데에서는 두 프레임의 중점에 선다")
    @MainActor
    func 한가운데는_중점() throws {
        let sim = 한판
        let from = try #require(sim.frames[0].stones[0][0])
        let to = try #require(sim.frames[1].stones[0][0])
        #expect(from != to, "첫 두 프레임 사이에 돌이 움직여야 중점을 볼 수 있다")
        let mid = try #require(AlkkagiScreen.interpolated(sim, elapsedSteps: 2)[0][0])
        #expect(abs(mid.x - (from.x + to.x) / 2) <= 1, "x가 중점에서 벗어났다: \(mid.x)")
        #expect(abs(mid.y - (from.y + to.y) / 2) <= 1, "y가 중점에서 벗어났다: \(mid.y)")
    }

    @Test("한 프레임 안에서도 스텝마다 자리가 다르다")
    @MainActor
    func 프레임_안에서도_움직인다() throws {
        let sim = 한판
        var seen: [Alkkagi.Point] = []
        for step in stride(from: 0.0, through: 4.0, by: 1.0) {
            seen.append(try #require(AlkkagiScreen.interpolated(sim, elapsedSteps: step)[0][0]))
        }
        // 프레임 경계 넷 사이의 세 지점이 저마다 달라야 30fps보다 촘촘한 화면이 그릴 것이 생긴다.
        #expect(Set(seen.map(\.y)).count == seen.count, "같은 자리를 되풀이해 그린다: \(seen.map(\.y))")
    }

    @Test("흐름이 다하면 끝 배치에 딱 앉는다")
    @MainActor
    func 끝은_마지막_배치() {
        let sim = 한판
        #expect(AlkkagiScreen.interpolated(sim, elapsedSteps: Double(sim.steps)) == sim.final)
        #expect(AlkkagiScreen.interpolated(sim, elapsedSteps: Double(sim.steps) + 100) == sim.final, "넘겨도 끝 배치다")
    }

    @Test("다음 프레임에서 사라질 돌은 그 칸이 끝날 때까지 제자리다")
    @MainActor
    func 떨어질_돌은_칸_끝까지() throws {
        let sim = 한판
        // 앞 프레임에는 있고 다음 프레임에는 없는 첫 자리를 찾는다 — 날아가는 중에 떨어진 돌이다.
        var found: (seat: Int, stone: Int, frame: Int)?
        찾기: for k in 0..<(sim.frames.count - 1) {
            for seat in 0..<Alkkagi.seatCount {
                for stone in 0..<Alkkagi.stonesPerSeat {
                    guard sim.frames[k].stones[seat][stone] != nil, sim.frames[k + 1].stones[seat][stone] == nil else { continue }
                    found = (seat, stone, k)
                    break 찾기
                }
            }
        }
        let 떨어진 = try #require(found, "날아가는 중에 떨어지는 돌이 있어야 한다")
        #expect(떨어진.frame + 1 < sim.frames.count - 1, "마지막 칸이 아니라야 칸 전체를 볼 수 있다")
        let 자리 = try #require(sim.frames[떨어진.frame].stones[떨어진.seat][떨어진.stone])
        let 칸머리 = Double(떨어진.frame * Alkkagi.frameEvery)
        for step in stride(from: 칸머리, to: 칸머리 + Double(Alkkagi.frameEvery), by: 0.5) {
            let stones = AlkkagiScreen.interpolated(sim, elapsedSteps: step)
            #expect(stones[떨어진.seat][떨어진.stone] == 자리, "\(step)스텝에서 떨어질 돌이 제자리를 떠났다")
        }
        let 다음칸 = AlkkagiScreen.interpolated(sim, elapsedSteps: 칸머리 + Double(Alkkagi.frameEvery))
        #expect(다음칸[떨어진.seat][떨어진.stone] == nil, "다음 칸으로 넘어가면 사라진다")
    }
}
