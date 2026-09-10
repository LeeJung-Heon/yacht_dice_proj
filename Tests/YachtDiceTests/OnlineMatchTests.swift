import Testing
import Foundation
import GameCore
@testable import YachtDice

@Suite("OnlineMatch - 오목")
@MainActor
struct OnlineMatchTests {
    private func makePair() -> (OnlineMatch<Omok>, OnlineMatch<Omok>, InMemoryTurnTransport, InMemoryTurnTransport) {
        let (ta, tb) = InMemoryTurnTransport.pair()
        let seatsA: [Participant] = [.human(name: "A"), .remote(playerID: "b", name: "B")]
        let seatsB: [Participant] = [.remote(playerID: "a", name: "A"), .human(name: "B")]
        let a = OnlineMatch(game: Omok.self, mode: .online(matchID: "m"), participants: seatsA, log: MoveLog<Omok>(), transport: ta)
        let b = OnlineMatch(game: Omok.self, mode: .online(matchID: "m"), participants: seatsB, log: MoveLog<Omok>(), transport: tb)
        a.startListening(); b.startListening()
        return (a, b, ta, tb)
    }

    @Test("내 수가 상대에게 재생되고 차례가 넘어간다")
    func 한_수_전파() async throws {
        let (a, b, ta, _) = makePair()
        var replayed: [Omok.Move] = []
        b.onRemoteMove = { move, _ in replayed.append(move) }
        #expect(a.isLocalTurn && !b.isLocalTurn)
        let played = await a.play(Omok.Move(x: 7, y: 7))
        #expect(played)
        await b.waitForIncoming()
        #expect(replayed == [Omok.Move(x: 7, y: 7)])
        #expect(b.state.stone(x: 7, y: 7) == 1 && b.isLocalTurn && !a.isLocalTurn)
        #expect(ta.lastPayload?.turnSeat == 1 && ta.lastPayload?.eventCount == 1)
        #expect(b.lastRemoteMove?.seat == 0)
    }

    @Test("내 차례가 아니거나 규칙에 어긋나면 두지 않는다")
    func 거부() async {
        let (a, b, ta, _) = makePair()
        let bPlayed = await b.play(Omok.Move(x: 0, y: 0))
        #expect(bPlayed == false)
        let aPlayed = await a.play(Omok.Move(x: 99, y: 0))
        #expect(aPlayed == false)
        #expect(ta.sent.isEmpty)
    }

    @Test("5목이면 끝나고 승자가 실린다")
    func 완주() async throws {
        let (a, b, ta, _) = makePair()
        let moves: [(OnlineMatch<Omok>, Int, Int)] = [(a,0,0),(b,0,1),(a,1,0),(b,1,1),(a,2,0),(b,2,1),(a,3,0),(b,3,1),(a,4,0)]
        for (m, x, y) in moves {
            let played = await m.play(Omok.Move(x: x, y: y))
            #expect(played, "\(x),\(y)")
            await (m === a ? b : a).waitForIncoming()
        }
        #expect(a.outcome == .win(seat: 0) && b.outcome == .win(seat: 0))
        #expect(ta.lastPayload?.finished == true && ta.lastPayload?.winnerSeat == 0 && ta.lastPayload?.turnSeat == nil)
        #expect(!a.isLocalTurn && !b.isLocalTurn)
    }

    @Test("조작된 로그는 거부하고 이유를 남긴다")
    func 조작_거부() async throws {
        let (a, b, ta, _) = makePair()
        _ = await a.play(Omok.Move(x: 7, y: 7))
        await b.waitForIncoming()
        // B의 전송 대신 A가 자기 차례가 아닌 수를 로그에 끼워 넣는다
        var forged = a.log
        _ = forged.append(Omok.Move(x: 8, y: 8))   // 백 차례라 규칙상은 유효하지만 좌석이 다르다: 두 수 연속
        _ = forged.append(Omok.Move(x: 9, y: 9))
        try await ta.publish(TurnPayload(log: try forged.encoded(), eventCount: forged.moves.count, hints: [], turnSeat: 1, winnerSeat: nil, finished: false))
        await b.waitForIncoming()
        // 8,8은 백(좌석 1 = B) 수로 해석되지만 B는 두지 않았으므로 B 화면에서는 상대가 내 차례에 둔 것 — 거부한다
        #expect(b.lastTransportError != nil && b.log.moves.count == 1)
    }

    @Test("배치 일부만 받아들여도 그때까지 둔 수는 저장한다")
    func 조작_부분_거부() async throws {
        let (_, b, ta, _) = makePair()
        var saved: Data?
        b.onLogChanged = { saved = $0 }
        // 좌석0(상대)의 정당한 첫 수 뒤에, 다음은 B(좌석1) 차례인데 상대가 대신 둔 것처럼 조작한 수를 잇는다.
        // 두 수 연속을 같은 배치로 보내면 첫 수는 받아들이고 둘째 수에서 거부해야 한다.
        var forged = MoveLog<Omok>()
        _ = forged.append(Omok.Move(x: 7, y: 7))
        _ = forged.append(Omok.Move(x: 8, y: 8))
        try await ta.publish(TurnPayload(log: try forged.encoded(), eventCount: forged.moves.count, hints: [], turnSeat: 1, winnerSeat: nil, finished: false))
        await b.waitForIncoming()
        #expect(b.log.moves.count == 1 && b.lastTransportError != nil)
        let savedData = try #require(saved, "받아들인 수까지는 저장해야 한다")
        let savedLog = try MoveLog<Omok>.decoded(from: savedData)
        #expect(savedLog.moves.count == 1)
    }

    @Test("로컬 2인은 전송 없이 같은 객체에서 좌석이 번갈아 바뀐다")
    func 로컬_2인() async {
        let m = OnlineMatch(game: Omok.self, mode: .passAndPlay(names: ["갑", "을"]),
                            participants: [.human(name: "갑"), .human(name: "을")], log: MoveLog<Omok>(), transport: nil)
        #expect(m.localSeat == 0 && m.isLocalTurn)
        let firstPlayed = await m.play(Omok.Move(x: 7, y: 7))
        #expect(firstPlayed)
        #expect(m.localSeat == 1 && m.isLocalTurn)
        var saved: Data?
        m.onLogChanged = { saved = $0 }
        let secondPlayed = await m.play(Omok.Move(x: 8, y: 8))
        #expect(secondPlayed)
        #expect(saved != nil && m.localSeat == 0)
    }
}
