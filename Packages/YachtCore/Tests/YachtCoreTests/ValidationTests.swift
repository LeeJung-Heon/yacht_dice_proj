import Testing
@testable import YachtCore

@Suite("Intent 검증")
struct ValidationTests {

    private func rolled(_ dice: [Int], playerCount: Int = 1) -> GameState {
        GameState(playerCount: playerCount).applying(.rolled(dice))
    }

    @Test("굴리기 전에는 굴림만 허용된다")
    func 첫_굴림_전() {
        let s = GameState(playerCount: 1)
        #expect(s.allows(.roll))
        #expect(s.validate(.toggleHold(0)) == .failure(.mustRollFirst))
        #expect(s.validate(.commit(.aces)) == .failure(.mustRollFirst))
    }

    @Test("3회를 다 쓰면 더 굴릴 수 없다")
    func 굴림_소진() {
        var s = rolled([1, 2, 3, 4, 5])
        s = s.applying(.rolled([1, 2, 3, 4, 5]))
        s = s.applying(.rolled([1, 2, 3, 4, 5]))
        #expect(s.rollsRemaining == 0)
        #expect(s.validate(.roll) == .failure(.noRollsRemaining))
        #expect(s.allows(.commit(.choice)), "굴림을 다 써도 기록은 할 수 있어야 한다")
    }

    @Test("5개를 전부 keep하면 굴릴 수 없다")
    func 전부_홀드() {
        var s = rolled([1, 2, 3, 4, 5])
        for i in 0..<5 { s = s.applying(.holdToggled(i)) }
        #expect(s.validate(.roll) == .failure(.allDiceHeld))
    }

    @Test("이미 기록된 카테고리는 다시 쓸 수 없다")
    func 중복_기록() {
        var s = rolled([1, 1, 1, 1, 1])
        s = s.applying(.committed(.aces, 5))
        #expect(s.validate(.commit(.aces)) == .failure(.categoryAlreadyUsed(.aces)))
        #expect(s.allows(.commit(.deuces)))
    }

    @Test("주사위 인덱스는 0...4만 유효하다")
    func 인덱스_범위() {
        let s = rolled([1, 2, 3, 4, 5])
        #expect(s.validate(.toggleHold(5)) == .failure(.indexOutOfRange(5)))
        #expect(s.validate(.toggleHold(-1)) == .failure(.indexOutOfRange(-1)))
        #expect(s.allows(.toggleHold(4)))
    }

    @Test("게임이 끝나면 아무것도 허용되지 않는다")
    func 종료_후() {
        let s = rolled([1, 2, 3, 4, 5]).applying(.gameEnded)
        #expect(s.validate(.roll) == .failure(.gameFinished))
        #expect(s.validate(.toggleHold(0)) == .failure(.gameFinished))
        #expect(s.validate(.commit(.choice)) == .failure(.gameFinished))
    }

    @Test("검증은 상태를 바꾸지 않는다")
    func 부작용_없음() {
        let s = rolled([1, 2, 3, 4, 5])
        let before = s
        _ = s.validate(.roll)
        _ = s.validate(.commit(.aces))
        _ = s.validate(.toggleHold(99))
        #expect(s == before)
    }
}
