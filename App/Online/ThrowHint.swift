import Foundation

/// 굴린 쪽이 고른 궤적과 회전 선택. 받는 쪽이 같은 던지기를 보게 한다. 연출일 뿐이라 검증하지 않는다.
struct ThrowHint: Codable, Equatable, Sendable {
    /// 이 굴림이 로그에서 차지하는 이벤트 번호.
    let event: Int
    let trajectory: UInt16
    let direction: UInt8
    /// 굴린 주사위 순서대로 0...3.
    let yaws: [Int]
}
