import Testing
@testable import YachtDice

@Suite("주사위 면 뷰")
struct DieFaceViewTests {
    @Test("눈 개수", arguments: 0...6)
    func 눈(value: Int) {
        #expect(DieFaceView.pipPoints(for: value).count == value)
    }
}
