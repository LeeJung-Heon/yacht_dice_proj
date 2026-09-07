import Foundation
import simd

/// 구운 궤적이 쓸 만한지 검사한다. 베이커가 궤적을 채택하기 전에 통과시키는 관문이다.
public enum TrajectoryValidator {

    public static func problems(in trajectory: Trajectory,
                                trayInner: SIMD3<Float>,
                                dieSize: Float) -> [String] {
        var problems: [String] = []
        let margin = dieSize
        let limitX = trayInner.x / 2 + margin
        let limitZ = trayInner.z / 2 + margin
        let limitY = trayInner.y + margin

        guard trajectory.frameCount > 0 else { return ["프레임이 없다"] }
        guard trajectory.restUpFaces.count == trajectory.dieCount else {
            return ["정지 윗면 개수(\(trajectory.restUpFaces.count))가 주사위 수(\(trajectory.dieCount))와 다르다"]
        }

        // ① 트레이 이탈
        for (frameIndex, frame) in trajectory.frames.enumerated() {
            for (die, pose) in frame.enumerated() {
                let p = pose.position
                if abs(p.x) > limitX || abs(p.z) > limitZ || p.y < -margin || p.y > limitY {
                    problems.append("프레임 \(frameIndex) 주사위 \(die)가 트레이를 벗어났다: \(p)")
                }
            }
        }

        // ② 정지 시 윗면 기울기가 2° 이내인가, 그리고 기록된 윗면 값과 일치하는가
        //
        // 24개 축정렬 자세와의 거리로 재면 안 된다. 바닥에 평평하게 누운 주사위도
        // 수직축 둘레 yaw가 자유로워서 최대 45°가 나온다 (스펙 §7.3, Task 2 스파이크 실측).
        let last = trajectory.frames[trajectory.frameCount - 1]
        for die in 0..<trajectory.dieCount {
            let tilt = DieFace.upFaceTiltRadians(for: last[die].orientation)
            if tilt > 2.0 * .pi / 180 {
                problems.append("주사위 \(die)의 정지 자세가 \(tilt * 180 / .pi)도 기울었다 (벽에 기댔을 가능성)")
            }
            let actualUpFace = DieFace.upValue(for: last[die].orientation)
            if actualUpFace != trajectory.restUpFace(die: die) {
                problems.append("주사위 \(die)의 기록된 윗면 \(trajectory.restUpFace(die: die))이 실제 \(actualUpFace)과 다르다")
            }
        }

        // ③ 오프셋 전수 검증 — 스펙 §11의 가장 중요한 검사
        for die in 0..<trajectory.dieCount {
            for value in 1...6 {
                for yaw in 0..<4 {
                    let offset = FaceControl.offset(
                        restUpFace: trajectory.restUpFace(die: die),
                        showing: value, yawChoice: yaw
                    )
                    let pose = trajectory.posed(die: die, frame: trajectory.frameCount - 1, offset: offset)
                    let up = DieFace.upValue(for: pose.orientation)
                    if up != value {
                        problems.append("주사위 \(die)에 눈 \(value)를 요구했는데 \(up)이 나왔다 (yaw \(yaw))")
                    }
                }
            }
        }

        return problems
    }

    /// 눈에 보이는 벽 높이보다 위에서 벽에 닿은 프레임 수.
    ///
    /// 물리 벽은 `trayInner.y`(0.12)까지 있지만 화면에는 `visibleWallHeight`(0.03)까지만 그린다.
    /// 그 사이 높이에서 벽에 부딪히면 주사위가 허공에서 튕기는 것처럼 보인다.
    /// 던지는 도중 벽 근처를 높이 지나가는 것 자체는 괜찮다 — 벽에 **닿을 만큼** 가까운 프레임만 센다.
    public static func wallContactsAboveVisibleWall(in trajectory: Trajectory,
                                                    trayInner: SIMD3<Float>,
                                                    dieSize: Float,
                                                    visibleWallHeight: Float) -> Int {
        let reach = dieSize * 0.5 * 1.42 + 0.002   // 모서리로 닿는 경우까지 (대각 반지름)
        let nearX = trayInner.x / 2 - reach
        let nearZ = trayInner.z / 2 - reach
        var count = 0
        for frame in trajectory.frames {
            for pose in frame {
                let p = pose.position
                let touchingWall = abs(p.x) > nearX || abs(p.z) > nearZ
                let bottom = p.y - dieSize / 2
                if touchingWall && bottom > visibleWallHeight { count += 1 }
            }
        }
        return count
    }
}
