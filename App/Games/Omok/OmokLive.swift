import GameCore

/// 오목의 순간 상태는 상대가 고른(아직 놓지 않은) 교차점 하나이며 값은 `Omok.Move` 그대로다.
enum OmokLive {
    /// 받은 자리를 지금 판에 그려도 되면 그 자리를 준다. 상대가 보낸 입력이라 판 밖이거나 돌 위면 버린다.
    static func remotePreview(_ move: Omok.Move?, in state: Omok.State) -> Omok.Move? {
        guard let move, (0..<Omok.size).contains(move.x), (0..<Omok.size).contains(move.y),
              state.stone(x: move.x, y: move.y) == 0 else { return nil }
        return move
    }
}
