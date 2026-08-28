import Foundation

/// 이 모듈은 Foundation 외의 어떤 것도 import 하지 않는다.
/// SwiftUI·RealityKit·네트워크가 들어오는 순간 P3에서 코어를 재작성하게 된다.
public enum YachtCore {
    public static let diceCount = 5
    public static let maxRollsPerTurn = 3
    public static let turnCount = 12
    /// 로컬 패스앤플레이 최대 인원. 저장 파일에서 온 playerCount의 상한이기도 하다 —
    /// 상한이 없으면 손상된 파일의 큰 정수가 그대로 배열 할당으로 들어가 앱을 죽인다.
    public static let maxPlayers = 4
}
