import Foundation
import simd

/// 궤적 묶음의 바이너리 포맷.
///
///     헤더:  magic "YDTJ" (4B) | version UInt16 | count UInt32
///     궤적:  id UInt16 | dieCount UInt8 | direction UInt8 | frameRate UInt16 | frameCount UInt16
///           | restUpFaces [UInt8 x dieCount]  (각 1...6)
///           | collisionCount UInt16 | collisions [frame UInt16, die UInt8, intensity UInt8] x N
///           | frames [pos Float16 x3, quat Int16 x4] x (frameCount x dieCount)
///
/// 프레임당 주사위 하나에 14바이트. 5개 x 120프레임 = 8.4KB.
///
/// 이 포맷은 리틀엔디안 기기를 전제한다. iOS·macOS는 전부 리틀엔디안이므로
/// 바이트 스왑 코드 없이 이 전제만 문서화해둔다.
public enum TrajectoryArchive {
    public static let magic: [UInt8] = Array("YDTJ".utf8)
    public static let version: UInt16 = 1

    public enum Failure: Error, Equatable {
        case badMagic
        case unsupportedVersion(UInt16)
        case truncated(at: Int)
        case restUpFaceOutOfRange(UInt8)
        case tooManyTrajectories(UInt32)
    }

    public static func encode(_ trajectories: [Trajectory]) throws -> Data {
        var out = Data()
        out.append(contentsOf: magic)
        out.appendLE(version)
        out.appendLE(UInt32(trajectories.count))

        for trajectory in trajectories {
            out.appendLE(trajectory.id)
            out.append(UInt8(trajectory.dieCount))
            out.append(trajectory.direction.rawValue)
            out.appendLE(UInt16(trajectory.frameRate))
            out.appendLE(UInt16(trajectory.frameCount))
            out.append(contentsOf: trajectory.restUpFaces)

            out.appendLE(UInt16(trajectory.collisions.count))
            for cue in trajectory.collisions {
                out.appendLE(cue.frame)
                out.append(cue.dieIndex)
                out.append(UInt8(max(0, min(255, cue.intensity * 255))))
            }

            for frame in trajectory.frames {
                for pose in frame {
                    out.appendLE(Float16(pose.position.x))
                    out.appendLE(Float16(pose.position.y))
                    out.appendLE(Float16(pose.position.z))
                    let q = simd_normalize(pose.orientation).vector
                    for component in [q.x, q.y, q.z, q.w] {
                        out.appendLE(Int16(max(-32767, min(32767, (component * 32767).rounded()))))
                    }
                }
            }
        }
        return out
    }

    public static func decode(_ data: Data) throws -> [Trajectory] {
        var cursor = 0
        func need(_ bytes: Int) throws {
            guard cursor + bytes <= data.count else { throw Failure.truncated(at: cursor) }
        }

        try need(4)
        guard Array(data[data.startIndex..<data.startIndex + 4]) == magic else { throw Failure.badMagic }
        cursor = 4

        let fileVersion: UInt16 = try data.readLE(at: &cursor)
        guard fileVersion == version else { throw Failure.unsupportedVersion(fileVersion) }
        let count: UInt32 = try data.readLE(at: &cursor)

        // 헤더의 개수를 믿고 미리 할당하면 손상된 파일 하나가 앱 실행 시점에
        // 거대한 할당을 시도한다. 실제 상한(1~5개 x 방향 3종 x 변형 수십 개)의
        // 넉넉한 몇 배로 자른다.
        guard count <= 10_000 else { throw Failure.tooManyTrajectories(count) }

        var out: [Trajectory] = []
        out.reserveCapacity(Int(count))

        for _ in 0..<count {
            let id: UInt16 = try data.readLE(at: &cursor)
            let dieCount: UInt8 = try data.readLE(at: &cursor)
            let directionRaw: UInt8 = try data.readLE(at: &cursor)
            let frameRate: UInt16 = try data.readLE(at: &cursor)
            let frameCount: UInt16 = try data.readLE(at: &cursor)

            var restUpFaces: [UInt8] = []
            for _ in 0..<dieCount {
                let upFace: UInt8 = try data.readLE(at: &cursor)
                guard (1...6).contains(upFace) else { throw Failure.restUpFaceOutOfRange(upFace) }
                restUpFaces.append(upFace)
            }

            let collisionCount: UInt16 = try data.readLE(at: &cursor)
            var collisions: [CollisionCue] = []
            for _ in 0..<collisionCount {
                let frame: UInt16 = try data.readLE(at: &cursor)
                let die: UInt8 = try data.readLE(at: &cursor)
                let intensity: UInt8 = try data.readLE(at: &cursor)
                collisions.append(CollisionCue(frame: frame, dieIndex: die, intensity: Float(intensity) / 255))
            }

            var frames: [[DiePose]] = []
            frames.reserveCapacity(Int(frameCount))
            for _ in 0..<frameCount {
                var poses: [DiePose] = []
                poses.reserveCapacity(Int(dieCount))
                for _ in 0..<dieCount {
                    let x: Float16 = try data.readLE(at: &cursor)
                    let y: Float16 = try data.readLE(at: &cursor)
                    let z: Float16 = try data.readLE(at: &cursor)
                    let qx: Int16 = try data.readLE(at: &cursor)
                    let qy: Int16 = try data.readLE(at: &cursor)
                    let qz: Int16 = try data.readLE(at: &cursor)
                    let qw: Int16 = try data.readLE(at: &cursor)
                    let vector = SIMD4<Float>(Float(qx), Float(qy), Float(qz), Float(qw)) / 32767
                    poses.append(DiePose(
                        position: SIMD3(Float(x), Float(y), Float(z)),
                        orientation: simd_normalize(simd_quatf(vector: vector))
                    ))
                }
                frames.append(poses)
            }

            out.append(Trajectory(
                id: id, dieCount: Int(dieCount),
                direction: ThrowDirection(rawValue: directionRaw) ?? .center,
                frameRate: Int(frameRate), frames: frames,
                restUpFaces: restUpFaces, collisions: collisions
            ))
        }
        return out
    }
}

// MARK: - 바이트 입출력

extension Data {
    mutating func appendLE<T>(_ value: T) {
        var little = value
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func readLE<T>(at cursor: inout Int) throws -> T {
        let size = MemoryLayout<T>.size
        guard cursor + size <= count else { throw TrajectoryArchive.Failure.truncated(at: cursor) }
        let slice = self[startIndex + cursor ..< startIndex + cursor + size]
        cursor += size
        return slice.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
    }
}
