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
    private var hints: [ThrowHint] = []

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

    func startListening() {
        guard let transport, listenTask == nil else { return }
        listenTask = Task { [weak self] in
            for await update in transport.incoming {
                guard let self else { return }
                let previous = replayTask
                replayTask = Task { @MainActor in
                    await previous?.value
                    await self.replay(update)
                }
            }
        }
        let remoteID = participants.compactMap { if case .remote(let id, _) = $0 { id } else { nil } }.first
        presenceTask = Task { [weak self] in
            for await present in transport.presence {
                self?.opponentPresent = remoteID.map { present.contains($0) } ?? !present.isEmpty
            }
        }
        connectionTask = Task { [weak self] in
            for await connected in transport.connection { self?.isConnected = connected }
        }
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
