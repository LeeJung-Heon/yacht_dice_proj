import XCTest

final class AlkkagiUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func test_로컬_2인_돌을_당겨_놓으면_차례가_바뀐다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch", "-noPush", "-noGameCenter"]
        app.launch()
        app.buttons["hub.alkkagi"].tap()
        app.buttons["menu.alkkagi.local"].tap()
        XCTAssertTrue(app.buttons["menu.alkkagi.local.start"].waitForExistence(timeout: 5))
        app.buttons["menu.alkkagi.local.start"].tap()
        let board = app.descendants(matching: .any)["alkkagi.board"]
        XCTAssertTrue(board.waitForExistence(timeout: 10))
        let turn = app.staticTexts["header.turn"]
        XCTAssertEqual(turn.label, "흑 차례")
        // 흑 돌 2(6000, 2000)는 판의 x 중앙, 아래에서 3/14 지점(여백 1칸 + 2칸)/14칸 → 정규화 y = 1 - 3/14
        let stone = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1 - 3.0 / 14))
        let pullTo = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1 - 1.0 / 14))   // 아래로 2칸 당김
        stone.press(forDuration: 0.1, thenDragTo: pullTo)
        let moved = NSPredicate { _, _ in turn.label == "백 차례" }
        let outcome = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 8)
        XCTAssertEqual(outcome, .completed, "튕긴 뒤 차례가 바뀌지 않았다: \(turn.label)")
        app.buttons["header.menu"].tap()
        XCTAssertTrue(app.buttons["menu.alkkagi.local"].waitForExistence(timeout: 5))
    }
}
