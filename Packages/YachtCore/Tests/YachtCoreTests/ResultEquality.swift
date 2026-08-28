import Foundation
@testable import YachtCore

/// 검증 테스트가 `validate(...) == .failure(...)` 로 쓸 수 있게 해주는 테스트 전용 도우미.
///
/// `Result<Void, _>`는 `Void`가 Equatable이 아니라 등가 비교가 안 된다.
/// 프로덕션 코드는 이 연산자를 쓰지 않으므로(allows(_:)는 패턴 매칭을 쓴다)
/// 라이브러리의 public API를 넓히지 않도록 테스트 타깃에 둔다.
extension Result where Success == Void, Failure == RuleError {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success): true
        case (.failure(let a), .failure(let b)): a == b
        default: false
        }
    }
}
