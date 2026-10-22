import Foundation
import GameCore

/// 알까기의 순간 상태. 튕길 때는 잡은 돌과 손끝을, 배치할 때는 초안과 끄는 돌을 보낸다. 좌표는 모두 판 좌표다.
enum AlkkagiLive: Codable, Equatable {
    case pull(stone: Int, to: Alkkagi.Point)
    case setup(draft: [Alkkagi.Point], dragging: Dragging?)

    struct Dragging: Codable, Equatable {
        let stone: Int
        let at: Alkkagi.Point
    }

    /// 받은 좌표가 들어올 수 있는 범위. 손끝은 판 가장자리 너머까지 끌 수 있어 판 한 변만큼 둘레를 둔다.
    /// 이보다 먼 값은 조작된 것이고, 그대로 쓰면 당김 계산의 제곱이 Int를 넘쳐 앱이 멈춘다.
    static let reach = -Alkkagi.boardMax...(2 * Alkkagi.boardMax)

    private static func isReachable(_ point: Alkkagi.Point) -> Bool {
        reach.contains(point.x) && reach.contains(point.y)
    }

    /// 받은 당김을 지금 판에서 그릴 수 있으면 돌 번호와 그 돌의 자리, 손끝을 준다.
    /// 상대가 보낸 입력이라 플레이 단계가 아니거나 돌 번호가 범위 밖이거나 그 돌이 판에 없거나 손끝이 터무니없이 멀면 버린다.
    func aim(in state: Alkkagi.State) -> (stone: Int, from: Alkkagi.Point, to: Alkkagi.Point)? {
        guard case .pull(let stone, let to) = self, state.phase == .play,
              (0..<Alkkagi.stonesPerSeat).contains(stone), let seat = Alkkagi.currentSeat(state),
              state.stones.indices.contains(seat), state.stones[seat].indices.contains(stone),
              let from = state.stones[seat][stone], Self.isReachable(to) else { return nil }
        return (stone, from, to)
    }

    /// 받은 배치 초안을 그릴 수 있으면 준다. 돌이 다섯이 아니거나 끄는 돌 번호가 범위 밖이거나 좌표가 터무니없이 멀면 버린다.
    func draft() -> (points: [Alkkagi.Point], dragging: Dragging?)? {
        guard case .setup(let points, let dragging) = self, points.count == Alkkagi.stonesPerSeat,
              points.allSatisfy(Self.isReachable) else { return nil }
        if let dragging, !(0..<Alkkagi.stonesPerSeat).contains(dragging.stone) || !Self.isReachable(dragging.at) { return nil }
        return (points, dragging)
    }
}

/// 초당 10번 오는 상대의 손끝을 끊기지 않게 잇는다. 새 값이 오면 그 시각에 보이던 자리에서 새 값까지 100ms 동안 곧게 간다.
/// 순수 값이라 테스트한다.
struct AlkkagiLiveTrack: Equatable {
    static let duration: TimeInterval = 0.1
    private(set) var from: Alkkagi.Point
    private(set) var to: Alkkagi.Point
    private(set) var start: Date

    init(_ point: Alkkagi.Point, at date: Date) {
        from = point; to = point; start = date
    }

    mutating func update(_ point: Alkkagi.Point, at date: Date) {
        from = self.point(at: date)
        to = point
        start = date
    }

    func point(at date: Date) -> Alkkagi.Point {
        let t = min(max(date.timeIntervalSince(start) / Self.duration, 0), 1)
        return Alkkagi.Point(x: from.x + Int((Double(to.x - from.x) * t).rounded()),
                             y: from.y + Int((Double(to.y - from.y) * t).rounded()))
    }

    func isMoving(at date: Date) -> Bool { from != to && date.timeIntervalSince(start) < Self.duration }
}
