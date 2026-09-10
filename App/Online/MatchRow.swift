import Foundation
import YachtCore

/// `public.matches` 행. 서버 스키마와 1:1이다.
struct MatchRow: Codable, Equatable, Sendable {
    var id: UUID
    var code: String
    var hostUid: UUID
    var guestUid: UUID?
    var hostName: String
    var guestName: String?
    /// 원문 JSON. 게임마다 모양이 달라 전송·저장 계층은 이 로그를 모른 채 그대로 나른다.
    var log: Data
    var eventCount: Int
    var status: String
    var totals: [Int]?
    /// 굴림마다의 궤적 힌트. 열 이름은 `throws`.
    var hints: [ThrowHint] = []
    /// 다음에 둘 좌석. 끝났거나 대기 중이면 nil.
    var turnSeat: Int?
    /// 어떤 게임인지. `Packages/GameCore`의 `Game.id`와 같다.
    var game: String = "yacht"
    /// 호스트·게스트가 고른 게임별 플레이어(예: 오목의 돌 색). 요트는 쓰지 않는다.
    var hostPlayer: String?
    var guestPlayer: String?
    /// 끝났을 때의 승자 좌석. 무승부나 진행 중이면 nil.
    var winnerSeat: Int?

    enum CodingKeys: String, CodingKey {
        case id, code, log, status, totals, game
        case hostUid = "host_uid", guestUid = "guest_uid"
        case hostName = "host_name", guestName = "guest_name"
        case eventCount = "event_count"
        case hints = "throws"
        case turnSeat = "turn_seat"
        case hostPlayer = "host_player", guestPlayer = "guest_player"
        case winnerSeat = "winner_seat"
    }

    init(id: UUID, code: String, hostUid: UUID, guestUid: UUID?, hostName: String, guestName: String?,
         log: Data, eventCount: Int, status: String, totals: [Int]?, hints: [ThrowHint] = [], turnSeat: Int? = nil,
         game: String = "yacht", hostPlayer: String? = nil, guestPlayer: String? = nil, winnerSeat: Int? = nil) {
        self.id = id; self.code = code; self.hostUid = hostUid; self.guestUid = guestUid
        self.hostName = hostName; self.guestName = guestName; self.log = log; self.eventCount = eventCount
        self.status = status; self.totals = totals; self.hints = hints; self.turnSeat = turnSeat
        self.game = game; self.hostPlayer = hostPlayer; self.guestPlayer = guestPlayer; self.winnerSeat = winnerSeat
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        code = try c.decode(String.self, forKey: .code)
        hostUid = try c.decode(UUID.self, forKey: .hostUid)
        guestUid = try c.decodeIfPresent(UUID.self, forKey: .guestUid)
        hostName = try c.decode(String.self, forKey: .hostName)
        guestName = try c.decodeIfPresent(String.self, forKey: .guestName)
        // 서버가 jsonb를 객체로 주므로 그대로 다시 인코드해 원문 Data로 둔다. 게임별 디코드는 호출자가 한다.
        let raw = try c.decode(JSONValue.self, forKey: .log)
        log = try JSONEncoder().encode(raw)
        eventCount = try c.decode(Int.self, forKey: .eventCount)
        status = try c.decode(String.self, forKey: .status)
        totals = try c.decodeIfPresent([Int].self, forKey: .totals)
        hints = try c.decodeIfPresent([ThrowHint].self, forKey: .hints) ?? []
        turnSeat = try c.decodeIfPresent(Int.self, forKey: .turnSeat)
        game = try c.decodeIfPresent(String.self, forKey: .game) ?? "yacht"
        hostPlayer = try c.decodeIfPresent(String.self, forKey: .hostPlayer)
        guestPlayer = try c.decodeIfPresent(String.self, forKey: .guestPlayer)
        winnerSeat = try c.decodeIfPresent(Int.self, forKey: .winnerSeat)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(code, forKey: .code)
        try container.encode(hostUid, forKey: .hostUid)
        try container.encode(guestUid, forKey: .guestUid)
        try container.encode(hostName, forKey: .hostName)
        try container.encode(guestName, forKey: .guestName)
        try container.encode(JSONDecoder().decode(JSONValue.self, from: log), forKey: .log)
        try container.encode(eventCount, forKey: .eventCount)
        try container.encode(status, forKey: .status)
        try container.encode(totals, forKey: .totals)
        try container.encode(hints, forKey: .hints)
        try container.encode(turnSeat, forKey: .turnSeat)
        try container.encode(game, forKey: .game)
        try container.encode(hostPlayer, forKey: .hostPlayer)
        try container.encode(guestPlayer, forKey: .guestPlayer)
        try container.encode(winnerSeat, forKey: .winnerSeat)
    }

    var isWaiting: Bool { status == "waiting" }
    var isFinished: Bool { status == "finished" }
    var isAbandoned: Bool { status == "abandoned" }

    /// 좌석은 항상 [호스트, 게스트]. 내 uid가 어느 쪽인지로 human/remote를 정한다.
    func seats(localUid: UUID) -> [SeatPlayer] {
        [SeatPlayer(id: hostUid.uuidString, name: hostName),
         SeatPlayer(id: guestUid?.uuidString, name: guestName)]
    }

    /// 이 행의 로그를 요트 로그로 읽는다. 요트 행이 아니거나 디코드에 실패하면 nil.
    func yachtLog() -> MatchLog? { game == "yacht" ? try? MatchLog.decoded(from: log) : nil }

    /// 앱이 열 기록. 게스트가 없는 대기 방이거나 요트 행이 아니면 아직 열 수 없다.
    func record(localUid: UUID) -> MatchRecord? {
        guard let log = yachtLog(), guestUid != nil else { return nil }
        let participants = seatParticipants(localID: localUid.uuidString, players: seats(localUid: localUid))
        guard participants.contains(where: \.isHuman), log.playerCount == 2 else { return nil }
        return MatchRecord(mode: .online(matchID: id.uuidString), participants: participants, log: log)
    }

    /// 6자리 숫자 방 코드.
    static func makeCode(using generator: inout some RandomNumberGenerator) -> String {
        String(format: "%06d", Int.random(in: 0...999_999, using: &generator))
    }

    static func isValidCode(_ code: String) -> Bool {
        code.count == 6 && code.allSatisfy(\.isNumber)
    }
}

/// 어떤 JSON이든 잃지 않고 왕복한다. 서버 jsonb 열을 원문 Data로 두기 위해서다.
enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
