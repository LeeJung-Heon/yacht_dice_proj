import Foundation
import GameCore
import Observation

/// 요트가 아닌 게임의 세션. 로그·검증·전송·원격 재생·접속 상태를 맡고, 화면은 `onRemoteMove`로 상대 수를 그린다.
/// 로컬 2인은 전송이 nil인 같은 객체이며 수마다 좌석이 바뀐다.
@MainActor
@Observable
final class OnlineMatch<G: Game> {
    let mode: GameMode
    let participants: [Participant]
    private(set) var log: MoveLog<G>
    var state: G.State { log.state }
    var outcome: Outcome? { G.outcome(state) }

    /// 원격 재생 중이면 참. 입력을 잠근다.
    private(set) var isReplaying = false
    private(set) var opponentPresent = false
    private(set) var isConnected = true
    private(set) var lastTransportError: String?

    struct RemoteMove: Equatable {
        let id = UUID()
        let seat: Int
        let move: G.Move
    }
    /// 상대가 방금 둔 수. 화면이 팝업으로 알린다.
    private(set) var lastRemoteMove: RemoteMove?
    /// 상대가 지금 하고 있는 것(확정 전의 손놀림). 게임별 JSON이며, 내 로그와 같은 수 위의 것이고 재생 중이 아닐 때만 있다.
    /// 상대 수가 오면 그 전의 손놀림은 수가 맞지 않아 저절로 사라지고, 같은 좌석이 이어 두며 먼저 보낸 다음 수의 손놀림은
    /// 재생이 끝나 로그가 따라잡으면 그때 보인다.
    var remoteLive: Data? {
        guard let remoteFrame, remoteFrame.eventCount == log.moves.count, !isReplaying else { return nil }
        return remoteFrame.state
    }
    /// 받은 마지막 프레임. 내 로그보다 앞선 수의 것도 들고 있는다.
    private var remoteFrame: LiveFrame?

    /// 상대 수를 화면에서 재생한다. 끝날 때까지 다음 수를 넘기지 않는다.
    var onRemoteMove: (@MainActor (G.Move, ThrowHint?) async -> Void)?
    /// 로그가 바뀌었다. 로컬 판은 저장하고, 끝났으면 nil을 준다.
    var onLogChanged: (@MainActor (Data?) -> Void)?
    /// 판이 끝났다. 한 판에 한 번만 부른다 — 컨테이너가 전적을 다시 읽는다.
    var onFinished: (@MainActor () -> Void)?
    private var didNotifyFinished = false

    private let transport: (any TurnTransport)?
    private var listenTask: Task<Void, Never>?
    private var presenceTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var replayTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    private var hints: [ThrowHint] = []

    /// 순간 상태를 묶는 간격. 이보다 자주 바뀌면 간격이 찰 때 가장 최근 값만 보낸다.
    static var liveInterval: Duration { .milliseconds(100) }
    /// 키 순서를 고정한다. 같은 값이 인코딩마다 다른 바이트가 되면 "같은 값은 다시 보내지 않는다"가 깨진다.
    private static var liveEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
    /// 마지막으로 보낸 프레임과 그 시각. 같은 프레임은 다시 보내지 않는다.
    private var liveLastSent: LiveFrame?
    private var liveLastSentAt: ContinuousClock.Instant?
    /// 간격이 차기를 기다리는 가장 최근 값.
    private var livePending: LiveFrame?
    private var liveFlushTask: Task<Void, Never>?
    /// 보내기 사슬의 끝. 앞의 보내기가 끝난 뒤 이어 보내야 손을 뗀 nil이 앞선 당김보다 먼저 닿지 않는다.
    private var liveSendChain: Task<Void, Never>?

    init(game: G.Type, mode: GameMode, participants: [Participant], log: MoveLog<G>, transport: (any TurnTransport)?) {
        precondition(participants.count == G.seatCount)
        self.mode = mode
        self.participants = participants
        self.log = log
        self.transport = transport
    }

    /// 온라인이면 내 좌석, 로컬이면 지금 둘 좌석.
    var localSeat: Int? {
        if transport == nil { return G.currentSeat(state) }
        return participants.firstIndex(where: \.isHuman)
    }

    var isLocalTurn: Bool {
        guard !isReplaying, let seat = G.currentSeat(state), let mine = localSeat else { return false }
        return seat == mine
    }

