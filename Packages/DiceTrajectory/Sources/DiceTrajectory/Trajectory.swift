import Foundation
import simd

public enum ThrowDirection: UInt8, CaseIterable, Sendable {
    case left = 0, center = 1, right = 2
}

public struct DiePose: Equatable, Sendable {
    public var position: SIMD3<Float>
    public var orientation: simd_quatf
    public init(position: SIMD3<Float>, orientation: simd_quatf) {
        self.position = position
        self.orientation = orientation
    }
}

public struct CollisionCue: Equatable, Sendable {
    public let frame: UInt16
    public let dieIndex: UInt8
    /// 0...1. 사운드 볼륨과 햅틱 세기에 쓴다.
    public let intensity: Float
    public init(frame: UInt16, dieIndex: UInt8, intensity: Float) {
        self.frame = frame
        self.dieIndex = dieIndex
        self.intensity = intensity
    }
}

/// 미리 구운 물리 궤적 하나.
public struct Trajectory: Equatable, Sendable {
    public let id: UInt16
    public let dieCount: Int
    public let direction: ThrowDirection
    public let frameRate: Int
    /// frames[프레임][주사위]
    public var frames: [[DiePose]]
    /// 각 주사위가 정지했을 때 위를 향한 눈 (1...6).
    /// 회전 오프셋은 이 값에만 의존하므로 정지 자세 전체를 따로 저장할 필요가 없다 (스펙 §7.3).
    /// 정수라 양자화 손실이 없고, 정지 자세 자체는 마지막 프레임이 이미 갖고 있다.
    public let restUpFaces: [UInt8]
    public let collisions: [CollisionCue]

    public init(id: UInt16, dieCount: Int, direction: ThrowDirection, frameRate: Int,
                frames: [[DiePose]], restUpFaces: [UInt8], collisions: [CollisionCue]) {
        self.id = id
        self.dieCount = dieCount
        self.direction = direction
        self.frameRate = frameRate
        self.frames = frames
        self.restUpFaces = restUpFaces
        self.collisions = collisions
    }

    public var frameCount: Int { frames.count }

    public func restUpFace(die: Int) -> Int { Int(restUpFaces[die]) }

    /// 오프셋을 적용한 프레임 자세. 위치는 건드리지 않는다.
    public func posed(die: Int, frame: Int, offset: simd_quatf) -> DiePose {
        let raw = frames[frame][die]
        return DiePose(position: raw.position,
                       orientation: FaceControl.apply(offset, to: raw.orientation))
    }
}
