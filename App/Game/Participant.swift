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
    static let formatVersion = 2

    var formatVersion: Int
    var mode: GameMode
    var participants: [Participant]
    var log: MatchLog

    init(mode: GameMode) {
        let participants = mode.participants
        precondition(!participants.isEmpty, "참가자가 없는 모드로는 기록을 만들 수 없다: \(mode)")
        self.init(mode: mode, participants: participants, log: MatchLog(playerCount: participants.count))
    }

    init(mode: GameMode, participants: [Participant], log: MatchLog) {
        self.formatVersion = Self.formatVersion
        self.mode = mode
        self.participants = participants
        self.log = log
    }

    var isFinished: Bool { log.isFinished }
}
