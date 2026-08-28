import Testing
import Foundation
import YachtCore
import DiceTrajectory
@testable import YachtDice

/// 눈을 대본으로 공급하는 테스트용 드라이버.
private struct ScriptedDriver: MatchDriver {
    let script: [[Int]]
    let cursor = Counter()

    final class Counter: @unchecked Sendable {
        private var value = 0
        func next() -> Int { defer { value += 1 }; return value }
    }

    func requestRoll(count: Int) async throws -> [Int] {
        let roll = script[cursor.next() % script.count]
        return Array(roll.prefix(count))
    }
    func submit(_ event: Event) async throws {}
    var incoming: AsyncStream<Event> { AsyncStream { $0.finish() } }
}

@Suite("게임 세션")
@MainActor
struct GameSessionTests {

    /// - Parameter animated: 기본은 false. 궤적을 실제로 재생하면 굴림 하나에 2초가 걸려서
    ///   12턴 완주 테스트가 24초를 넘긴다. 연출 순서 자체를 보는 테스트만 true로 켠다.
    private func makeSession(script: [[Int]], animated: Bool = false) throws -> GameSession {
        let session = GameSession(
            driver: ScriptedDriver(script: script),
            stage: DiceStage(library: try TrajectoryLibrary.bundled()),
            log: MatchLog(playerCount: 1))
        session.reduceMotion = !animated
        return session
    }

    @Test("굴림 요청이 상태에 반영된다")
    func 굴림() async throws {
        let session = try makeSession(script: [[3, 1, 4, 6, 6]])
        await session.send(.roll)
        #expect(session.visibleState.dice == [3, 1, 4, 6, 6])
        #expect(session.visibleState.rollsRemaining == 2)
    }

    @Test("연출이 끝난 뒤에야 상태가 노출된다")
    func 연출_큐() async throws {
        let session = try makeSession(script: [[1, 1, 1, 1, 1]], animated: true)
        #expect(session.visibleState.phase == .awaitingFirstRoll)
        let task = Task { await session.send(.roll) }
        // send가 완료되기 전에는 아직 굴리기 전 상태여야 한다
        #expect(session.visibleState.dice == [0, 0, 0, 0, 0])
        await task.value
        #expect(session.visibleState.dice == [1, 1, 1, 1, 1])
    }

    @Test("불법 의도는 무시되고 상태를 바꾸지 않는다")
    func 불법_의도() async throws {
        let session = try makeSession(script: [[1, 2, 3, 4, 5]])
        let before = session.visibleState
        await session.send(.commit(.aces))   // 굴리기 전이라 불가
        #expect(session.visibleState == before)
    }

    @Test("기록하면 자동으로 다음 턴으로 넘어간다")
    func 기록_후_턴_전환() async throws {
        let session = try makeSession(script: [[6, 6, 6, 6, 6]])
        await session.send(.roll)
        await session.send(.commit(.yacht))
        #expect(session.visibleState.scorecards[0].entry(.yacht) == 50)
        #expect(session.visibleState.turnIndex == 2)
        #expect(session.visibleState.phase == .awaitingFirstRoll)
    }

    @Test("12턴을 마치면 게임이 끝난다")
    func 완주() async throws {
        let session = try makeSession(script: [[1, 2, 3, 4, 5]])
        for _ in 0..<12 {
            await session.send(.roll)
            let open = session.visibleState.scorecards[0].openCategories
            await session.send(.commit(open[0]))
        }
        #expect(session.visibleState.phase == .finished)
        #expect(session.visibleState.scorecards[0].isComplete)
    }

    @Test("Assist가 켜져 있으면 예상 점수를 준다")
    func 예상_점수() async throws {
        let session = try makeSession(script: [[5, 5, 5, 5, 5]])
        await session.send(.roll)
        session.assistEnabled = true
        #expect(session.previewScore(.yacht) == 50)
        #expect(session.previewScore(.fives) == 25)
        session.assistEnabled = false
        #expect(session.previewScore(.yacht) == nil)
    }

    @Test("이미 기록된 칸은 예상 점수를 주지 않는다")
    func 예상_점수_기록된_칸() async throws {
        let session = try makeSession(script: [[1, 1, 1, 1, 1]])
        session.assistEnabled = true
        await session.send(.roll)
        await session.send(.commit(.aces))
        await session.send(.roll)
        #expect(session.previewScore(.aces) == nil)
    }

    @Test("로그 변경이 통지된다 — 저장 훅")
    func 로그_통지() async throws {
        let session = try makeSession(script: [[2, 2, 2, 2, 2]])
        let recorder = LogRecorder()
        session.onLogChanged = { recorder.record($0) }
        await session.send(.roll)
        #expect(recorder.count > 0, "저장 훅이 불리지 않았다")
    }

    final class LogRecorder: @unchecked Sendable {
        private(set) var count = 0
        func record(_ log: MatchLog) { count += 1 }
    }
}
