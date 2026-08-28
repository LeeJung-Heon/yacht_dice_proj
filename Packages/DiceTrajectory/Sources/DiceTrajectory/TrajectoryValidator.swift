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
}