    /// 수를 둔다. 내 차례가 아니거나 규칙에 어긋나면 거짓.
    @discardableResult
    func play(_ move: G.Move, hint: ThrowHint? = nil) async -> Bool {
        guard isLocalTurn, G.canApply(move, to: state) else { return false }
        // 둔 수 전의 손놀림은 끝났다. 들고 있던 값이 수 뒤에 나가지 않게 먼저 거둔다.
        withdrawLive()
        if let hint { hints.append(ThrowHint(event: log.moves.count, trajectory: hint.trajectory, direction: hint.direction, yaws: hint.yaws)) }
        log.append(move)
        notifyLogChanged()
        await publish()
        notifyFinishedIfNeeded()
        return true
    }

    /// 판이 끝났다고 한 번만 알린다. 서버에 결과를 올린 뒤에 부른다.
    private func notifyFinishedIfNeeded() {
        guard outcome != nil, !didNotifyFinished else { return }
        didNotifyFinished = true
        onFinished?()
    }

    func encodedLog() throws -> Data { try log.encoded() }

    // MARK: 순간 상태

    /// 내 손놀림을 상대에게 흘린다. 로컬 2인이거나 내 차례가 아니면 보내지 않는다.
    /// nil은 손을 뗐다는 뜻이라, 앞서 보낸 것이 있으면 차례와 무관하게 들고 있던 값을 버리고 바로 보낸다.
    func publishLive<L: Encodable>(_ state: L?) {
        guard transport != nil else { return }
        guard let state else { return withdrawLive() }
        guard isLocalTurn, let data = try? Self.liveEncoder.encode(state) else { return }
        let frame = LiveFrame(eventCount: log.moves.count, state: data)
        guard frame != liveLastSent else {
            // 들고 있던 값이 무엇이든 지금 보이는 것은 이미 보낸 그것이다.
            livePending = nil
            return
        }
        if let last = liveLastSentAt, ContinuousClock.now - last < Self.liveInterval {
            livePending = frame
            guard liveFlushTask == nil else { return }
            let wait = Self.liveInterval - (ContinuousClock.now - last)
            liveFlushTask = Task { [weak self] in
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled, let self else { return }
                self.liveFlushTask = nil
                guard let pending = self.livePending else { return }
                self.livePending = nil
                // 기다리는 사이 수가 바뀌었거나 차례가 넘어갔으면 지난 손놀림이다.
                guard pending.eventCount == self.log.moves.count, self.isLocalTurn else { return }
                self.sendLiveNow(pending)
            }
            return
        }
        sendLiveNow(frame)
    }

    /// 상대의 순간 상태를 게임의 타입으로 읽는다. 읽을 수 없으면 nil.
    func remoteLive<L: Decodable>(as type: L.Type) -> L? {
        remoteLive.flatMap { try? JSONDecoder().decode(L.self, from: $0) }
    }

    /// 들고 있던 값을 버리고, 앞서 보낸 손놀림이 있으면 nil로 거둔다.
    private func withdrawLive() {
        livePending = nil
        liveFlushTask?.cancel(); liveFlushTask = nil
        guard liveLastSent?.state != nil else { return }
        sendLiveNow(LiveFrame(eventCount: log.moves.count, state: nil))
    }

    private func sendLiveNow(_ frame: LiveFrame) {
        guard let transport else { return }
        liveLastSent = frame
        liveLastSentAt = .now
        let previous = liveSendChain
        liveSendChain = Task {
            await previous?.value
            await transport.sendLive(frame)
        }
    }

    /// 로그가 바뀌었다고 화면·저장소에 알린다. 끝났으면 nil(지우라는 뜻)을 준다.
    /// 인코딩이 실패하면 — 끝나지 않았는데도 — 알리지 않는다. 알리면 저장소가 그 nil을 "지워라"로 읽어
    /// 진행 중인 판을 잃기 때문이다. 대신 오류를 남긴다.
    private func notifyLogChanged() {
        guard outcome == nil else {
            onLogChanged?(nil)
            return
        }
        guard let encoded = try? log.encoded() else {
            lastTransportError = "기록을 저장하지 못했다"
            return
        }
        onLogChanged?(encoded)
    }

    private func publish() async {
        guard let transport else { return }
        do {
            let finished = outcome != nil
            var winner: Int? = nil
            if case .win(let seat) = outcome { winner = seat }
            try await transport.publish(TurnPayload(log: try log.encoded(), eventCount: log.moves.count, hints: hints,
                                                    turnSeat: G.currentSeat(state), winnerSeat: winner, finished: finished))
            lastTransportError = nil
        } catch {
            lastTransportError = "서버에 보내지 못해 다시 시도하는 중이다"
        }
    }

