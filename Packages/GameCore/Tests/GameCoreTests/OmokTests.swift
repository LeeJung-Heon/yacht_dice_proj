import Testing
@testable import GameCore

@Suite("오목 규칙")
struct OmokTests {
    private func play(_ moves: [(Int, Int)]) -> Omok.State {
        var state = Omok.initial()
        for (x, y) in moves {
            let move = Omok.Move(x: x, y: y)
            precondition(Omok.canApply(move, to: state), "적용 불가 \(move)")
            state = Omok.apply(move, to: state)
        }
        return state
    }

    @Test("빈 판은 흑(좌석 0) 차례이고 끝나지 않았다")
    func 초기() {
        let s = Omok.initial()
        #expect(s.cells.count == 225 && s.cells.allSatisfy { $0 == 0 })
        #expect(Omok.currentSeat(s) == 0 && Omok.outcome(s) == nil)
    }

    @Test("가로 5목이면 흑이 이긴다")
    func 가로() {
        // 흑 (0..4, 0), 백 (0..3, 1)
        let s = play([(0,0),(0,1),(1,0),(1,1),(2,0),(2,1),(3,0),(3,1),(4,0)])
        #expect(Omok.outcome(s) == .win(seat: 0))
        #expect(Omok.currentSeat(s) == nil)
    }

    @Test("세로·대각선 5목과 6목도 승리다")
    func 방향들() {
        let 세로 = play([(7,0),(0,0),(7,1),(0,1),(7,2),(0,2),(7,3),(0,3),(7,4)])
        #expect(Omok.outcome(세로) == .win(seat: 0))
        let 대각 = play([(0,0),(1,0),(1,1),(2,0),(2,2),(3,0),(3,3),(4,0),(4,4)])
        #expect(Omok.outcome(대각) == .win(seat: 0))
        let 역대각 = play([(4,0),(0,0),(3,1),(0,1),(2,2),(0,2),(1,3),(0,3),(0,4)])
        #expect(Omok.outcome(역대각) == .win(seat: 0))
        // 백이 6목: 흑은 14행에 흩어 둔다
        let 육목 = play([(0,14),(0,0),(2,14),(1,0),(4,14),(2,0),(6,14),(3,0),(8,14),(5,0),(10,14),(4,0)])
        #expect(Omok.outcome(육목) == .win(seat: 1))
    }

    @Test("찬 칸·범위 밖·끝난 판에는 둘 수 없다")
    func 검증() {
        var s = Omok.initial()
        #expect(!Omok.canApply(Omok.Move(x: 15, y: 0), to: s))
        #expect(!Omok.canApply(Omok.Move(x: -1, y: 3), to: s))
        s = Omok.apply(Omok.Move(x: 7, y: 7), to: s)
        #expect(!Omok.canApply(Omok.Move(x: 7, y: 7), to: s))
        #expect(Omok.currentSeat(s) == 1)
        let done = play([(0,0),(0,1),(1,0),(1,1),(2,0),(2,1),(3,0),(3,1),(4,0)])
        #expect(!Omok.canApply(Omok.Move(x: 9, y: 9), to: done))
    }

    @Test("225수가 차면 무승부다")
    func 무승부() {
        // 5목이 생기지 않는 배열: 행마다 2칸씩 색을 바꿔 채운다(흑흑백백…), 행이 바뀔 때 한 칸 밀어 세로·대각도 끊는다
        var s = Omok.initial()
        var seat = 0
        var placed = 0
        // 같은 색이 가로 최대 2, 세로·대각 최대 2가 되도록 색 지도를 만들고, 차례에 맞는 색이 남아 있는 칸을 고른다
        func color(_ x: Int, _ y: Int) -> Int { (((x + 2 * y) / 2) % 2) }
        var free = (0..<225).map { ($0 % 15, $0 / 15) }
        while !free.isEmpty {
            guard let i = free.firstIndex(where: { color($0.0, $0.1) == seat }) ?? free.indices.first else { break }
            let (x, y) = free.remove(at: i)
            let move = Omok.Move(x: x, y: y)
            #expect(Omok.canApply(move, to: s), "\(placed)번째 수 \(move)를 둘 수 없다")
            s = Omok.apply(move, to: s)
            placed += 1
            if Omok.outcome(s) != nil { break }
            seat = 1 - seat
        }
        #expect(placed == 225 && Omok.outcome(s) == .draw, "놓은 수 \(placed), 결과 \(String(describing: Omok.outcome(s)))")
    }
}
