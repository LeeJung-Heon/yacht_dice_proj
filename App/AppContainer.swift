import Foundation
import GameCore
import Observation
import YachtCore

/// 앱 조립을 한 곳에 모은다. 씬(DiceStage)은 무겁고 게임마다 같으므로 한 번만 만든다.
@MainActor
@Observable
final class AppContainer {
    enum Status {
        case hub
        case menu(GameID)
        case playing(GameSession)
        case playingOmok(OnlineMatch<Omok>)
        case playingCupPong(OnlineMatch<CupPong>)
        case playingAlkkagi(OnlineMatch<Alkkagi>)
        case failed(String)
    }

    private(set) var status: Status
    /// 메뉴의 "이어하기"에 보여줄 저장된 판.
    private(set) var savedRecord: MatchRecord?

    private let store: MatchStore
    private let stage: DiceStage?
    let gameCenter: GameCenterService
    let supabase: SupabaseService
    let records: RecordsStore
    /// UI 테스트는 GameKit 로그인 창이 뜨면 진행하지 못한다. `-noGameCenter`면 인증을 건너뛴다.
    private let skipGameCenter: Bool
    /// 로그인·신원 잇기를 이미 마쳤는가. 허브는 돌아올 때마다 `bootstrap()`을 부른다.
    private var bootstrapped = false
    /// 온라인 매치를 열지 못한 이유. 온라인 메뉴가 보여준다.
    private(set) var onlineError: String?

    var currentStage: DiceStage? { stage }

    init(store: MatchStore = .default,
         arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.store = store
        let gameCenter = GameCenterService()
        let supabase = SupabaseService()
        self.gameCenter = gameCenter
        self.supabase = supabase
        self.records = RecordsStore(service: supabase, gameCenter: gameCenter)
        self.skipGameCenter = arguments.contains("-noGameCenter")
        // UI 테스트가 깨끗한 상태에서 시작할 수 있게 한다
        if arguments.contains("-resetMatch") {
            try? store.clear()
        }
        do {
            stage = DiceStage(library: try TrajectoryLibrary.bundled())
            status = .hub
        } catch {
            stage = nil
            status = .failed("주사위 데이터를 읽지 못했습니다: \(error)")
        }
        savedRecord = store.load()
        PushRegistration.shared.currentMatchID = { [weak self] in
            guard let self else { return nil }
            let mode: GameMode
            switch self.status {
            case .playing(let session): mode = session.record.mode
            case .playingOmok(let match): mode = match.mode
            case .playingCupPong(let match): mode = match.mode
            case .playingAlkkagi(let match): mode = match.mode
            default: return nil
            }
            guard case .online(let id) = mode else { return nil }
            return UUID(uuidString: id)
        }
        PushRegistration.shared.onOpenMatch = { [weak self] id in
            Task { await self?.openOnlineMatchID(id) }
        }
    }

    /// 허브가 뜰 때마다 부른다. 로그인과 신원 잇기는 처음 한 번뿐이고, 전적만 매번 다시 읽는다.
    /// Game Center 로그인은 선택이라 실패해도 나머지는 그대로 돈다.
    func bootstrap() async {
        if !bootstrapped {
            await supabase.signIn()
            if !skipGameCenter { await gameCenter.authenticate() }
            if let id = gameCenter.playerID, let name = gameCenter.displayName {
                await supabase.upsertProfile(player: id, name: name)
                if supabase.nickname.isEmpty { supabase.nickname = name }
            }
            bootstrapped = true
        }
        await records.reload()
    }

    /// 지금 보고 있는 게임. 허브에 있거나 열 수 없는 상태면 nil.
    var currentGame: GameID? {
        switch status {
        case .menu(let game): game
        case .playing: .yacht
        case .playingOmok: .omok
        case .playingCupPong: .cuppong
        case .playingAlkkagi: .alkkagi
        default: nil
        }
    }

    /// 허브에서 게임 하나를 고른다.
    func showMenu(_ game: GameID) {
        savedRecord = store.load()
        status = .menu(game)
    }

    func returnToHub() {
        stopCurrentGame()
        savedRecord = store.load()
        status = .hub
    }

    /// 푸시 알림을 탭했을 때. 행을 읽어 연다. 이미 그 판을 플레이 중이면 세션을 새로 만들지 않는다.
    func openOnlineMatchID(_ id: UUID) async {
        if case .playing(let session) = status, session.record.mode == .online(matchID: id.uuidString) { return }
        if case .playingOmok(let match) = status, match.mode == .online(matchID: id.uuidString) { return }
        if case .playingCupPong(let match) = status, match.mode == .online(matchID: id.uuidString) { return }
        if case .playingAlkkagi(let match) = status, match.mode == .online(matchID: id.uuidString) { return }
        await supabase.signIn()
        guard let row = try? await supabase.fetchMatch(id: id) else {
            onlineError = "매치를 읽지 못했다"
            return
        }
        openSupabaseMatch(row)
    }

    func startGame(mode: GameMode) {
        try? store.clear()
        savedRecord = nil
        launch(MatchRecord(mode: mode))
    }

