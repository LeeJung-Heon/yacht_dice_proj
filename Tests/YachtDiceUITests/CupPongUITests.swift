import XCTest

final class CupPongUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func test_로컬_2인_한_번_던지면_결과가_보인다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch", "-noPush", "-noGameCenter"]
        app.launch()
        app.buttons["hub.cuppong"].tap()
        app.buttons["menu.cuppong.local"].tap()
        XCTAssertTrue(app.buttons["menu.cuppong.local.start"].waitForExistence(timeout: 5))
        app.buttons["menu.cuppong.local.start"].tap()
        let table = app.descendants(matching: .any)["cuppong.table"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        let status = app.staticTexts["header.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "내 컵 10 · 상대 컵 10")
        // 이름 기본값이 나·상대라 첫 차례는 "나 차례"다. 던지기 전에 본다 — 공이 날아가는 0.9초와 겹치면 안 된다.
        let turn = app.staticTexts["header.turn"]
        XCTAssertEqual(turn.label, "나 차례")
        // 아래 중앙에서 위로 끌어 던진다
        let start = table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        let end = table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)
        // 공이 0.9초 날아간 뒤: 맞혔으면 상대 컵이 9가 되고, 빗나갔으면 차례가 "상대 차례"로 넘어간다
        let moved = NSPredicate { _, _ in
            status.label != "내 컵 10 · 상대 컵 10" || turn.label == "상대 차례"
        }
        let outcome = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 5)
        XCTAssertEqual(outcome, .completed, "던진 뒤 상태가 바뀌지 않았다: \(status.label) / \(turn.label)")
        app.buttons["header.menu"].tap()
        XCTAssertTrue(app.buttons["menu.cuppong.local"].waitForExistence(timeout: 5))
    }
}
