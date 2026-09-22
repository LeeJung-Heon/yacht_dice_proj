import XCTest

final class CupPongUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func test_컵별_디자인_편집을_열고_게임으로_돌아간다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch", "-noPush", "-noGameCenter"]
        app.launch()
        app.buttons["hub.cuppong"].tap()
        let customize = app.buttons["menu.cuppong.customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
        customize.tap()
        for index in 0..<10 {
            XCTAssertTrue(app.buttons["cuppong.customize.cup.\(index)"].exists)
        }
        app.buttons["cuppong.customize.cup.9"].tap()
        XCTAssertTrue(app.buttons["cuppong.customize.photo"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Cup customization"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["cuppong.customize.done"].tap()
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
    }

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
        let clearStage = NSPredicate { _, _ in !app.descendants(matching: .any)["turn.banner"].exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: clearStage, object: nil)], timeout: 5), .completed)
        let scene = XCTAttachment(screenshot: app.screenshot())
        scene.name = "CupPong 3D gameplay"
        scene.lifetime = .keepAlways
        add(scene)
        // 아래 중앙에서 위로 끌어 던진다
        let start = table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        let end = table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)
        // 물리 재생이 끝난 뒤: 맞혔으면 상대 컵이 9가 되고, 빗나갔으면 차례가 "상대 차례"로 넘어간다
        let moved = NSPredicate { _, _ in
            status.label != "내 컵 10 · 상대 컵 10" || turn.label == "상대 차례"
        }
        let outcome = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 8)
        XCTAssertEqual(outcome, .completed, "던진 뒤 상태가 바뀌지 않았다: \(status.label) / \(turn.label)")
        app.buttons["header.menu"].tap()
        XCTAssertTrue(app.buttons["menu.cuppong.local"].waitForExistence(timeout: 5))
    }
}
