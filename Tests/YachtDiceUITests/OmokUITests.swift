import XCTest

final class OmokUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// 판의 교차점 (x, y)를 탭한다. 판은 정사각형이고 칸은 변/15다.
    @MainActor
    private func tap(_ app: XCUIApplication, x: Int, y: Int) {
        let board = app.otherElements["omok.board"].exists ? app.otherElements["omok.board"] : app.descendants(matching: .any)["omok.board"]
        let cell = board.frame.width / 15
        board.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: cell * (CGFloat(x) + 0.5), dy: cell * (CGFloat(y) + 0.5))).tap()
        let place = app.buttons["omok.place"]
        XCTAssertTrue(place.waitForExistence(timeout: 3))
        place.tap()
    }

    @MainActor
    func test_로컬_2인_다섯_수로_흑이_이긴다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch", "-noPush"]
        app.launch()
        app.buttons["hub.omok"].tap()
        app.buttons["menu.omok.local"].tap()
        XCTAssertTrue(app.buttons["menu.omok.local.start"].waitForExistence(timeout: 5))
        app.buttons["menu.omok.local.start"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["omok.board"].waitForExistence(timeout: 10))
        for (x, y) in [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (2, 1), (3, 0), (3, 1), (4, 0)] { tap(app, x: x, y: y) }
        let result = app.staticTexts["omok.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        // 로컬 2인 설정은 이름을 "흑"·"백"으로 두므로 이긴 좌석까지 문구가 못 박힌다
        XCTAssertEqual(result.label, "흑 승리")
        app.buttons["omok.back"].tap()
        XCTAssertTrue(app.buttons["menu.omok.local"].waitForExistence(timeout: 5))
    }
}
