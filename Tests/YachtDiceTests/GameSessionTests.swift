import Testing
import Foundation
import YachtCore
import YachtBot
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

    @Test("끝난 판에서 새 게임을 시작할 수 있다")
    func 새_게임() async throws {
        let session = try makeSession(script: [[1, 2, 3, 4, 5]])
        for _ in 0..<12 {
            await session.send(.roll)
            await session.send(.commit(session.visibleState.scorecards[0].openCategories[0]))
        }
        #expect(session.visibleState.phase == .finished)
        let finalScore = session.visibleState.scorecards[0].total
        #expect(finalScore > 0, "최종 점수를 보여줄 수 없다")

        let recorder = LogRecorder()
        session.onLogChanged = { recorder.record($0) }
        session.startNewGame()

        #expect(session.visibleState.phase == .awaitingFirstRoll)
        #expect(session.visibleState.turnIndex == 1)
        #expect(session.visibleState.scorecards[0].total == 0)
        #expect(session.visibleState.scorecards[0].openCategories.count == ScoreCategory.allCases.count)
        #expect(session.visibleState.allows(.roll), "새 판에서 굴릴 수 없다")
        #expect(recorder.count == 1, "새 판이 저장 훅에 통지되지 않았다")

        await session.send(.roll)
        #expect(session.visibleState.dice == [1, 2, 3, 4, 5])
    }

    @Test("게임이 끝나지 않았으면 새 게임 요청을 무시한다")
    func 새_게임_거부() async throws {
        let session = try makeSession(script: [[1, 2, 3, 4, 5]])
        await session.send(.roll)
        let before = session.visibleState
        session.startNewGame()
        #expect(session.visibleState == before, "진행 중인 판이 초기화됐다")
    }

    @Test("굴릴 수 없어 반려된 스와이프의 방향은 남지 않는다")
    func 방향_누수_반려() async throws {
        let session = try makeSession(script: [[1, 2, 3, 4, 5]])
        for _ in 0..<3 { await session.send(.roll) }
        #expect(session.visibleState.rollsRemaining == 0)

        session.nextThrowDirection = .left      // 제스처가 조건 없이 설정한다
        await session.send(.roll)               // 더 굴릴 수 없어 반려된다
        #expect(session.nextThrowDirection == nil,
                "굴리지 못한 방향이 남아 다음 굴림으로 샌다")
    }

    @Test("연출 중에 쓸어넘긴 방향이 다음 굴림으로 새지 않는다")
    func 방향_누수_연출중() async throws {
        let session = try makeSession(script: [[1, 1, 1, 1, 1]], animated: true)
        let rolling = Task { await session.send(.roll) }
        while !session.isBusy { await Task.yield() }

        session.nextThrowDirection = .left
        await session.send(.roll)               // isBusy라 반려된다
        #expect(session.nextThrowDirection == nil,
                "연출 중 스와이프한 방향이 그대로 남아 다음 굴림에 적용된다")
        await rolling.value
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
        func record(_ record: MatchRecord) { count += 1 }
    }
}

@Suite("게임 세션 - 참가자")
@MainActor
struct GameSessionParticipantTests {

    private struct ConstantDriver: MatchDriver {
        let face: Int
        func requestRoll(count: Int) async throws -> [Int] { Array(repeating: face, count: count) }
        func submit(_ event: Event) async throws {}
        var incoming: AsyncStream<Event> { AsyncStream { $0.finish() } }
    }

    private final class Box: @unchecked Sendable {
        var value: MatchRecord?
    }

    private func makeSession(mode: GameMode, face: Int = 3) throws -> GameSession {
        let session = GameSession(driver: ConstantDriver(face: face),
                                  stage: DiceStage(library: try TrajectoryLibrary.bundled()),
                                  record: MatchRecord(mode: mode))
        session.reduceMotion = true
        return session
    }

