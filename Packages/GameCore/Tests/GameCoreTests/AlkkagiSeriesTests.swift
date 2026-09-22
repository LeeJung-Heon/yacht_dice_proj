import Foundation
import Testing
@testable import GameCore

@Suite("알까기 3판 2선승")
struct AlkkagiSeriesTests {
    typealias P = Alkkagi.Point

    @Test("확장된 우측과 위쪽 교차점에 돌을 배치할 수 있다")
    func enlargedPlayableArea() {
        let black = [P(x: 12000, y: 7000), P(x: 13000, y: 7000), P(x: 14000, y: 7000), P(x: 15000, y: 7000), P(x: 16000, y: 7000)]
        let white = black.map { P(x: $0.x, y: 16000) }
        var state = Alkkagi.initial()
        #expect(Alkkagi.canApply(.setup(black), to: state))
        state = Alkkagi.apply(.setup(black), to: state)
        #expect(Alkkagi.canApply(.setup(white), to: state))
        state = Alkkagi.apply(.setup(white), to: state)
        #expect(state.stones[1][4] == P(x: 16000, y: 16000))
    }

    @Test("첫 라운드의 마지막 돌을 떨어뜨려도 전체 경기는 끝나지 않는다")
    func firstRoundDoesNotFinishMatch() {
        let state = Alkkagi.State(stones: [[P(x: 8000, y: 16000), nil, nil, nil, nil],
                                          [P(x: 8000, y: 4000), nil, nil, nil, nil]], nextSeat: 0, outcome: nil)
        let next = Alkkagi.apply(.flick(.init(stone: 0, dx: 0, dy: 1000, power: 1000)), to: state)
        #expect(next.remaining(seat: 0) == 0)
        #expect(Alkkagi.outcome(next) == nil)
        #expect(Alkkagi.currentSeat(next) == 1)
        #expect(!Alkkagi.canApply(.flick(.init(stone: 0, dx: 1000, dy: 0, power: 1)), to: next))
    }

    @Test("라운드 사이 점수는 유지하고 새 맵에서 선공과 배치를 바꾼다")
    func roundTransition() {
        var state = lossForBlack(round: 1, wins: [0, 0])
        #expect(state.roundWins == [0, 1] && state.roundOutcome == .win(seat: 1))
        #expect(Alkkagi.canApply(.nextRound, to: state))
        state = Alkkagi.apply(.nextRound, to: state)
        #expect(state.roundNumber == 2 && state.map == .cutCorners && state.roundWins == [0, 1])
        #expect(state.phase == .setup && state.nextSeat == 1 && state.lastSimulation == nil)
        #expect(state.stones.flatMap { $0 }.allSatisfy { $0 == nil })
        state = Alkkagi.apply(.setup(Alkkagi.defaultPlacement(seat: 1)), to: state)
        #expect(state.nextSeat == 0 && state.phase == .setup)
        state = Alkkagi.apply(.setup(Alkkagi.defaultPlacement(seat: 0)), to: state)
        #expect(state.nextSeat == 1 && state.phase == .play)
        #expect(!Alkkagi.canApply(.nextRound, to: state))
        let tied = lossForBlack(round: 2, wins: [1, 0])
        let decider = Alkkagi.apply(.nextRound, to: tied)
        #expect(decider.roundNumber == 3 && decider.map == .centerBumper && decider.nextSeat == 0)
        #expect(decider.roundWins == [1, 1])
    }

    @Test("2승째부터만 경기가 끝나며 세 번째 라운드를 열 수 없다")
    func secondWinEndsMatch() {
        let state = lossForBlack(round: 2, wins: [0, 1])
        #expect(state.roundWins == [0, 2] && state.outcome == .win(seat: 1) && state.nextSeat == nil)
        #expect(!Alkkagi.canApply(.nextRound, to: state))
        let decider = lossForBlack(round: 3, wins: [1, 1])
        #expect(decider.roundWins == [1, 2] && decider.outcome == .win(seat: 1))
    }

    @Test("동시 낙하는 점수를 올리지 않고 같은 맵에서 다시 배치한다")
    func drawRepeatsRound() {
        let empty: [P?] = [nil, nil, nil, nil, nil]
        let state = Alkkagi.State(stones: [[P(x: 8000, y: 16000), nil, nil, nil, nil], empty],
                                  nextSeat: 0, outcome: nil, roundNumber: 2, roundWins: [1, 0])
        let drawn = Alkkagi.apply(.flick(.init(stone: 0, dx: 0, dy: 1000, power: 1000)), to: state)
        #expect(drawn.roundOutcome == .draw && drawn.outcome == nil && drawn.roundWins == [1, 0])
        let next = Alkkagi.apply(.nextRound, to: drawn)
        #expect(next.roundNumber == 2 && next.map == .cutCorners && next.nextSeat == 1 && next.roundWins == [1, 0])
    }

