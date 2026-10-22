import Testing
import Foundation
@testable import YachtDice

@Suite("컵퐁 - 던지기 순서")
@MainActor
struct CupPongThrowTests {
    /// 테스트가 열 때까지 멈춰 있는 느린 전송.
    @MainActor
    final class Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false
        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func open() { isOpen = true; waiters.forEach { $0.resume() }; waiters = [] }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test("공이 닿으면 전송이 끝나기 전에도 화면이 풀린다")
    func 착지에_풀림() async {
        let gate = Gate()
        var landed = false, rejected = false, played = false
        let throwing = Task {
            await CupPongThrow.run(play: { await gate.wait(); played = true; return true },
                                   animate: {}, landed: { landed = true }, rejected: { rejected = true })
        }
        await waitUntil { landed }
        #expect(landed && !played, "느린 전송이 착지 뒤의 화면을 붙잡았다")
        gate.open()
        await throwing.value
        #expect(played && !rejected)
    }

    @Test("화면 Task가 취소돼도 수는 끝까지 올라간다")
    func 취소돼도_전송() async {
        let gate = Gate()
        var played = false, landed = false
        let throwing = Task {
            await CupPongThrow.run(play: { await gate.wait(); played = true; return true },
                                   animate: { try? await Task.sleep(for: .seconds(5)) }, landed: { landed = true }, rejected: {})
        }
        try? await Task.sleep(for: .milliseconds(20))
        throwing.cancel()
        await throwing.value
        gate.open()
        await waitUntil { played }
        #expect(played, "화면을 떠나자 이미 채널로 나간 수의 전송이 끊겼다")
        #expect(!landed, "취소된 연출 뒤에 화면을 풀었다")
    }

    @Test("규칙이 거절하면 착지 뒤에 알린다")
    func 거절() async {
        var order: [String] = []
        await CupPongThrow.run(play: { false }, animate: {}, landed: { order.append("landed") }, rejected: { order.append("rejected") })
        #expect(order == ["landed", "rejected"])
    }
}
