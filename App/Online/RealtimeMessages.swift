import Foundation

/// 채널 `match:<id>`의 클라이언트 브로드캐스트 `move`. DB를 기다리지 않고 먼저 가는 확정된 수다.
/// 로그는 base64가 아니라 JSON 그대로 실어, DB 브로드캐스트의 `record`와 같은 모양을 받는 쪽이 같은 길로 읽는다.
struct MoveMessage: Codable, Equatable {
    let log: JSONValue
    let eventCount: Int
    let hints: [ThrowHint]

    enum CodingKeys: String, CodingKey {
        case log
        case eventCount = "event_count"
        case hints = "throws"
    }

    init(_ payload: TurnPayload) throws {
        log = try JSONDecoder().decode(JSONValue.self, from: payload.log)
        eventCount = payload.eventCount
        hints = payload.hints
    }

    func remoteUpdate() throws -> RemoteUpdate {
        RemoteUpdate(log: try JSONEncoder().encode(log), eventCount: eventCount, hints: hints)
    }
}

/// 채널의 클라이언트 브로드캐스트 `emoji`. 게임 중에 보내는 이모지 반응이다.
struct ReactionMessage: Codable, Equatable {
    let emoji: String
    let eventCount: Int

    enum CodingKeys: String, CodingKey {
        case emoji
        case eventCount = "event_count"
    }

    init(_ reaction: Reaction) {
        emoji = reaction.emoji
        eventCount = reaction.eventCount
    }

    var reaction: Reaction { Reaction(emoji: emoji, eventCount: eventCount) }
}

/// 채널의 클라이언트 브로드캐스트 `live`. 확정 전의 손놀림이며 상태는 게임별 JSON 그대로다.
struct LiveMessage: Codable, Equatable {
    let eventCount: Int
    /// nil이면 손을 뗐다는 뜻이다. 키가 없거나 null이면 nil로 읽는다.
    let state: JSONValue?

    enum CodingKeys: String, CodingKey {
        case eventCount = "event_count"
        case state
    }

    init(_ frame: LiveFrame) throws {
        eventCount = frame.eventCount
        state = try frame.state.map { try JSONDecoder().decode(JSONValue.self, from: $0) }
    }

    func frame() throws -> LiveFrame {
        LiveFrame(eventCount: eventCount, state: try state.map { try JSONEncoder().encode($0) })
    }
}
