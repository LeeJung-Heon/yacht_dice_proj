import Testing
import Foundation
import GameCore
@testable import YachtDice

@Suite("오목 판 기하")
struct OmokBoardTests {
    @Test("교차점 좌표와 탭 좌표가 서로 맞는다")
    func 왕복() {
        let size = CGSize(width: 300, height: 300)
        for (x, y) in [(0, 0), (14, 14), (7, 7), (3, 11)] {
            let p = OmokGeometry.point(of: Omok.Move(x: x, y: y), in: size)
            #expect(OmokGeometry.move(at: p, in: size) == Omok.Move(x: x, y: y))
        }
        // 교차점 사이 중간은 가까운 쪽으로
        let between = OmokGeometry.point(of: Omok.Move(x: 2, y: 2), in: size)
        #expect(OmokGeometry.move(at: CGPoint(x: between.x + 4, y: between.y - 4), in: size) == Omok.Move(x: 2, y: 2))
        // 판 밖은 nil
        #expect(OmokGeometry.move(at: CGPoint(x: -20, y: 10), in: size) == nil)
    }
}
