import Foundation
import simd

/// 궤적 재생과 주사위 면 제어에 필요한 순수 수학·자료구조.
/// Foundation과 simd만 import한다. RealityKit이 들어오면 시뮬레이터 없이 테스트할 수 없게 된다.
public enum DiceTrajectory {
    public static let formatVersion: UInt16 = 1
}
