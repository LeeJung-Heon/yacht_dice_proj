import XCTest

final class LaunchUITests: XCTestCase {
    @MainActor
    func test_앱이_실행된다() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.buttons["hub.yacht"].waitForExistence(timeout: 10), "허브가 뜨지 않았다")
    }
}
