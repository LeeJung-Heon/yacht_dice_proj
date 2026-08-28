import XCTest

final class LaunchUITests: XCTestCase {
    func test_앱이_실행된다() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
