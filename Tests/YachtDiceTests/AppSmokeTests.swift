import Testing
import YachtCore
import DiceTrajectory
@testable import YachtDice

/// 앱 타깃이 두 로컬 패키지에 실제로 링크되었는지 확인한다.
/// Bool(true)를 확인하는 테스트는 스캐폴딩이 깨져도 통과하므로 의미가 없다.
@Test func 앱_타깃이_두_패키지에_링크된다() {
    #expect(YachtCore.diceCount == 5)
    #expect(DiceTrajectory.formatVersion == 1)
}
