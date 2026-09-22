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
        XCTAssertGreaterThan(board.frame.width, app.frame.width * 0.96, "17줄 판이 화면 폭을 충분히 써야 한다")
        XCTAssertEqual(app.staticTexts["header.status"].label, "1R · 클래식")
        XCTAssertTrue(app.descendants(matching: .any)["players.seat.0"].label.contains("0승"))
        let turn = app.staticTexts["header.turn"]
        // 배치 단계: 기본 배치 그대로 흑이 놓고, 이어서 백이 놓으면 흑부터 튕긴다
        let done = app.buttons["alkkagi.placeDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertEqual(wait(until: { turn.label == "백 배치" }), .completed, "흑이 놓은 뒤 백 배치가 오지 않았다: \(turn.label)")
        // 좌석이 넘어간 직후에는 단추가 잠겨 있다 — 풀린 다음에 백이 누른다
        XCTAssertEqual(wait(until: { done.isEnabled }), .completed, "배치 완료가 다시 열리지 않았다")
        done.tap()
        XCTAssertEqual(wait(until: { turn.label == "흑 차례" }), .completed, "둘 다 놓았는데 흑 차례가 오지 않았다: \(turn.label)")
        XCTAssertEqual(wait(until: { !app.descendants(matching: .any)["turn.banner"].exists }), .completed)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Alkkagi-17-lines-round-1"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // 흑 돌 2(8000, 3000). 16칸 + 양쪽 여백 0.4칸, 아래로 2칸 당긴다.
        let stone = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1 - 3.4 / 16.8))
        let pullTo = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1 - 1.4 / 16.8))
        stone.press(forDuration: 0.1, thenDragTo: pullTo)
        XCTAssertEqual(wait(until: { turn.label == "백 차례" }, timeout: 8), .completed, "튕긴 뒤 차례가 바뀌지 않았다: \(turn.label)")
        app.buttons["header.menu"].tap()
        XCTAssertTrue(app.buttons["menu.alkkagi.local"].waitForExistence(timeout: 5))
    }

    /// 조건이 참이 될 때까지 기다린다. 차례 표시는 재생이 끝나야 바뀌어 존재 여부로는 볼 수 없다.
    @MainActor
    private func wait(until condition: @escaping () -> Bool, timeout: TimeInterval = 5) -> XCTWaiter.Result {
        let predicate = NSPredicate { _, _ in condition() }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout)
    }
}