    /// 저장된 판을 이어한다. v3부터 저장 파일이 요트 아닌 게임의 기록일 수 있어 게임별로 가른다.
    func resumeSavedGame() {
        guard let record = savedRecord ?? store.load() else { return }
        switch GameID(rawValue: record.game) {
        case .yacht: launch(record)
        case .omok: if !launchOmok(record, transport: nil) { discardSavedGame() }
        case .cuppong: if !launchCupPong(record, transport: nil) { discardSavedGame() }
        case .alkkagi: if !launchAlkkagi(record, transport: nil) { discardSavedGame() }
        default: return
        }
    }

    /// 열 수 없는 저장을 지우고 허브로 돌린다. 남겨 두면 눌러도 아무 일이 없는 "이어하기"가 계속 뜬다.
    private func discardSavedGame() {
        try? store.clear()
        savedRecord = nil
        status = .hub
    }

    func returnToMenu() {
        let game = currentGame ?? .yacht
        stopCurrentGame()
        savedRecord = store.load()
        status = .menu(game)
    }

    /// 한 기기에서 번갈아 두는 오목. 저장된 판은 새 판에 밀린다.
    func startOmokLocal(names: [String]) {
        try? store.clear()
        savedRecord = nil
        let participants: [Participant] = names.map { .human(name: $0) }
        let record = MatchRecord(game: Omok.id, mode: .passAndPlay(names: names), participants: participants,
                                 moveLog: (try? MoveLog<Omok>().encoded()) ?? Data())
        if !launchOmok(record, transport: nil) { discardSavedGame() }
    }

    /// 기록을 읽어 오목 판을 연다. 규칙에 어긋나는 로그면 열지 않고 이유를 남긴 채 거짓이다.
    @discardableResult
    private func launchOmok(_ record: MatchRecord, transport: (any TurnTransport)?) -> Bool {
        guard let data = record.moveLog, let log = try? MoveLog<Omok>.decoded(from: data) else {
            onlineError = "오목 기록을 읽을 수 없다"
            return false
        }
        // 좌석 수가 어긋난 기록은 `OnlineMatch`의 precondition에 걸려 앱이 죽는다. 여기서 돌려보낸다.
        guard record.participants.count == Omok.seatCount else {
            onlineError = "오목 기록의 자리 수가 맞지 않다"
            return false
        }
        let match = OnlineMatch(game: Omok.self, mode: record.mode, participants: record.participants, log: log, transport: transport)
        match.onFinished = { [weak self] in Task { await self?.records.reload() } }
        if transport == nil {
            let store = store
            var saved = record
            match.onLogChanged = { data in
                if let data { saved.moveLog = data; try? store.save(saved) } else { try? store.clear() }
            }
        } else {
            match.startListening()
        }
        stopCurrentGame()
        status = .playingOmok(match)
        return true
    }

    /// 한 기기에서 번갈아 던지는 컵퐁. 저장된 판은 새 판에 밀린다.
    func startCupPongLocal(names: [String]) {
        try? store.clear()
        savedRecord = nil
        let participants: [Participant] = names.map { .human(name: $0) }
        let record = MatchRecord(game: CupPong.id, mode: .passAndPlay(names: names), participants: participants,
                                 moveLog: (try? MoveLog<CupPong>().encoded()) ?? Data())
        if !launchCupPong(record, transport: nil) { discardSavedGame() }
    }

    /// 기록을 읽어 컵퐁 판을 연다. 규칙에 어긋나는 로그면 열지 않고 이유를 남긴 채 거짓이다.
    @discardableResult
    private func launchCupPong(_ record: MatchRecord, transport: (any TurnTransport)?) -> Bool {
        guard let data = record.moveLog, let log = try? MoveLog<CupPong>.decoded(from: data) else {
            onlineError = "컵퐁 기록을 읽을 수 없다"
            return false
        }
        // 좌석 수가 어긋난 기록은 `OnlineMatch`의 precondition에 걸려 앱이 죽는다. 여기서 돌려보낸다.
        guard record.participants.count == CupPong.seatCount else {
            onlineError = "컵퐁 기록의 자리 수가 맞지 않다"
            return false
        }
        let match = OnlineMatch(game: CupPong.self, mode: record.mode, participants: record.participants, log: log, transport: transport)
        match.onFinished = { [weak self] in Task { await self?.records.reload() } }
        if transport == nil {
            let store = store
            var saved = record
            match.onLogChanged = { data in
                if let data { saved.moveLog = data; try? store.save(saved) } else { try? store.clear() }
            }
        } else {
            match.startListening()
        }
        stopCurrentGame()
        status = .playingCupPong(match)
        return true
    }

    /// 한 기기에서 번갈아 튕기는 알까기. 저장된 판은 새 판에 밀린다.
    func startAlkkagiLocal(names: [String]) {
        try? store.clear()
        savedRecord = nil
        let participants: [Participant] = names.map { .human(name: $0) }
        let record = MatchRecord(game: Alkkagi.id, mode: .passAndPlay(names: names), participants: participants,
                                 moveLog: (try? MoveLog<Alkkagi>().encoded()) ?? Data())
        if !launchAlkkagi(record, transport: nil) { discardSavedGame() }
    }

