import Foundation
import Observation
import YachtCore
import YachtBot
import DiceTrajectory
import simd

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

    /// 남(원격 상대나 봇)이 방금 기록한 것. 화면이 팝업으로 알린다. id가 바뀔 때마다 새 기록이다.
    struct OpponentCommit: Equatable {
        let id = UUID()
        let seat: Int
        let category: ScoreCategory
        let points: Int
    }
    private(set) var lastOpponentCommit: OpponentCommit?

    // MARK: 온라인
    private let transport: (any TurnTransport)?
    private var listenTask: Task<Void, Never>?
    private var presenceTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    /// 도착한 로그를 재생 중인 Task. 재생은 굴림마다 3D를 기다리므로 순서를 지켜야 한다.
    private var replayTask: Task<Void, Never>?
    /// 상대가 보낸 로그를 받아들일 수 없었을 때의 이유. 화면에 배너로 보인다.
    private(set) var lastTransportError: String?
    /// 이 판의 굴림마다 고른 궤적·회전. 상대에게 보내 같은 던지기를 보여 준다.
    private(set) var throwHints: [ThrowHint] = []
    /// 원격 상대가 같은 채널에 있는가.
    private(set) var opponentPresent = false
    /// 전송 채널이 살아 있는가. 온라인이 아니면 항상 참.
    private(set) var isConnected = true

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
            for await update in transport.incoming {
                guard let self else { return }
                let previous = replayTask
                replayTask = Task { @MainActor in
                    await previous?.value
                    await self.replay(remote: update)
                }
            }
        }
        let remoteID = remotePlayerID
        presenceTask = Task { [weak self] in
            for await present in transport.presence {
                guard let self else { return }
                self.opponentPresent = remoteID.map { present.contains($0) } ?? !present.isEmpty
            }
        }
        connectionTask = Task { [weak self] in
            for await connected in transport.connection {
                self?.isConnected = connected
            }
        }
    }

    /// 원격 좌석의 플레이어 ID. 온라인이 아니면 nil.
    private var remotePlayerID: String? {
        for participant in participants {
            if case .remote(let playerID, _) = participant { return playerID }
        }
        return nil
    }

    /// 테스트용: 무대의 주사위 자세.
    func stageOrientation(slot: Int) -> simd_quatf? { stage.orientation(slot: slot) }

    /// 테스트용: 도착한 로그를 전부 재생할 때까지 기다린다.
    /// 로그가 아직 도착하지 않았을 수 있으므로 잠깐(최대 2초) 기다린 뒤,
    /// 실시간 갱신은 여러 로그가 잇따라 오므로 50ms 동안 새 이벤트가 없을 때까지 더 기다린다.
    func waitForIncoming() async {
        let before = record.log.events.count
        let deadline = ContinuousClock.now + .seconds(2)
        while replayTask == nil || record.log.events.count == before {
            if ContinuousClock.now > deadline || lastTransportError != nil { break }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        var settled = -1
        while true {
            await replayTask?.value
            let count = record.log.events.count
            if count == settled { break }
            settled = count
            try? await Task.sleep(for: .milliseconds(50))
        }
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
        throwHints = []
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
            await publishProgressIfOnline()
        case .toggleHold(let index):
            await commitEvents([.holdToggled(index)])
            stage.placeHeld(visibleState.held.sorted(), values: visibleState.dice)
            onHoldToggled?()
            await publishProgressIfOnline()
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
            if !participants[seat].isHuman {
                lastOpponentCommit = OpponentCommit(seat: seat, category: category, points: points)
            }
            if !visibleState.isAllScored {
                stage.reset()
                scheduleTurnOwner(announceHandoff: true)
            }
            await publishTurnIfNeeded()
        }
    }

    /// 앱이 앞으로 돌아왔을 때 등, 서버 상태를 즉시 다시 읽는다.
    func resync() async {
        await transport?.refresh()
    }

    /// 턴 도중의 굴림·고정을 바로 올린다. 상대 화면이 내 플레이를 실시간으로 따라오게 하기 위해서다.
    private func publishProgressIfOnline() async {
        guard let transport else { return }
        do {
            try await transport.publishProgress(log: record.log, hints: throwHints)
            lastTransportError = nil
        } catch {
            lastTransportError = "서버에 보내지 못해 다시 시도하는 중이다"
        }
    }

    /// 내 턴이 끝나 원격 좌석에게 넘어갔거나 게임이 끝났으면 로그를 올린다.
    private func publishTurnIfNeeded() async {
        guard let transport else { return }
        do {
            if visibleState.phase == .finished {
                try await transport.endMatch(log: record.log, hints: throwHints,
                                             totals: visibleState.scorecards.map(\.total))
            } else if case .remote = currentParticipant {
                try await transport.endTurn(log: record.log, hints: throwHints, nextSeat: visibleState.currentPlayer)
            }
            lastTransportError = nil
        } catch {
            lastTransportError = "서버에 보내지 못해 다시 시도하는 중이다"
        }
    }

    /// 상대 플레이를 재생할 때 이벤트 사이에 두는 뜸. 실제 상대의 손놀림보다 빨리 지나가면 뭘 했는지 읽을 수 없다.
    static let remotePauseAfterRoll: Duration = .milliseconds(700)
    static let remotePauseAfterHold: Duration = .milliseconds(600)
    static let remotePauseAfterCommit: Duration = .milliseconds(1500)

    private func remotePause(_ duration: Duration) async {
        guard !reduceMotion else { return }
        try? await Task.sleep(for: duration)
    }

    /// 상대가 보낸 로그에서 내가 모르는 이벤트만 검증하며 재생한다.
    /// 굴림은 3D로 보여주고, 고정·기록은 적용한 뒤 잠깐 멈춰 눈으로 따라올 시간을 준다.
    private func replay(remote update: RemoteUpdate) async {
        let log = update.log
        // 상대의 힌트를 합친다 (같은 이벤트 번호는 하나만)
        for hint in update.hints where !throwHints.contains(where: { $0.event == hint.event }) {
            throwHints.append(hint)
        }
        let mine = record.log.events
        guard log.playerCount == record.log.playerCount,
              log.events.count > mine.count,
              Array(log.events.prefix(mine.count)) == mine
        else {
            if log.events.count > mine.count { lastTransportError = "상대의 기록이 내 기록과 어긋난다" }
            return
        }
        for (offset, event) in log.events.dropFirst(mine.count).enumerated() {
            let eventIndex = mine.count + offset
            guard visibleState.canApply(event) else {
                lastTransportError = "상대가 보낸 이벤트가 규칙에 맞지 않는다: \(event)"
                return
            }
            isBusy = true
            switch event {
            case .rolled(let values):
                let slots = visibleState.rollableIndices
                let hint = throwHints.first { $0.event == eventIndex }
                _ = await stage.roll(values: values, slots: slots,
                                     direction: ThrowDirection.allCases.randomElement() ?? .center,
                                     skipAnimation: reduceMotion, hint: hint,
                                     onCue: { [weak self] cue in self?.onCollisionCue?(cue) })
                record.log.append(event)
                visibleState = visibleState.applying(event)
                await remotePause(Self.remotePauseAfterRoll)
            case .holdToggled:
                record.log.append(event)
                visibleState = visibleState.applying(event)
                stage.placeHeld(visibleState.held.sorted(), values: visibleState.dice)
                onHoldToggled?()
                await remotePause(Self.remotePauseAfterHold)
            case .committed(let category, let points):
                let seat = visibleState.currentPlayer
                record.log.append(event)
                visibleState = visibleState.applying(event)
                onCommitted?(category, points, false)
                lastOpponentCommit = OpponentCommit(seat: seat, category: category, points: points)
                await remotePause(Self.remotePauseAfterCommit)
            case .gameEnded:
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
        let outcome = await stage.roll(values: values, slots: slots,
                                       direction: direction, skipAnimation: reduceMotion,
                                       onCue: { [weak self] cue in self?.onCollisionCue?(cue) })
        onCollisionCues?(outcome.cues)

        // 착지한 뒤에 노출한다. 이 굴림의 이벤트 번호에 힌트를 매긴다.
        throwHints.append(ThrowHint(event: record.log.events.count, trajectory: outcome.trajectoryID,
                                    direction: outcome.direction.rawValue, yaws: outcome.yaws))
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
