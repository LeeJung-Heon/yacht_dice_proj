import Testing
import Foundation
@testable import YachtDice

@Suite("이모지 반응 판")
@MainActor
struct ReactionBoardTests {
    /// 두 기기. A는 좌석 0, B는 좌석 1. 시간을 줄여 둔다.
    private func makePair() -> (a: ReactionBoard, b: ReactionBoard, ta: InMemoryTurnTransport, tb: InMemoryTurnTransport) {
        let (ta, tb) = InMemoryTurnTransport.pair()
        let a = ReactionBoard(localSeat: 0, remoteSeat: 1, remoteName: "B", transport: ta,
                              cooldown: .milliseconds(200), burstDuration: .milliseconds(300))
        let b = ReactionBoard(localSeat: 1, remoteSeat: 0, remoteName: "A", transport: tb,
                              cooldown: .milliseconds(200), burstDuration: .milliseconds(300))
        a.start(); b.start()
        return (a, b, ta, tb)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test("이모지 하나만 참이다", arguments: ["🔥", "👍🏽", "🇰🇷", "👨‍👩‍👧‍👦", "1️⃣", "❤️", "😀", "⛹🏽‍♀️", "☝🏽", "🏳️‍🌈",
                                         "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "🙂‍↔️", "🧑🏽‍🦯‍➡️", "#️⃣", "©️"])
    func 이모지(_ text: String) {
        #expect(ReactionBoard.isSingleEmoji(text))
    }

    @Test("이모지가 아니거나 둘 이상이거나 너무 길면 거짓이다",
          arguments: ["a", "1", "#", "🔥🔥", "", "🔥a", " ", "가", String(repeating: "👨‍👩‍👧‍👦", count: 3),
                      "🔥" + String(repeating: "\u{200D}", count: 70),
                      "a🏽", "좆🏽", "🇰", "🔥" + String(repeating: "\u{0301}", count: 20), "🔥\u{093E}", "1\u{FE0F}"])
    func 이모지_아님(_ text: String) {
        #expect(!ReactionBoard.isSingleEmoji(text))
    }

    @Test("보내면 상대에게 가고 내 좌석으로 떠오르며 내 명패에 배지가 붙는다")
    func 보내기() {
        let (a, _, _, _) = makePair()
        #expect(a.send("🔥", eventCount: 2))
        #expect(a.bursts.map(\.seat) == [0] && a.bursts.first?.emoji == "🔥")
        #expect(a.badges[0] == ReactionBoard.Badge(emoji: "🔥", eventCount: 2))
    }

    @Test("보낸 반응은 전송에 그대로 실린다")
    func 전송() async {
        let (a, _, ta, _) = makePair()
        a.send("🔥", eventCount: 2)
        await waitUntil { !ta.sentReactions.isEmpty }
        #expect(ta.sentReactions == [Reaction(emoji: "🔥", eventCount: 2)])
    }

    @Test("간격 안의 둘째는 보내지 않고 간격이 지나면 다시 보낸다")
    func 간격() async throws {
        let (a, _, ta, _) = makePair()
        #expect(a.send("🔥", eventCount: 0))
        #expect(!a.canSend)
        #expect(!a.send("😭", eventCount: 0))
        try await Task.sleep(for: .milliseconds(250))
        #expect(a.canSend)
        #expect(a.send("😭", eventCount: 0))
        await waitUntil { ta.sentReactions.count == 2 }
        #expect(ta.sentReactions.map(\.emoji) == ["🔥", "😭"])
    }

    @Test("이모지가 아니면 보내지 않는다")
    func 글자() async throws {
        let (a, _, ta, _) = makePair()
        #expect(!a.send("hi", eventCount: 0))
        #expect(a.canSend && a.bursts.isEmpty && a.badges.isEmpty)
        try await Task.sleep(for: .milliseconds(50))
        #expect(ta.sentReactions.isEmpty)
    }

    @Test("받으면 상대 좌석으로 떠오르고 배지가 붙는다")
    func 받기() async {
        let (a, b, _, _) = makePair()
        a.send("🔥", eventCount: 1)
        await waitUntil { !b.bursts.isEmpty }
        #expect(b.bursts.map(\.seat) == [0] && b.bursts.first?.emoji == "🔥")
        #expect(b.badges[0] == ReactionBoard.Badge(emoji: "🔥", eventCount: 1))
        #expect(b.badges[1] == nil)
    }

    @Test("받은 것이 이모지가 아니거나 같은 사람의 간격 안 둘째면 버린다")
    func 받기_거르기() async throws {
        let (_, b, ta, _) = makePair()
        await ta.sendReaction(Reaction(emoji: "hello", eventCount: 0))
        try await Task.sleep(for: .milliseconds(50))
        #expect(b.bursts.isEmpty && b.badges.isEmpty)
        await ta.sendReaction(Reaction(emoji: "🔥", eventCount: 0))
        await ta.sendReaction(Reaction(emoji: "😭", eventCount: 0))
        try await Task.sleep(for: .milliseconds(50))
        #expect(b.bursts.map(\.emoji) == ["🔥"])
    }

    @Test("떠오른 반응은 정한 시간이 지나면 목록에서 빠지고 배지는 남는다")
    func 떠오름_수명() async throws {
        let (a, _, _, _) = makePair()
        a.send("🔥", eventCount: 0)
        try await Task.sleep(for: .milliseconds(400))
        #expect(a.bursts.isEmpty)
        #expect(a.badges[0]?.emoji == "🔥")
    }

    @Test("배지는 보낸 수 뒤에 차례가 바뀌면 사라지고 같은 차례에서는 남는다")
    func 배지_수명() {
        let (a, _, _, _) = makePair()
        a.noteTurn(0, eventCount: 0)
        a.send("🔥", eventCount: 0)
        a.noteTurn(0, eventCount: 1)
        #expect(a.badges[0] != nil)
        a.noteTurn(1, eventCount: 2)
        #expect(a.badges[0] == nil)
    }

    @Test("차례가 바뀐 그 수에서 보낸 배지는 다음 차례가 바뀔 때까지 남는다")
    func 바뀐_수의_배지() {
        let (a, _, _, _) = makePair()
        a.noteTurn(1, eventCount: 3)
        a.send("😭", eventCount: 3)
        a.noteTurn(1, eventCount: 3)
        #expect(a.badges[0]?.emoji == "😭")
        a.noteTurn(0, eventCount: 4)
        #expect(a.badges[0] == nil)
    }

    @Test("같은 사람의 다음 이모지가 배지를 바꾸고 판이 끝난 뒤에도 주고받는다")
    func 끝난_뒤() async throws {
        let (a, b, _, _) = makePair()
        a.noteTurn(nil, eventCount: 9); b.noteTurn(nil, eventCount: 9)
        #expect(a.send("🔥", eventCount: 9))
        try await Task.sleep(for: .milliseconds(260))
        #expect(a.send("👏", eventCount: 9))
        a.noteTurn(nil, eventCount: 9)
        #expect(a.badges[0]?.emoji == "👏")
        await waitUntil { b.badges[0]?.emoji == "👏" }
        #expect(b.badges[0]?.emoji == "👏")
    }

    @Test("stop() 뒤에는 받지 않는다")
    func 접기() async throws {
        let (a, b, _, _) = makePair()
        b.stop()
        a.send("🔥", eventCount: 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(b.bursts.isEmpty && b.badges.isEmpty)
    }
}
