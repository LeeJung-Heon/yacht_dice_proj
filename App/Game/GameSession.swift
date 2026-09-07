import Foundation
import Observation
import YachtCore
import YachtBot
import DiceTrajectory

/// 코어·드라이버·3D 연출을 잇는 유일한 오케스트레이터.
///
/// 핵심: 상태는 이벤트 발생 즉시 전이하지만, 화면에 노출되는 visibleState는
/// 주사위가 착지한 뒤에야 갱신된다. 점수판 미리보기가 주사위보다 먼저 뜨면
/// 게임이 망가진다 (스펙 §8.2).
///
/// 봇과 사람은 같은 `perform(_:)` 경로를 탄다. 사람의 `send(_:)`는 그 앞에 "지금 내 차례인가"만 더한다.
@MainActor
@Observable
final class GameSession {
    private let driver: any MatchDriver
    private let stage: DiceStage
    private(set) var record: MatchRecord

    /// 뷰가 보는 상태. 연출이 끝난 뒤에만 갱신된다.
    private(set) var visibleState: GameState
    /// 연출 중이거나 드라이버를 기다리는 중이면 참. 입력을 잠그는 데 쓴다.
    private(set) var isBusy = false
    /// 패스앤플레이에서 기기를 넘기는 동안 참.
    private(set) var pendingHandoff = false
    var assistEnabled = true
    var reduceMotion = false
    /// 다음 굴림에 쓸 던지는 방향. 제스처가 설정하고 performRoll이 소비한다.
    /// nil이면 무작위로 고른다 (버튼으로 굴린 경우).
    var nextThrowDirection: ThrowDirection?

    var onLogChanged: (@Sendable (MatchRecord) -> Void)?
    var onCollisionCues: (@MainActor ([CollisionCue]) -> Void)?
    /// 연출 중 주사위가 부딪히는 그 순간. 햅틱·사운드용.
    var onCollisionCue: (@MainActor (CollisionCue) -> Void)?
    /// 고정을 바꿨다.
    var onHoldToggled: (@MainActor () -> Void)?
    /// 기록했다: 카테고리, 점수, 이번 기록으로 상단 보너스를 달성했는가.
    var onCommitted: (@MainActor (ScoreCategory, Int, Bool) -> Void)?

    private var botTask: Task<Void, Never>?

    // MARK: 온라인
    private let transport: (any TurnTransport)?
    private var listenTask: Task<Void, Never>?
    /// 도착한 로그를 재생 중인 Task. 재생은 굴림마다 3D를 기다리므로 순서를 지켜야 한다.
    private var replayTask: Task<Void, Never>?
    /// 상대가 보낸 로그를 받아들일 수 없었을 때의 이유. 화면에 배너로 보인다.
    private(set) var lastTransportError: String?

    init(driver: any MatchDriver, stage: DiceStage, record: MatchRecord,
         transport: (any TurnTransport)? = nil) {
        precondition(record.participants.count == record.log.playerCount,
                     "참가자 \(record.participants.count)명과 로그의 \(record.log.playerCount)명이 다르다")
        self.driver = driver
        self.stage = stage
        self.record = record
        self.transport = transport
        self.visibleState = record.log.state
    }

    /// 테스트 호환. 혼자 연습 기록으로 감싼다.
    convenience init(driver: any MatchDriver, stage: DiceStage, log: MatchLog) {
        self.init(driver: driver, stage: stage,
                  record: MatchRecord(mode: .solo, participants: GameMode.solo.participants, log: log))
    }

    var participants: [Participant] { record.participants }
    var currentParticipant: Participant { participants[visibleState.currentPlayer] }

    /// 이 기기의 사람이 지금 입력할 수 있는가.
    var isLocalTurn: Bool {
        guard visibleState.phase != .finished, !pendingHandoff else { return false }
        return currentParticipant.isHuman
    }

    /// 사람의 입력. 내 차례가 아니면 버린다.
    func send(_ intent: Intent) async {
        guard isLocalTurn else {
            if case .roll = intent { nextThrowDirection = nil }
            return
        }
        await perform(intent)
    }

    func acknowledgeHandoff() {
        pendingHandoff = false
    }

    /// 복원 직후 현재 차례의 주인에게 진행을 넘긴다. 봇이면 바로 둔다.
    func resumeTurnOwner() {
        scheduleTurnOwner(announceHandoff: false)
    }

