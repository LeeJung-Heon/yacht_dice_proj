import Foundation
import GameKit
import Observation
import YachtCore

/// 앱 조립을 한 곳에 모은다. 씬(DiceStage)은 무겁고 게임마다 같으므로 한 번만 만든다.
@MainActor
@Observable
final class AppContainer {
    enum Status {
        case menu
        case playing(GameSession)
        case failed(String)
    }

    private(set) var status: Status
    /// 메뉴의 "이어하기"에 보여줄 저장된 판.
    private(set) var savedRecord: MatchRecord?

    private let store: MatchStore
    private let stage: DiceStage?
    let gameCenter = GameCenterService()
    /// 온라인 매치를 열지 못한 이유. 온라인 메뉴가 보여준다.
    private(set) var onlineError: String?

    var currentStage: DiceStage? { stage }

    init(store: MatchStore = .default,
         arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.store = store
        // UI 테스트가 깨끗한 상태에서 시작할 수 있게 한다
        if arguments.contains("-resetMatch") {
            try? store.clear()
        }
        do {
            stage = DiceStage(library: try TrajectoryLibrary.bundled())
            status = .menu
        } catch {
            stage = nil
            status = .failed("주사위 데이터를 읽지 못했습니다: \(error)")
        }
        savedRecord = store.load()
        gameCenter.onMatchOpened = { [weak self] match in self?.startOnlineMatch(match) }
    }

    func startGame(mode: GameMode) {
        try? store.clear()
        savedRecord = nil
        launch(MatchRecord(mode: mode))
    }

    func resumeSavedGame() {
        guard let record = savedRecord ?? store.load() else { return }
        launch(record)
    }

    func returnToMenu() {
        savedRecord = store.load()
        status = .menu
    }

    /// Game Center 매치로 게임을 시작하거나 이어간다. 진행 상태의 원본은 매치 데이터라 로컬에 저장하지 않는다.
    func startOnlineMatch(_ match: GKTurnBasedMatch) {
        let players = match.participants.map { SeatPlayer(id: $0.player?.gamePlayerID, name: $0.player?.displayName) }
        _ = openOnlineMatch(matchID: match.matchID, localID: gameCenter.localPlayerID, players: players,
                            matchData: match.matchData,
                            transport: GameCenterTurnTransport(match: match, service: gameCenter))
    }

    /// GameKit 객체 없이 테스트할 수 있는 핵심. 성공하면 참.
    ///
    /// 이미 같은 매치를 플레이 중이면(알림으로 앱이 다시 열린 경우) 세션을 새로 만들지 않는다 —
    /// 새 로그는 transport 스트림으로 들어오고 있는 세션이 재생한다.
    @discardableResult
    func openOnlineMatch(matchID: String, localID: String, players: [SeatPlayer],
                         matchData: Data?, transport: any TurnTransport) -> Bool {
        if case .playing(let session) = status, session.record.mode == .online(matchID: matchID) {
            return true
        }
        let participants = seatParticipants(localID: localID, players: players)
        guard participants.contains(where: \.isHuman) else {
            onlineError = "이 매치에 내 자리가 없습니다"
            return false
        }
        let log: MatchLog
        if let data = matchData, !data.isEmpty {
            guard let decoded = try? MatchLog.decoded(from: data), decoded.playerCount == participants.count else {
                onlineError = "매치 데이터를 읽을 수 없습니다"
                return false
            }
            log = decoded
        } else {
            log = MatchLog(playerCount: participants.count)
        }
        onlineError = nil
        let record = MatchRecord(mode: .online(matchID: matchID), participants: participants, log: log)
        launch(record, transport: transport)
        return true
    }

    private func launch(_ record: MatchRecord, transport: (any TurnTransport)? = nil) {
        guard let stage else { return }
        stage.reset()
        let session = GameSession(driver: LocalDriver(), stage: stage, record: record, transport: transport)
        if transport == nil {
            let store = store
            session.onLogChanged = { record in try? store.save(record) }
        } else {
            session.startListening()
        }

        // 복원한 판이면 주사위를 마지막 상태로 앉힌다. 그림은 즉시 확정되지만
        // roll()이 async라 한 틱 뒤에 실행된다 — 첫 입력보다는 항상 먼저다.
        let state = record.log.state
        if state.phase == .rolling {
            Task { @MainActor in
                _ = await stage.roll(values: state.dice, slots: Array(0..<YachtCore.diceCount),
                                     direction: .center, skipAnimation: true)
                stage.placeHeld(state.held.sorted(), values: state.dice)
                session.resumeTurnOwner()
            }
        } else {
            session.resumeTurnOwner()
        }
        status = .playing(session)
    }
}
