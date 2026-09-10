import XCTest

final class MenuUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    @MainActor
    func test_컴퓨터_대전_한_턴() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch", "-noPush", "-noGameCenter"]
        app.launch()
        app.openYachtMenu()

        let bot = app.buttons["menu.bot"]
        XCTAssertTrue(bot.waitForExistence(timeout: 10))
        bot.tap()
        let normal = app.buttons["menu.bot.normal"]
        XCTAssertTrue(normal.waitForExistence(timeout: 5))
        normal.tap()

        // combine된 요소는 타입이 고정되지 않으므로 어느 타입이든 찾는다
        XCTAssertTrue(app.descendants(matching: .any)["players.seat.1"].waitForExistence(timeout: 10), "참가자 띠가 없다")
        let roll = app.buttons["action.roll"]
        XCTAssertTrue(roll.waitForHittable(timeout: 10))
        roll.tap()
        let row = app.buttons["scoreboard.row.choice"]
        XCTAssertTrue(row.waitForHittable(timeout: 15))
        row.tap()

        // 봇 차례: 상태 표시가 뜨고 입력이 잠긴다
        XCTAssertTrue(app.staticTexts["header.status"].waitForExistence(timeout: 5), "봇 차례 표시가 없다")
        XCTAssertFalse(roll.isEnabled, "봇 차례인데 Roll이 활성이다")

        // 봇이 끝내면 내 차례로 돌아온다 (굴림 3회 연출 최대 ~8초)
        XCTAssertTrue(roll.waitForHittable(timeout: 30), "봇 턴이 끝나지 않았다")
        XCTAssertEqual(app.otherElements["header.turn"].label, "Turn 2/12")
    }

    @MainActor
    func test_로컬_2인_핸드오프() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch", "-noPush", "-noGameCenter"]
        app.launch()
        app.openYachtMenu()

        let local = app.buttons["menu.local"]
        XCTAssertTrue(local.waitForExistence(timeout: 10))
        local.tap()
        let start = app.buttons["menu.local.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let roll = app.buttons["action.roll"]
        XCTAssertTrue(roll.waitForHittable(timeout: 10))
        roll.tap()
        let row = app.buttons["scoreboard.row.choice"]
        XCTAssertTrue(row.waitForHittable(timeout: 15))
        row.tap()

        let handoff = app.buttons["handoff.start"]
        XCTAssertTrue(handoff.waitForExistence(timeout: 5), "핸드오프가 뜨지 않았다")
        handoff.tap()
        XCTAssertTrue(roll.waitForHittable(timeout: 5), "두 번째 사람이 굴릴 수 없다")
    }

    @MainActor
    func test_메뉴로_돌아가면_이어하기가_있다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch", "-noPush", "-noGameCenter"]
        app.launch()
        app.openYachtMenu()
        let solo = app.buttons["menu.solo"]
        XCTAssertTrue(solo.waitForExistence(timeout: 10))
        solo.tap()
        let roll = app.buttons["action.roll"]
        XCTAssertTrue(roll.waitForHittable(timeout: 10))
        roll.tap()
        XCTAssertTrue(app.buttons["scoreboard.row.choice"].waitForHittable(timeout: 15))
        app.buttons["header.menu"].tap()
        XCTAssertTrue(app.buttons["menu.resume"].waitForExistence(timeout: 5), "이어하기가 없다")
    }

    @MainActor
    func test_허브에서_오목_메뉴가_열리고_돌아온다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch", "-noPush", "-noGameCenter"]
        app.launch()
        let omok = app.buttons["hub.omok"]
        XCTAssertTrue(omok.waitForExistence(timeout: 10))
        omok.tap()
        XCTAssertTrue(app.buttons["menu.omok.local"].waitForExistence(timeout: 5))
        app.buttons["menu.back"].tap()
        XCTAssertTrue(app.buttons["hub.yacht"].waitForExistence(timeout: 5))
        // 준비 중인 게임은 허브에 보이되 눌리지 않는다
        let cuppong = app.buttons["hub.cuppong"]
        XCTAssertTrue(cuppong.waitForExistence(timeout: 5))
        XCTAssertFalse(cuppong.isEnabled, "준비 중 타일이 눌린다")
    }
}

extension MenuUITests {
    @MainActor
    func test_온라인_대전_화면이_열린다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch", "-noPush", "-noGameCenter"]
        app.launch()
        app.openYachtMenu()
        let online = app.buttons["menu.online"]
        XCTAssertTrue(online.waitForExistence(timeout: 10))
        online.tap()
        XCTAssertTrue(app.descendants(matching: .any)["online.status"].waitForExistence(timeout: 10),
                      "온라인 상태 문구가 없다")
    }
}

extension MenuUITests {
    @MainActor
    func test_설정_시트가_열린다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch", "-noPush", "-noGameCenter"]
        app.launch()
        let settings = app.buttons["menu.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.switches["settings.sound"].waitForExistence(timeout: 5), "사운드 토글이 없다")
        XCTAssertTrue(app.switches["settings.haptics"].exists, "햅틱 토글이 없다")
    }
}