    @Test("잘린 모서리는 배치할 수 없고 이동해서 들어가면 낙하한다")
    func cutCornersArePhysical() {
        let cornerPlacement = [P(x: 0, y: 0)] + Alkkagi.defaultPlacement(seat: 0).dropFirst()
        #expect(Alkkagi.placementIsValid(cornerPlacement, seat: 0, map: .classic))
        #expect(!Alkkagi.placementIsValid(cornerPlacement, seat: 0, map: .cutCorners))
        let stones: [[P?]] = [[P(x: 3000, y: 0), nil, nil, nil, nil], [P(x: 8000, y: 13000), nil, nil, nil, nil]]
        let flick = Alkkagi.Flick(stone: 0, dx: -1000, dy: 0, power: 200)
        let classic = Alkkagi.simulate(.init(stones: stones, nextSeat: 0, outcome: nil), flick)
        let corners = Alkkagi.simulate(.init(stones: stones, nextSeat: 0, outcome: nil, roundNumber: 2), flick)
        #expect(classic.final[0][0] != nil)
        #expect(corners.final[0][0] == nil)
        #expect(corners.events.contains { $0.kind == .dropped(.init(seat: 0, stone: 0)) })
    }

    @Test("중앙 범퍼는 돌을 반사하고 범퍼와 겹치는 배치는 거부한다")
    func centerBumperBounces() {
        let nearBumper = [P(x: 8000, y: 7000)] + Alkkagi.defaultPlacement(seat: 0).dropFirst()
        #expect(Alkkagi.placementIsValid(nearBumper, seat: 0, map: .classic))
        #expect(!Alkkagi.placementIsValid(nearBumper, seat: 0, map: .centerBumper))
        let state = Alkkagi.State(stones: [[P(x: 8000, y: 5000), nil, nil, nil, nil],
                                          [P(x: 14000, y: 13000), nil, nil, nil, nil]], nextSeat: 0, outcome: nil,
                                  roundNumber: 3, roundWins: [1, 1])
        let flick = Alkkagi.Flick(stone: 0, dx: 0, dy: 1000, power: 300)
        let sim = Alkkagi.simulate(state, flick)
        #expect(sim.final[0][0].map { $0.y < 5000 } == true)
        #expect(sim.events.contains { $0.kind == .bumper(.init(seat: 0, stone: 0)) })
        #expect(sim == Alkkagi.simulate(state, flick))
        for seat in 0..<2 { #expect(Alkkagi.placementIsValid(Alkkagi.defaultPlacement(seat: seat), seat: seat, map: .centerBumper)) }
    }

    @Test("라운드 정보가 상태에 저장되고 구형 상태에는 첫 라운드 기본값을 쓴다")
    func roundStateSerialization() throws {
        let state = lossForBlack(round: 2, wins: [1, 0])
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(Alkkagi.State.self, from: encoded)
        #expect(decoded.roundNumber == 2 && decoded.roundWins == [1, 1] && decoded.roundOutcome == .win(seat: 1))
        #expect(decoded.lastSimulation == nil && Alkkagi.canApply(.nextRound, to: decoded))
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["roundNumber", "roundWins", "roundOutcome"] { legacy.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(Alkkagi.State.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.roundNumber == 1 && old.roundWins == [0, 0] && old.roundOutcome == nil)
    }

    @Test("두 라운드의 수 로그를 다시 읽으면 점수와 최종 승자가 같다")
    func completeSeriesLog() throws {
        var log = MoveLog<Alkkagi>()
        func append(_ move: Alkkagi.Move) { let accepted = log.append(move); #expect(accepted) }
        for round in 1...2 {
            if round == 2 { append(.nextRound) }
            let first = round == 1 ? 0 : 1
            append(.setup(Alkkagi.defaultPlacement(seat: first)))
            append(.setup(Alkkagi.defaultPlacement(seat: 1 - first)))
            if round == 2 { append(.flick(.init(stone: 0, dx: 1000, dy: 0, power: 1))) }
            for stone in 0..<5 {
                append(.flick(.init(stone: stone, dx: 0, dy: 1000, power: 1000)))
                if stone < 4 { append(.flick(.init(stone: stone + 1, dx: 1000, dy: 0, power: 1))) }
            }
            #expect(log.state.roundWins == [round, 0])
            #expect(log.isFinished == (round == 2))
        }
        let replayed = try MoveLog<Alkkagi>.decoded(from: log.encoded())
        #expect(replayed == log && replayed.state.outcome == .win(seat: 0))
        #expect(!replayed.state.stones[0].allSatisfy { $0 == nil })
    }

    private func lossForBlack(round: Int, wins: [Int]) -> Alkkagi.State {
        let state = Alkkagi.State(stones: [[P(x: 8000, y: 16000), nil, nil, nil, nil],
                                          [P(x: 3000, y: 4000), nil, nil, nil, nil]], nextSeat: 0, outcome: nil,
                                  roundNumber: round, roundWins: wins)
        return Alkkagi.apply(.flick(.init(stone: 0, dx: 0, dy: 1000, power: 1000)), to: state)
    }
}
