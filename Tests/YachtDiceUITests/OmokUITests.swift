import XCTest

final class OmokUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// 판의 교차점 (x, y)를 탭한다. 판은 정사각형이고 칸은 변/19다.
    @MainActor
    private func tap(_ app: XCUIApplication, x: Int, y: Int) {
        let board = app.otherElements["omok.board"].exists ? app.otherElements["omok.board"] : app.descendants(matching: .any)["omok.board"]
        let cell = board.frame.width / 19
        board.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: cell * (CGFloat(x) + 0.5), dy: cell * (CGFloat(y) + 0.5))).tap()
        let place = app.buttons["omok.place"]
        XCTAssertTrue(place.waitForExistence(timeout: 3))
        place.tap()
    }

    @MainActor
    func test_로컬_2인_다섯_수로_흑이_이긴다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch", "-noPush", "-noGameCenter"]
        app.launch()
        app.buttons["hub.omok"].tap()
        app.buttons["menu.omok.local"].tap()
        XCTAssertTrue(app.buttons["menu.omok.local.start"].waitForExistence(timeout: 5))
        app.buttons["menu.omok.local.start"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["omok.board"].waitForExistence(timeout: 10))
        let board = app.descendants(matching: .any)["omok.board"]
        XCTAssertTrue(board.label.contains("19×19"))
        let screenWidth = app.windows.firstMatch.frame.width
        if screenWidth < 600 {
            XCTAssertGreaterThanOrEqual(board.frame.width, screenWidth - 12, "휴대폰에서는 판이 화면 폭을 충분히 사용해야 한다")
        }
        // 기존 15줄 판 바깥의 교차점을 실제로 탭하고 19번째 열의 끝에서 이긴다.
        for (x, y) in [(18, 14), (0, 0), (18, 15), (2, 0), (18, 16), (4, 0), (18, 17), (6, 0)] { tap(app, x: x, y: y) }
        let clearBoard = NSPredicate { _, _ in !app.descendants(matching: .any)["turn.banner"].exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: clearBoard, object: nil)], timeout: 5), .completed)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "omok-expanded-board"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        tap(app, x: 18, y: 18)
        let result = app.staticTexts["omok.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        // 로컬 2인 설정은 이름을 "흑"·"백"으로 두므로 이긴 좌석까지 문구가 못 박힌다
        XCTAssertEqual(result.label, "흑 승리")
        app.buttons["omok.back"].tap()
        XCTAssertTrue(app.buttons["menu.omok.local"].waitForExistence(timeout: 5))
    }
}
