import XCTest

/// VoiceOver가 실제로 읽게 되는 접근성 트리를 그대로 훑는다.
///
/// 예전 접근성 테스트는 UI가 통째로 망가져도 통과했다. 여기서는 화면에 실제로
/// 올라온 요소의 라벨·값·활성 상태를 확인한다. 주의: XCUIElement.isHittable은
/// 순수 기하 판정이라 SwiftUI에서 disabled된 버튼에도 true다 — isEnabled를 같이 본다.
final class AccessibilityUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    @MainActor
    func test_접근성_트리가_게임_상태를_말로_전달한다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch", "-noPush"]
        app.launch()

        let solo = app.buttons["menu.solo"]
        XCTAssertTrue(solo.waitForExistence(timeout: 10), "메뉴가 뜨지 않았다")
        solo.tap()

        let roll = app.buttons["action.roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: 20), "Roll 버튼이 트리에 없다")

        // 굴리기 전: 남은 횟수를 읽어주고, 주사위 칩은 잠겨 있다
        XCTAssertEqual(roll.label, "주사위 굴리기, 3회 남음")
        for index in 0..<5 {
            let die = app.buttons["action.die.\(index)"]
            XCTAssertTrue(die.exists, "주사위 칩 \(index)이 트리에 없다")
            XCTAssertEqual(die.label, "주사위 \(index + 1), 아직 안 굴림")
            XCTAssertFalse(die.isEnabled, "굴리기 전인데 주사위 \(index) 칩이 활성이다")
        }

        // 점수판: 12칸 모두 이름과 상태를 읽어준다
        let categories = [
            "aces", "deuces", "threes", "fours", "fives", "sixes",
            "choice", "fourOfAKind", "fullHouse", "smallStraight", "largeStraight", "yacht",
        ]
        for category in categories {
            let row = app.buttons["scoreboard.row.\(category)"]
            XCTAssertTrue(row.exists, "\(category) 행이 트리에 없다")
            XCTAssertTrue(row.label.hasSuffix("비어 있음"),
                          "\(category) 행이 빈 칸이라고 읽어주지 않는다: \(row.label)")
            XCTAssertFalse(row.isEnabled, "굴리기 전인데 \(category) 행이 활성이다")
        }

        roll.tap()
        XCTAssertTrue(app.buttons["scoreboard.row.choice"].waitForHittable(timeout: 20))

        // 굴린 뒤: 칩이 눈을 읽어주고 고정 여부를 값으로 말한다
        XCTAssertEqual(roll.label, "주사위 굴리기, 2회 남음")
        var values: [Int] = []
        for index in 0..<5 {
            let die = app.buttons["action.die.\(index)"]
            XCTAssertTrue(die.isEnabled, "굴린 뒤인데 주사위 \(index) 칩이 잠겨 있다")
            XCTAssertEqual(die.value as? String, "고정 안 됨")

            let spoken = die.label
            let parts = spoken.components(separatedBy: ", ")
            XCTAssertEqual(parts.count, 2, "주사위 \(index)의 라벨이 눈을 읽어주지 않는다: \(spoken)")
            guard let value = Int(parts[1]), (1...6).contains(value) else {
                return XCTFail("주사위 \(index)의 라벨에 1~6이 아닌 값이 있다: \(spoken)")
            }
            values.append(value)
        }

        // 고정하면 값이 바뀐다
        app.buttons["action.die.0"].tap()
        XCTAssertEqual(app.buttons["action.die.0"].value as? String, "고정됨")
        XCTAssertEqual(app.buttons["action.die.0"].label, "주사위 1, \(values[0])")

        // Assist가 켜져 있으면 점수판이 지금 기록하면 몇 점인지 읽어준다
        let choice = app.buttons["scoreboard.row.choice"]
        XCTAssertEqual(choice.label, "Choice, 지금 기록하면 \(values.reduce(0, +))점")

        // 기록하면 "기록됨"으로 바뀌고 그 행은 잠긴다
        choice.tap()
        let recorded = app.buttons["scoreboard.row.choice"]
        XCTAssertTrue(recorded.waitForExistence(timeout: 10))
        XCTAssertEqual(recorded.label, "Choice, \(values.reduce(0, +))점 기록됨")
        XCTAssertFalse(recorded.isEnabled, "기록된 행이 다시 활성이다")
        // 총점 행은 스크롤 아래에 있다 — 찾아 내려가서 읽는다
        // 총점 행은 스크롤 아래에 있다. 합쳐진 요소 하나가 정확히 그 식별자를 달고
        // 총점을 읽어줘야 한다 — 자식마다 같은 식별자가 붙으면 지목할 수 없다.
        let total = app.staticTexts["scoreboard.total"]
        XCTAssertTrue(total.waitForHittable(timeout: 10), "총점 행을 접근성 트리에서 찾을 수 없다")
        XCTAssertEqual(total.label, "총점 \(values.reduce(0, +))점",
                       "총점 행이 하나의 요소로 합쳐져 읽히지 않는다")

        // 3D 무대는 VoiceOver에서 감춰져 있어야 한다 (값은 칩이 읽어준다)
        XCTAssertEqual(app.otherElements.matching(identifier: "dice.stage").count, 0)
    }
}
