import Testing
import GameCore
@testable import YachtDice

@Suite("오목 - 상대의 고른 자리")
struct OmokLiveTests {
    @Test("판 밖 좌표는 그리지 않는다")
    func 판_밖() {
        let state = MoveLog<Omok>().state
        #expect(OmokLive.remotePreview(Omok.Move(x: 19, y: 0), in: state) == nil)
        #expect(OmokLive.remotePreview(Omok.Move(x: 0, y: 19), in: state) == nil)
        #expect(OmokLive.remotePreview(Omok.Move(x: -1, y: 3), in: state) == nil)
    }

    @Test("이미 돌이 있는 자리는 그리지 않는다")
    func 돌_위() {
        var log = MoveLog<Omok>()
        log.append(Omok.Move(x: 7, y: 7))
        #expect(OmokLive.remotePreview(Omok.Move(x: 7, y: 7), in: log.state) == nil)
    }

    @Test("빈 교차점은 그대로 그린다")
    func 빈_자리() {
        let state = MoveLog<Omok>().state
        #expect(OmokLive.remotePreview(Omok.Move(x: 3, y: 4), in: state) == Omok.Move(x: 3, y: 4))
        #expect(OmokLive.remotePreview(nil, in: state) == nil)
    }
}
