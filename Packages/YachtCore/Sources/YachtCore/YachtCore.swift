import Foundation

/// 이 모듈은 Foundation 외의 어떤 것도 import 하지 않는다.
/// SwiftUI·RealityKit·네트워크가 들어오는 순간 P3에서 코어를 재작성하게 된다.
public enum YachtCore {
    public static let diceCount = 5
    public static let maxRollsPerTurn = 3
    public static let turnCount = 12
}
