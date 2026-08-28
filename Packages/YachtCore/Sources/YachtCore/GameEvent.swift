import Foundation

/// 턴 안에서의 위치. validate(_:)가 어떤 Intent를 허용할지 판단하는 근거다.
public enum Phase: String, Codable, Sendable {
    /// 이번 턴에 아직 한 번도 굴리지 않았다. 굴림만 가능하다.
    case awaitingFirstRoll
    /// 한 번 이상 굴렸다. 홀드·재굴림·기록이 가능하다.
    case rolling
    /// 12턴이 끝났다.
    case finished
}

/// 확정된 사실. 주사위 눈이 "이미 정해진 채로" 들어온다.
/// 눈의 출처(로컬 RNG / 서버 / 테스트 대본)를 코어는 알지 못한다.
public enum Event: Equatable, Codable, Sendable {
    /// 굴린 주사위의 새 눈. keep되지 않은 슬롯에 인덱스 오름차순으로 채워진다.
    /// 예) held = {1, 3} 이고 rolled([5, 2, 6]) 이면 슬롯 0←5, 2←2, 4←6.
    /// 배열 길이는 항상 rollableIndices.count 와 같아야 한다.
    case rolled([Int])
    case holdToggled(Int)
    case committed(ScoreCategory, Int)
    case turnAdvanced
    case gameEnded
}
