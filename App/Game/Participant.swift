import Foundation
import YachtCore
import YachtBot

/// 좌석 하나. 순서는 GameState.currentPlayer와 같다.
enum Participant: Codable, Equatable, Sendable {
    case human(name: String)
    case bot(BotDifficulty)
    /// 다른 기기의 사람. P3(온라인)에서 채운다.
    case remote(playerID: String, name: String)

    var displayName: String {
        switch self {
        case .human(let name): name
        case .bot(let difficulty): "컴퓨터 (\(difficulty.displayName))"
        case .remote(_, let name): name
        }
    }

    var isHuman: Bool {
        if case .human = self { return true }
        return false
    }
}

enum GameMode: Codable, Equatable, Sendable {
    case solo
    case versusBot(BotDifficulty)
    case passAndPlay(names: [String])
    case online(matchID: String)

    /// 이 모드의 좌석 배치. 온라인은 매치가 잡힌 뒤에야 알 수 있어 비어 있다.
    var participants: [Participant] {
        switch self {
        case .solo: [.human(name: "나")]
        case .versusBot(let difficulty): [.human(name: "나"), .bot(difficulty)]
        case .passAndPlay(let names): names.map { .human(name: $0) }
        case .online: []
        }
    }

    /// 다른 기기의 사람과 겨루는 모드인가. 결과 문구가 "승리/패배"인지 "누구 승리"인지를 가른다.
    var isOnline: Bool {
        if case .online = self { true } else { false }
    }

    var title: String {
        switch self {
        case .solo: "혼자 연습"
        case .versusBot(let difficulty): "컴퓨터 대전 · \(difficulty.displayName)"
        case .passAndPlay(let names): "\(names.count)인 대전"
        case .online: "온라인 대전"
        }
    }
}

/// 저장·복원의 단위. 로그만으로는 상대가 누구였는지 알 수 없다.
struct MatchRecord: Codable, Equatable, Sendable {
    static let formatVersion = 3

    var formatVersion: Int
    /// "yacht", "omok", "cuppong", "alkkagi".
    var game: String
    var mode: GameMode
    var participants: [Participant]
    /// 요트 로그. 다른 게임이면 빈 로그다.
    var log: MatchLog
    /// 요트가 아닌 게임의 `MoveLog` JSON.
    var moveLog: Data?

    init(mode: GameMode) {
        let participants = mode.participants
        precondition(!participants.isEmpty, "참가자가 없는 모드로는 기록을 만들 수 없다: \(mode)")
        self.init(game: "yacht", mode: mode, participants: participants,
                  log: MatchLog(playerCount: participants.count), moveLog: nil)
    }

    init(mode: GameMode, participants: [Participant], log: MatchLog) {
        self.init(game: "yacht", mode: mode, participants: participants, log: log, moveLog: nil)
    }

    init(game: String, mode: GameMode, participants: [Participant], moveLog: Data) {
        self.init(game: game, mode: mode, participants: participants,
                  log: MatchLog(playerCount: participants.count), moveLog: moveLog)
    }

    private init(game: String, mode: GameMode, participants: [Participant], log: MatchLog, moveLog: Data?) {
        formatVersion = Self.formatVersion
        self.game = game
        self.mode = mode
        self.participants = participants
        self.log = log
        self.moveLog = moveLog
    }

    var isYacht: Bool { game == "yacht" }
    /// 끝났는가. 요트는 로그가, 다른 게임은 저장 전에 호출자가 `finished`를 판단해 `moveLog`를 nil로 두므로 여기서는 요트만 본다.
    var isFinished: Bool { isYacht ? log.isFinished : false }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        game = try c.decodeIfPresent(String.self, forKey: .game) ?? "yacht"
        mode = try c.decode(GameMode.self, forKey: .mode)
        participants = try c.decode([Participant].self, forKey: .participants)
        log = try c.decode(MatchLog.self, forKey: .log)
        moveLog = try c.decodeIfPresent(Data.self, forKey: .moveLog)
    }
}
