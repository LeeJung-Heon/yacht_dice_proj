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
        // 판 밖은 nil — 음수 쪽도, 마지막 교차점 너머도
        #expect(OmokGeometry.move(at: CGPoint(x: -20, y: 10), in: size) == nil)
        #expect(OmokGeometry.move(at: CGPoint(x: 305, y: 10), in: size) == nil)
    }

    /// 두 방향을 다 본다. 한쪽만 보면 긴 변을 쓰는 구현도 통과해 `min`이 시험되지 않는다.
    @Test("정사각형이 아닌 자리에서는 짧은 변이 판의 크기다",
          arguments: [CGSize(width: 300, height: 480), CGSize(width: 480, height: 300)])
    func 짧은_변을_따른다(size: CGSize) {
        #expect(OmokGeometry.cell(size) == 20)
        #expect(OmokGeometry.point(of: Omok.Move(x: 14, y: 14), in: size) == CGPoint(x: 290, y: 290))
        for (x, y) in [(0, 0), (7, 7)] {
            let p = OmokGeometry.point(of: Omok.Move(x: x, y: y), in: size)
            #expect(OmokGeometry.move(at: p, in: size) == Omok.Move(x: x, y: y))
        }
        // 300pt 정사각형 밖은 긴 변 쪽으로 남는 자리라도 판이 아니다
        #expect(OmokGeometry.move(at: CGPoint(x: 150, y: 320), in: size) == nil)
        #expect(OmokGeometry.move(at: CGPoint(x: 320, y: 150), in: size) == nil)
    }
}
