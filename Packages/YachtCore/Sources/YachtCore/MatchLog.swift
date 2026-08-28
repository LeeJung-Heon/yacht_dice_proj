import Foundation

/// 한 판의 이벤트 로그. 저장·복원·리플레이·(P3의) 재접속이 전부 이것 하나로 처리된다.
public struct MatchLog: Equatable, Codable, Sendable {
    public static let formatVersion = 1

    public enum DecodingFailure: Error, Equatable {
        case unsupportedVersion(Int)
    }

    public private(set) var formatVersion: Int
    public private(set) var playerCount: Int
    public private(set) var events: [Event]

    public init(playerCount: Int) {
        self.formatVersion = Self.formatVersion
        self.playerCount = playerCount
        self.events = []
    }

    public mutating func append(_ event: Event) { events.append(event) }

    /// 매번 처음부터 접는다. 한 판은 최대 수백 이벤트라 비용이 문제되지 않는다.
    /// 캐시를 두면 캐시 무효화 버그가 리플레이 정확성을 갉아먹는다.
    public var state: GameState { GameState.replaying(events, playerCount: playerCount) }

    public var isFinished: Bool { state.phase == .finished }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> MatchLog {
        let log = try JSONDecoder().decode(MatchLog.self, from: data)
        guard log.formatVersion == Self.formatVersion else {
            throw DecodingFailure.unsupportedVersion(log.formatVersion)
        }
        return log
    }
}
