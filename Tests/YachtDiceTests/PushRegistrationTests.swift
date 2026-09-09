import Testing
import Foundation
@testable import YachtDice

@Suite("푸시 알림")
@MainActor
struct PushRegistrationTests {
    @Test("알림 페이로드의 matchID를 UUID로 읽는다")
    func 매치_ID() {
        let id = UUID()
        #expect(PushRegistration.matchID(from: ["matchID": id.uuidString]) == id)
        #expect(PushRegistration.matchID(from: ["matchID": "abc"]) == nil)
        #expect(PushRegistration.matchID(from: [:]) == nil)
    }

    @Test("열 곳이 아직 없으면 알림을 보관했다가 걸리면 넘긴다")
    func 보류_후_전달() {
        let push = PushRegistration()
        let id = UUID()
        push.open(matchID: id)
        var opened: UUID?
        push.onOpenMatch = { opened = $0 }
        #expect(opened == id)
    }
}