    /// 기록을 읽어 알까기 판을 연다. 규칙에 어긋나는 로그면 열지 않고 이유를 남긴 채 거짓이다.
    @discardableResult
    private func launchAlkkagi(_ record: MatchRecord, transport: (any TurnTransport)?) -> Bool {
        guard let data = record.moveLog, let log = try? MoveLog<Alkkagi>.decoded(from: data) else {
            onlineError = "알까기 기록을 읽을 수 없다"
            return false
        }
        // 좌석 수가 어긋난 기록은 `OnlineMatch`의 precondition에 걸려 앱이 죽는다. 여기서 돌려보낸다.
        guard record.participants.count == Alkkagi.seatCount else {
            onlineError = "알까기 기록의 자리 수가 맞지 않다"
            return false
        }
        let match = OnlineMatch(game: Alkkagi.self, mode: record.mode, participants: record.participants, log: log, transport: transport)
        match.onFinished = { [weak self] in Task { await self?.records.reload() } }
        if transport == nil {
            let store = store
            var saved = record
            match.onLogChanged = { data in
                if let data { saved.moveLog = data; try? store.save(saved) } else { try? store.clear() }
            }
        } else {
            match.startListening()
        }
        stopCurrentGame()
        status = .playingAlkkagi(match)
        return true
    }

    /// Supabase 행으로 게임을 연다. 게스트가 아직 없는 대기 방은 열지 않는다.
    @discardableResult
    func openSupabaseMatch(_ row: MatchRow) -> Bool {
        guard let uid = supabase.uid else {
            onlineError = "로그인되지 않았다"
            return false
        }
        return openSupabaseMatch(row, localUid: uid,
                                 transport: SupabaseTurnTransport(client: supabase.client, matchID: row.id))
    }

    /// 테스트가 전송을 바꿔 끼울 수 있는 핵심. `row.game`으로 요트와 오목을 가른다.
    @discardableResult
    func openSupabaseMatch(_ row: MatchRow, localUid: UUID, transport: any TurnTransport) -> Bool {
        guard row.guestUid != nil else { onlineError = "상대가 아직 들어오지 않았다"; return false }
        switch GameID(rawValue: row.game) {
        case .yacht:
            return openOnlineMatch(matchID: row.id.uuidString, localID: localUid.uuidString,
                                   players: row.seats(localUid: localUid), matchData: row.log, transport: transport)
        case .omok:
            if case .playingOmok(let match) = status, match.mode == .online(matchID: row.id.uuidString) { return true }
            let participants = seatParticipants(localID: localUid.uuidString, players: row.seats(localUid: localUid))
            guard participants.contains(where: \.isHuman) else { onlineError = "이 매치에 내 자리가 없습니다"; return false }
            onlineError = nil
            return launchOmok(MatchRecord(game: Omok.id, mode: .online(matchID: row.id.uuidString),
                                          participants: participants, moveLog: row.log),
                              transport: transport)
        case .cuppong:
            if case .playingCupPong(let match) = status, match.mode == .online(matchID: row.id.uuidString) { return true }
            let participants = seatParticipants(localID: localUid.uuidString, players: row.seats(localUid: localUid))
            guard participants.contains(where: \.isHuman) else { onlineError = "이 매치에 내 자리가 없습니다"; return false }
            onlineError = nil
            return launchCupPong(MatchRecord(game: CupPong.id, mode: .online(matchID: row.id.uuidString),
                                             participants: participants, moveLog: row.log),
                                 transport: transport)
        case .alkkagi:
            if case .playingAlkkagi(let match) = status, match.mode == .online(matchID: row.id.uuidString) { return true }
            let participants = seatParticipants(localID: localUid.uuidString, players: row.seats(localUid: localUid))
            guard participants.contains(where: \.isHuman) else { onlineError = "이 매치에 내 자리가 없습니다"; return false }
            onlineError = nil
            return launchAlkkagi(MatchRecord(game: Alkkagi.id, mode: .online(matchID: row.id.uuidString),
                                             participants: participants, moveLog: row.log),
                                 transport: transport)
        default:
            onlineError = "아직 지원하지 않는 게임이다: \(row.game)"
            return false
        }
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
        session.onFinished = { [weak self] in Task { await self?.records.reload() } }
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
        stopCurrentGame()
        status = .playing(session)
    }

    /// 지금 열려 있는 판의 수신·재생 루프를 접는다. 화면을 떠난 세션이 계속 서버를 듣고 있으면
    /// 새 판과 함께 두 세션이 같은 매치를 재생하고, 봇은 보이지 않는 곳에서 턴을 이어 둔다.
    private func stopCurrentGame() {
        switch status {
        case .playing(let session): session.stop()
        case .playingOmok(let match): match.stop()
        case .playingCupPong(let match): match.stop()
        case .playingAlkkagi(let match): match.stop()
        default: break
        }
    }
}
