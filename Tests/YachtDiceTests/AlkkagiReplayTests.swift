import Testing
import GameCore
@testable import YachtDice

@Suite("알까기 재생")
struct AlkkagiReplayTests {
    /// 흑 돌 0을 정면으로 튕겨 백 돌 0을 맞히고 판 밖으로 밀어내는, 충돌과 낙하가 다 있는 한 수.
    private func 한판(power: Int = 1000) -> Alkkagi.Simulation {
        Alkkagi.simulate(Alkkagi.standardStart(), Alkkagi.Flick(stone: 0, dx: 0, dy: 1000, power: power))
    }

    /// 프레임을 처음부터 끝까지 돌며 각 사건이 몇 번째 프레임에서 나왔는지 모은다.
    @MainActor
    private func 재생(_ sim: Alkkagi.Simulation) -> [(frame: Int, event: Alkkagi.Event)] {
        var eventIndex = 0
        var played: [(frame: Int, event: Alkkagi.Event)] = []
        for i in sim.frames.indices {
            let due = AlkkagiScreen.eventsToPlay(in: sim, frame: i, from: &eventIndex)
            played.append(contentsOf: due.map { (i, $0) })
        }
        return played
    }

    @Test("프레임을 돌면 사건이 한 번씩 스텝 순서로 나온다")
    @MainActor
    func 사건은_한_번씩_순서대로() {
        let sim = 한판()
        let hasCollision = sim.events.contains { if case .collision = $0.kind { true } else { false } }
        let hasDropped = sim.events.contains { if case .dropped = $0.kind { true } else { false } }
        #expect(hasCollision, "충돌이 있는 수여야 한다")
        #expect(hasDropped, "낙하가 있는 수여야 한다")

        let played = 재생(sim)
        #expect(played.map(\.event) == sim.events, "모든 사건이 빠짐없이 한 번씩, 스텝 순서로 나온다")
        let frames = played.map(\.frame)
        #expect(frames == frames.sorted(), "프레임 번호도 앞에서 뒤로만 간다")
    }

    @Test("사건은 그 스텝을 덮는 첫 프레임에서 나온다")
    @MainActor
    func 사건은_제_프레임에서() {
        let sim = 한판()
        for (frame, event) in 재생(sim) {
            let stepEnd = frame == sim.frames.count - 1 ? sim.steps : frame * Alkkagi.frameEvery
            #expect(event.step <= stepEnd, "\(event.step)스텝 사건이 \(stepEnd)스텝까지인 프레임 \(frame)에 나왔다")
            // 앞 프레임이 이미 그 스텝을 덮었다면 거기서 나왔어야 한다.
            if frame > 0 { #expect((frame - 1) * Alkkagi.frameEvery < event.step, "\(event.step)스텝 사건이 프레임 \(frame)까지 늦었다") }
        }
    }

    /// 사건 스텝이 프레임 경계에 딱 걸리는 판이 섞여 있어야 "그 프레임까지"의 경계가 실제로 시험된다.
    @Test("세기를 달리해도 경계에 걸린 사건까지 제자리에서 나온다")
    @MainActor
    func 경계에_걸린_사건() {
        var 경계에_걸린_판 = 0
        for power in stride(from: 100, through: 1000, by: 50) {
            let sim = 한판(power: power)
            let played = 재생(sim)
            #expect(played.map(\.event) == sim.events, "세기 \(power): 사건이 빠짐없이 한 번씩 나온다")
            for (frame, event) in played where frame > 0 {
                #expect((frame - 1) * Alkkagi.frameEvery < event.step, "세기 \(power): \(event.step)스텝 사건이 프레임 \(frame)까지 늦었다")
            }
            if sim.events.contains(where: { $0.step % Alkkagi.frameEvery == 0 }) { 경계에_걸린_판 += 1 }
        }
        #expect(경계에_걸린_판 > 0, "프레임 경계 스텝에 놓인 사건이 하나도 없어 경계를 시험하지 못했다")
    }
}
