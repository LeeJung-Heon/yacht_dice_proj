import Foundation
import Observation
import YachtCore
import DiceTrajectory

/// 코어·드라이버·3D 연출을 잇는 유일한 오케스트레이터.
///
/// 핵심: 상태는 이벤트 발생 즉시 전이하지만, 화면에 노출되는 visibleState는
/// 주사위가 착지한 뒤에야 갱신된다. 점수판 미리보기가 주사위보다 먼저 뜨면
/// 게임이 망가진다 (스펙 §8.2).
@MainActor
@Observable
final class GameSession {
    private let driver: any MatchDriver
    private let stage: DiceStage
    private var log: MatchLog

    /// 뷰가 보는 상태. 연출이 끝난 뒤에만 갱신된다.
    private(set) var visibleState: GameState
    /// 연출 중이거나 드라이버를 기다리는 중이면 참. 입력을 잠그는 데 쓴다.
    private(set) var isBusy = false
    var assistEnabled = true
    var reduceMotion = false
    /// 다음 굴림에 쓸 던지는 방향. 제스처가 설정하고 performRoll이 소비한다.
    /// nil이면 무작위로 고른다 (버튼으로 굴린 경우).
    var nextThrowDirection: ThrowDirection?

    var onLogChanged: (@Sendable (MatchLog) -> Void)?
    var onCollisionCues: (@MainActor ([CollisionCue]) -> Void)?

    init(driver: any MatchDriver, stage: DiceStage, log: MatchLog) {
        self.driver = driver
        self.stage = stage
        self.log = log
        self.visibleState = log.state
    }

    func send(_ intent: Intent) async {
        guard !isBusy, visibleState.allows(intent) else { return }
        isBusy = true
        defer { isBusy = false }

        switch intent {
        case .roll:
            await performRoll()
        case .toggleHold(let index):
            await commitEvents([.holdToggled(index)])
            stage.placeHeld(visibleState.held.sorted(), values: visibleState.dice)
        case .commit(let category):
            let points = category.score(visibleState.dice)
            var events: [Event] = [.committed(category, points)]
            let afterCommit = visibleState.applying(events[0])
            events.append(afterCommit.isAllScored ? .gameEnded : .turnAdvanced)
            await commitEvents(events)
            if !visibleState.isAllScored { stage.reset() }
        }
    }

    /// 끝난 판을 접고 새 판을 시작한다.
    /// 저장 파일은 MatchStore.save가 게임 종료 시점에 이미 지웠으므로 로그만 갈아끼우면 된다.
    func startNewGame() {
        guard !isBusy, visibleState.phase == .finished else { return }
        log = MatchLog(playerCount: log.playerCount)
        visibleState = log.state
        nextThrowDirection = nil
        stage.reset()
        onLogChanged?(log)
    }

    /// Assist가 켜져 있고 아직 비어 있는 칸에 대해서만 예상 점수를 준다.
    func previewScore(_ category: ScoreCategory) -> Int? {
        guard assistEnabled,
              visibleState.phase == .rolling,
              !visibleState.scorecards[visibleState.currentPlayer].isFilled(category)
        else { return nil }
        return category.score(visibleState.dice)
    }

    // MARK: - 내부

    private func performRoll() async {
        let slots = visibleState.rollableIndices
        guard let values = try? await driver.requestRoll(count: slots.count) else { return }

        // 상태는 즉시 전이시키되 화면에는 아직 노출하지 않는다
        let pending = visibleState.applying(.rolled(values))

        let direction = nextThrowDirection ?? ThrowDirection.allCases.randomElement() ?? .center
        nextThrowDirection = nil
        let cues = await stage.roll(values: values, slots: slots,
                                    direction: direction, skipAnimation: reduceMotion)
        onCollisionCues?(cues)

        // 착지한 뒤에 노출한다
        log.append(.rolled(values))
        visibleState = pending
        try? await driver.submit(.rolled(values))
        onLogChanged?(log)
    }

    private func commitEvents(_ events: [Event]) async {
        var state = visibleState
        for event in events {
            log.append(event)
            state = state.applying(event)
            try? await driver.submit(event)
        }
        visibleState = state
        onLogChanged?(log)
    }
}
