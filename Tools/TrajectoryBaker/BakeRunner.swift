import Foundation
import simd
import DiceTrajectory

struct BakePlan {
    /// 굴리는 개수별 x 방향별 시도 수. 5 x 3 x 80 = 1200회 시도. 5개짜리는 하나라도 선반에
    /// 올라앉으면 기각이라 채택률이 낮다. 조합당 최소 20개(TrajectoryLibraryTests)를 채우려면 이만큼 필요하다.
    static var variantsPerCombination: Int {
        // `-variants 30`처럼 주면 그만큼만. 던지기 파라미터를 맞출 때 짧게 돌려 보는 용도다.
        if let index = CommandLine.arguments.firstIndex(of: "-variants"),
           index + 1 < CommandLine.arguments.count,
           let count = Int(CommandLine.arguments[index + 1]), count > 0 {
            return count
        }
        return 80
    }
    static let frameRate = 60
    /// 정착 상한. 스파이크 실측 정착 시간이 0.9~5.0초인데 5초짜리 굴림은 게임 템포를 망친다.
    /// 조합별 채택 수가 20개 미만이면 180으로 완화한다 (Step 6 판정표).
    static let maxFrames = 180          // 3.0초 (정착 판정 대기 포함 — 대기 프레임은 잘라낸다)
    static let settleThreshold: Float = 0.002   // m/frame, 위치 차분 기준
    static let settleFrames = 20
    /// 마지막 움직임 뒤에 남길 프레임 수. 멈춘 것을 눈으로 확인할 만큼만.
    static let tailFrames = 10
    /// 이보다 짧으면 "던졌다"고 느끼기 전에 끝난다.
    static let minDurationSeconds: Float = 0.6
    /// 정지 시 윗면 기울기 상한. 초과하면 벽에 기대어 멈춘 것이므로 기각한다.
    /// 24개 축정렬 최근접 거리가 아니라 윗면 기울기로 잰다 (스펙 §7.3).
    static let maxUpFaceTiltDegrees: Float = 2.0

    static var combinations: [(dieCount: Int, direction: ThrowDirection)] {
        dieCounts.flatMap { count in ThrowDirection.allCases.map { (count, $0) } }
    }

    /// `-dice 5`처럼 주면 그 개수만 굽는다. 채택률이 낮은 조합만 보충할 때 쓴다.
    static var dieCounts: [Int] {
        if let index = CommandLine.arguments.firstIndex(of: "-dice"),
           index + 1 < CommandLine.arguments.count,
           let count = Int(CommandLine.arguments[index + 1]), (1...5).contains(count) {
            return [count]
        }
        return Array(1...5)
    }

    /// `-merge 경로`를 주면 그 아카이브를 먼저 읽고 새 궤적을 뒤에 이어 붙인다. id는 이어서 매긴다.
    static var mergeSource: URL? {
        guard let index = CommandLine.arguments.firstIndex(of: "-merge"),
              index + 1 < CommandLine.arguments.count else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[index + 1])
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