    /// 스트림에 이미 쌓여 있던 값은 취소된 Task에도 그대로 배달되므로, 루프마다 취소를 먼저 본다.
    func startListening() {
        guard let transport, listenTask == nil else { return }
        listenTask = Task { [weak self] in
            for await update in transport.incoming {
                if Task.isCancelled { return }
                guard let self else { return }
                let previous = replayTask
                replayTask = Task { @MainActor in
                    await previous?.value
                    if Task.isCancelled { return }
                    await self.replay(update)
                }
            }
        }
        let remoteID = participants.compactMap { if case .remote(let id, _) = $0 { id } else { nil } }.first
        presenceTask = Task { [weak self] in
            for await present in transport.presence {
                if Task.isCancelled { return }
                guard let self else { return }
                self.opponentPresent = remoteID.map { present.contains($0) } ?? !present.isEmpty
                // 떠난 상대의 손놀림은 그대로 멈춰 남지 않게 거둔다.
                if !self.opponentPresent { self.remoteFrame = nil }
            }
        }
        connectionTask = Task { [weak self] in
            for await connected in transport.connection {
                if Task.isCancelled { return }
                guard let self else { return }
                self.isConnected = connected
                if !connected { self.remoteFrame = nil }
            }
        }
        liveTask = Task { [weak self] in
            for await frame in transport.live {
                if Task.isCancelled { return }
                guard let self else { return }
                // 내 로그보다 뒤처진 수 위의 것은 늦게 온 지난 차례의 손놀림이다. 앞선 것은 재생이 따라잡을 때까지 들고 있는다.
                guard frame.eventCount >= self.log.moves.count else { continue }
                self.remoteFrame = frame
            }
        }
    }

    /// 이 판을 접는다. 화면을 떠난 세션이 계속 수신·재생하며 살아 있지 않도록 컨테이너가 부른다.
    /// 다시 `startListening()`을 부르면 처음처럼 새 루프가 뜬다.
    func stop() {
        // 끌던 손놀림이 상대 화면에 멈춰 남지 않게 먼저 거둔다. 보내기 사슬은 끊지 않는다.
        withdrawLive()
        listenTask?.cancel(); listenTask = nil
        presenceTask?.cancel(); presenceTask = nil
        connectionTask?.cancel(); connectionTask = nil
        replayTask?.cancel(); replayTask = nil
        liveTask?.cancel(); liveTask = nil
        remoteFrame = nil
    }

    func resync() async { await transport?.refresh() }

    /// 상대 로그에서 내가 모르는 수만 검증하며 하나씩 재생한다.
    private func replay(_ update: RemoteUpdate) async {
        for hint in update.hints where !hints.contains(where: { $0.event == hint.event }) { hints.append(hint) }
        guard let theirs = try? MoveLog<G>.decoded(from: update.log) else {
            lastTransportError = "상대의 기록을 읽을 수 없다"
            return
        }
        let mine = log.moves
        guard theirs.moves.count > mine.count, Array(theirs.moves.prefix(mine.count)) == mine else {
            if theirs.moves.count > mine.count { lastTransportError = "상대의 기록이 내 기록과 어긋난다" }
            return
        }
        isReplaying = true
        defer { isReplaying = false }
        // 상대의 마지막 수로 판이 끝났을 수 있다. 로그를 알린 뒤에 부르려고 먼저 선언한다.
        defer { notifyFinishedIfNeeded() }
        // 배치 일부만 받아들여도(뒤엣것이 조작이라 거부돼도) 그때까지 둔 수는 잃지 않는다.
        // isReplaying을 내리기 전에 알려야 화면이 재생 중 상태로 저장을 보므로, 이 defer를 나중에 선언해
        // "알림 → isReplaying = false" 순서를 만든다(defer는 선언의 역순으로 실행된다).
        var appended = false
        defer { if appended { notifyLogChanged() } }
        for (offset, move) in theirs.moves.dropFirst(mine.count).enumerated() {
            // 상대가 보낸 수는 상대 좌석의 것이어야 한다. 내 좌석 차례의 수가 오면 조작이다.
            guard let seat = G.currentSeat(state), seat != localSeat, G.canApply(move, to: state) else {
                lastTransportError = "상대가 보낸 수가 규칙에 맞지 않는다"
                return
            }
            let hint = hints.first { $0.event == mine.count + offset }
            await onRemoteMove?(move, hint)
            log.append(move)
            appended = true
            lastRemoteMove = RemoteMove(seat: seat, move: move)
        }
        lastTransportError = nil
    }

    /// 테스트용: 도착한 로그를 전부 재생할 때까지 기다린다(최대 2초).
    func waitForIncoming() async {
        let before = log.moves.count
        let deadline = ContinuousClock.now + .seconds(2)
        while replayTask == nil || log.moves.count == before {
            if ContinuousClock.now > deadline || lastTransportError != nil { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        await replayTask?.value
    }
}
