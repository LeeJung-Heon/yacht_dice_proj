import Foundation
import simd
import DiceTrajectory

struct BakePlan {
    /// 굴리는 개수별 x 방향별 변형 수. 5 x 3 x 40 = 600개.
    static let variantsPerCombination = 40
    static let frameRate = 60
    /// 정착 상한. 스파이크 실측 정착 시간이 0.9~5.0초인데 5초짜리 굴림은 게임 템포를 망친다.
    /// 조합별 채택 수가 20개 미만이면 180으로 완화한다 (Step 6 판정표).
    static let maxFrames = 150          // 2.5초
    static let settleThreshold: Float = 0.002   // m/frame, 위치 차분 기준
    static let settleFrames = 20
    /// 정지 시 윗면 기울기 상한. 초과하면 벽에 기대어 멈춘 것이므로 기각한다.
    /// 24개 축정렬 최근접 거리가 아니라 윗면 기울기로 잰다 (스펙 §7.3).
    static let maxUpFaceTiltDegrees: Float = 2.0

    static var combinations: [(dieCount: Int, direction: ThrowDirection)] {
        (1...5).flatMap { count in ThrowDirection.allCases.map { (count, $0) } }
    }
}

struct BakeResult {
    var accepted: [Trajectory] = []
    var rejected: [(reason: String, dieCount: Int, direction: ThrowDirection)] = []

    var summary: String {
        let byCombination = Dictionary(grouping: accepted) { "\($0.dieCount)개/\($0.direction)" }
            .mapValues(\.count).sorted { $0.key < $1.key }
        return """
        채택 \(accepted.count)개 / 기각 \(rejected.count)개
        \(byCombination.map { "  \($0.key): \($0.value)" }.joined(separator: "\n"))
        기각 사유 상위: \(Dictionary(grouping: rejected, by: \.reason).mapValues(\.count)
            .sorted { $0.value > $1.value }.prefix(3)
            .map { "\($0.key) x\($0.value)" }.joined(separator: ", "))
        """
    }
}