    @Test("혼자 연습은 항상 내 차례이고 핸드오프가 없다")
    func 혼자() async throws {
        let session = try makeSession(mode: .solo)
        #expect(session.isLocalTurn)
        await session.send(.roll)
        await session.send(.commit(.threes))
        #expect(session.isLocalTurn)
        #expect(!session.pendingHandoff)
    }

    @Test("내 턴이 끝나면 봇이 자기 턴을 끝까지 두고 차례가 돌아온다")
    func 봇_턴() async throws {
        let session = try makeSession(mode: .versusBot(.normal))
        #expect(session.isLocalTurn)
        await session.send(.roll)
        await session.send(.commit(.threes))
        #expect(!session.isLocalTurn, "봇 차례인데 입력이 열려 있다")

        await session.waitForBotTurn()
        #expect(session.visibleState.currentPlayer == 0)
        #expect(session.visibleState.turnIndex == 2)
        #expect(session.visibleState.scorecards[1].openCategories.count == 11, "봇이 기록하지 않았다")
        #expect(session.isLocalTurn)
    }

    @Test("봇 차례에는 send가 거부된다")
    func 봇_차례_잠금() async throws {
        let session = try makeSession(mode: .versusBot(.easy))
        await session.send(.roll)
        await session.send(.commit(.threes))
        let before = session.visibleState
        await session.send(.roll)   // 봇 차례에 끼어들기
        #expect(session.visibleState.currentPlayer == before.currentPlayer)
        await session.waitForBotTurn()
    }

    @Test("패스앤플레이는 사람 차례가 바뀔 때 핸드오프를 기다린다")
    func 핸드오프() async throws {
        let session = try makeSession(mode: .passAndPlay(names: ["A", "B"]))
        await session.send(.roll)
        await session.send(.commit(.threes))
        #expect(session.pendingHandoff)
        #expect(!session.isLocalTurn)
        #expect(session.currentParticipant == .human(name: "B"))

        await session.send(.roll)
        #expect(session.visibleState.rollsRemaining == 3, "핸드오프 중에 굴려졌다")

        session.acknowledgeHandoff()
        #expect(session.isLocalTurn)
        await session.send(.roll)
        #expect(session.visibleState.rollsRemaining == 2)
    }

    @Test("4인 패스앤플레이 12턴 완주")
    func 사인_완주() async throws {
        let session = try makeSession(mode: .passAndPlay(names: ["A", "B", "C", "D"]))
        for category in ScoreCategory.allCases {
            for _ in 0..<4 {
                if session.pendingHandoff { session.acknowledgeHandoff() }
                await session.send(.roll)
                await session.send(.commit(category))
            }
        }
        #expect(session.visibleState.phase == .finished)
        let allComplete = session.visibleState.scorecards.allSatisfy { $0.isComplete }
        #expect(allComplete)
    }

    @Test("복원한 판의 현재 차례가 봇이면 바로 봇이 둔다")
    func 복원_봇_차례() async throws {
        var record = MatchRecord(mode: .versusBot(.normal))
        record.log.append(.rolled([3, 3, 3, 3, 3]))
        record.log.append(.committed(.threes, 15))
        record.log.append(.turnAdvanced)
        let session = GameSession(driver: ConstantDriver(face: 2),
                                  stage: DiceStage(library: try TrajectoryLibrary.bundled()),
                                  record: record)
        session.reduceMotion = true
        session.resumeTurnOwner()
        await session.waitForBotTurn()
        #expect(session.visibleState.currentPlayer == 0)
    }

    @Test("onLogChanged는 모드를 담은 기록을 준다")
    func 저장_콜백() async throws {
        let session = try makeSession(mode: .versusBot(.hard))
        let saved = Box()
        session.onLogChanged = { saved.value = $0 }
        await session.send(.roll)
        #expect(saved.value?.mode == .versusBot(.hard))
        #expect(saved.value?.log.events.count == 1)
    }
}
