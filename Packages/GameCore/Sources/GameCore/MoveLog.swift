import Foundation

/// 수 목록이 곧 판이다. 상태는 처음부터 다시 적용해 만들며, 디코드도 같은 길을 지나 신뢰 경계를 지킨다.
public struct MoveLog<G: Game>: Codable, Equatable, Sendable {
    public private(set) var moves: [G.Move]
    public private(set) var state: G.State

    public init() {
        moves = []
        state = G.initial()
    }

    /// 규칙에 맞으면 더하고 참, 아니면 그대로 두고 거짓.
    @discardableResult
    public mutating func append(_ move: G.Move) -> Bool {
        guard G.canApply(move, to: state) else { return false }
        moves.append(move)
        state = G.apply(move, to: state)
        return true
    }

    public var isFinished: Bool { G.outcome(state) != nil }

    enum CodingKeys: String, CodingKey { case moves }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let moves = try container.decode([G.Move].self, forKey: .moves)
        self.init()
        for (index, move) in moves.enumerated() {
            guard append(move) else {
                throw DecodingError.dataCorruptedError(forKey: .moves, in: container,
                                                       debugDescription: "\(index)번째 수를 적용할 수 없다")
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(moves, forKey: .moves)
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decoded(from data: Data) throws -> Self { try JSONDecoder().decode(Self.self, from: data) }
}