    func waitForBotTurn() async {
        await botTask?.value
    }

    /// 원격 로그를 받아 재생하는 루프를 시작한다. transport가 있을 때 AppContainer가 부른다.
    func startListening() {
        guard let transport, listenTask == nil else { return }
        listenTask = Task { [weak self] in
            for await log in transport.incomingLogs {
                guard let self else { return }
                let previous = replayTask
                replayTask = Task { @MainActor in
                    await previous?.value
                    await self.replay(remote: log)
                }
            }
        }
    }

    /// 테스트용: 도착한 로그를 전부 재생할 때까지 기다린다.
    /// 로그가 아직 도착하지 않았을 수 있으므로 잠깐(최대 2초) 기다려 본다.
    func waitForIncoming() async {
        let before = record.log.events.count
        let deadline = ContinuousClock.now + .seconds(2)
        while replayTask == nil || record.log.events.count == before {
            if ContinuousClock.now > deadline || lastTransportError != nil { break }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        await replayTask?.value
    }

    /// 끝난 판을 접고 같은 모드로 새 판을 시작한다.
    /// 저장 파일은 MatchStore.save가 게임 종료 시점에 이미 지웠으므로 기록만 갈아끼우면 된다.
    func startNewGame() {
        guard !isBusy, visibleState.phase == .finished else { return }
        record = MatchRecord(mode: record.mode, participants: record.participants,
                             log: MatchLog(playerCount: record.participants.count))
        visibleState = record.log.state
        nextThrowDirection = nil
        pendingHandoff = false
        stage.reset()
        onLogChanged?(record)
        scheduleTurnOwner(announceHandoff: false)
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

    /// 출처를 가리지 않는 실제 실행 경로. 봇도 여기로 들어온다.
    private func perform(_ intent: Intent) async {
        guard !isBusy, visibleState.allows(intent) else {
            // 굴리지 못하고 되돌아가면 이번 스와이프의 방향은 버린다.
            // 제스처는 조건 없이 방향을 설정하는데, 여기서 소비하지 않고 반려하면
            // 연출 중에 왼쪽으로 쓸어넘긴 방향이 "다음" 굴림에 뒤늦게 적용된다.
            if case .roll = intent { nextThrowDirection = nil }
            return
        }
        isBusy = true
        defer { isBusy = false }

        switch intent {
        case .roll:
            await performRoll()
        case .toggleHold(let index):
            await commitEvents([.holdToggled(index)])
            stage.placeHeld(visibleState.held.sorted(), values: visibleState.dice)
            onHoldToggled?()
        case .commit(let category):
            let points = category.score(visibleState.dice)
            let bonusBefore = visibleState.scorecards[visibleState.currentPlayer].upperBonus
            let seat = visibleState.currentPlayer
            var events: [Event] = [.committed(category, points)]
            let afterCommit = visibleState.applying(events[0])
            events.append(afterCommit.isAllScored ? .gameEnded : .turnAdvanced)
            await commitEvents(events)
            let bonusReached = bonusBefore == 0 && visibleState.scorecards[seat].upperBonus > 0
            onCommitted?(category, points, bonusReached)
            if !visibleState.isAllScored {
                stage.reset()
                scheduleTurnOwner(announceHandoff: true)
            }
            await publishTurnIfNeeded()
        }
    }

    /// 내 턴이 끝나 원격 좌석에게 넘어갔거나 게임이 끝났으면 로그를 올린다.
    private func publishTurnIfNeeded() async {
        guard let transport else { return }
        if visibleState.phase == .finished {
            try? await transport.endMatch(log: record.log, totals: visibleState.scorecards.map(\.total))
        } else if case .remote = currentParticipant {
            try? await transport.endTurn(log: record.log)
        }
    }

    /// 상대가 보낸 로그에서 내가 모르는 이벤트만 검증하며 재생한다.
    /// 굴림은 3D로 보여주고, 고정·기록은 즉시 적용한다.
    private func replay(remote log: MatchLog) async {
        let mine = record.log.events
        guard log.playerCount == record.log.playerCount,
              log.events.count > mine.count,
              Array(log.events.prefix(mine.count)) == mine
        else {
            if log.events.count > mine.count { lastTransportError = "상대의 기록이 내 기록과 어긋난다" }
            return
        }
        for event in log.events.dropFirst(mine.count) {
            guard visibleState.canApply(event) else {
                lastTransportError = "상대가 보낸 이벤트가 규칙에 맞지 않는다: \(event)"
                return
            }
            isBusy = true
            switch event {
            case .rolled(let values):
                let slots = visibleState.rollableIndices
                _ = await stage.roll(values: values, slots: slots,
                                     direction: ThrowDirection.allCases.randomElement() ?? .center,
                                     skipAnimation: reduceMotion,
                                     onCue: { [weak self] cue in self?.onCollisionCue?(cue) })
                record.log.append(event)
                visibleState = visibleState.applying(event)
            case .holdToggled:
                record.log.append(event)
                visibleState = visibleState.applying(event)
                stage.placeHeld(visibleState.held.sorted(), values: visibleState.dice)
            case .committed, .gameEnded:
                record.log.append(event)
                visibleState = visibleState.applying(event)
            case .turnAdvanced:
                record.log.append(event)
                visibleState = visibleState.applying(event)
                stage.reset()
            }
            isBusy = false
        }
        lastTransportError = nil
        scheduleTurnOwner(announceHandoff: false)
        onLogChanged?(record)
    }

    /// 새 차례의 주인에 따라 다음 일을 정한다.
    /// - 봇: 자기 턴을 Task로 둔다.
    /// - 사람 (2인 이상): 기기를 넘기도록 핸드오프를 띄운다.
    /// - 원격: P3에서 채운다.
    private func scheduleTurnOwner(announceHandoff: Bool) {
        guard visibleState.phase != .finished else { return }
        switch currentParticipant {
        case .bot(let difficulty):
            botTask = Task { [weak self] in await self?.runBotTurn(difficulty) }
        case .human:
            // 기기를 넘길 사람이 둘 이상일 때만. 봇 상대 한 판에서는 넘길 사람이 없다.
            if announceHandoff && participants.filter(\.isHuman).count > 1 { pendingHandoff = true }
        case .remote:
            break
        }
    }

    private func runBotTurn(_ difficulty: BotDifficulty) async {
        // perform 안에서 예약된 Task다. isBusy가 풀린 뒤에 시작해야 첫 Intent가 거부되지 않는다.
        await Task.yield()
        let bot = BotPlayer(difficulty: difficulty)
        var rng = SystemRandomNumberGenerator()
        let owner = visibleState.currentPlayer
        var guardCounter = 0
        while visibleState.currentPlayer == owner, visibleState.phase != .finished, guardCounter < 40 {
            let plan = bot.plan(visibleState, using: &rng)
            guard !plan.isEmpty else { break }
            for intent in plan {
                guard visibleState.allows(intent) else { return }
                await think()
                await perform(intent)
                guardCounter += 1
            }
        }
    }

    /// 사람처럼 잠깐 뜸을 들인다. Reduce Motion이면 거의 바로.
    private func think() async {
        let delay: Duration = reduceMotion ? .milliseconds(10) : .milliseconds(Int.random(in: 350...700))
        try? await Task.sleep(for: delay)
    }

    private func performRoll() async {
        let slots = visibleState.rollableIndices
        guard let values = try? await driver.requestRoll(count: slots.count) else { return }

        // 상태는 즉시 전이시키되 화면에는 아직 노출하지 않는다
        let pending = visibleState.applying(.rolled(values))

        let direction = nextThrowDirection ?? ThrowDirection.allCases.randomElement() ?? .center
        nextThrowDirection = nil
        let cues = await stage.roll(values: values, slots: slots,
                                    direction: direction, skipAnimation: reduceMotion,
                                    onCue: { [weak self] cue in self?.onCollisionCue?(cue) })
        onCollisionCues?(cues)

        // 착지한 뒤에 노출한다
        record.log.append(.rolled(values))
        visibleState = pending
        try? await driver.submit(.rolled(values))
        onLogChanged?(record)
    }

    private func commitEvents(_ events: [Event]) async {
        var state = visibleState
        for event in events {
            record.log.append(event)
            state = state.applying(event)
            try? await driver.submit(event)
        }
        visibleState = state
        onLogChanged?(record)
    }
}
