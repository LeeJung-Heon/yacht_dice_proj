import XCTest

final class FullGameUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// 12턴을 끝까지 진행한다. P1 완료 기준의 첫 번째 항목이다.
    @MainActor
    func test_12턴을_완주한다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch"]
        app.launch()

        let roll = app.buttons["action.roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: 15), "Roll 버튼이 없다")

        let categories = [
            "aces", "deuces", "threes", "fours", "fives", "sixes",
            "choice", "fourOfAKind", "fullHouse", "smallStraight", "largeStraight", "yacht",
        ]

        for (turn, category) in categories.enumerated() {
            XCTAssertTrue(roll.waitForHittable(timeout: 15), "\(turn + 1)턴에서 Roll을 누를 수 없다")
            roll.tap()

            let row = app.buttons["scoreboard.row.\(category)"]
            XCTAssertTrue(row.waitForHittable(timeout: 15), "\(turn + 1)턴에서 \(category)를 누를 수 없다")
            row.tap()
        }

        XCTAssertTrue(app.staticTexts["게임 종료"].waitForExistence(timeout: 10), "12턴 뒤에 게임이 끝나지 않았다")

        // 최종 점수가 보이고, 거기서 새 판을 시작할 수 있어야 한다.
        // 이게 없으면 앱을 강제 종료하는 것 말고는 새 게임을 시작할 방법이 없다.
        let total = app.staticTexts["result.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5), "최종 점수가 보이지 않는다")
        let newGame = app.buttons["action.newGame"]
        XCTAssertTrue(newGame.waitForHittable(timeout: 5), "새 게임 버튼을 누를 수 없다")
        newGame.tap()

        XCTAssertTrue(app.otherElements["header.turn"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements["header.turn"].label, "Turn 1/12", "새 게임이 1턴에서 시작하지 않았다")
        XCTAssertTrue(roll.waitForHittable(timeout: 5), "새 게임에서 Roll을 누를 수 없다")
        XCTAssertFalse(app.staticTexts["게임 종료"].exists, "새 게임인데 종료 표시가 남아 있다")
    }

    /// 앱을 재시작해도 진행이 남는다. P1 완료 기준의 다섯 번째 항목이다.
    @MainActor
    func test_재시작_후_진행이_복원된다() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetMatch"]
        app.launch()

        let roll = app.buttons["action.roll"]
        XCTAssertTrue(roll.waitForHittable(timeout: 15))
        roll.tap()

        let row = app.buttons["scoreboard.row.choice"]
        XCTAssertTrue(row.waitForHittable(timeout: 15))
        row.tap()

        let headerBefore = app.otherElements["header.turn"].label
        XCTAssertTrue(headerBefore.contains("2"), "기록 후 2턴이어야 한다: \(headerBefore)")

        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launch()   // -resetMatch 없이

        let header = relaunched.otherElements["header.turn"]
        XCTAssertTrue(header.waitForExistence(timeout: 15))
        XCTAssertEqual(header.label, headerBefore, "재시작 후 턴이 복원되지 않았다")
    }
}

extension XCUIElement {
    /// 존재 + 활성화 + 히트 테스트 가능해질 때까지 기다린다.
    ///
    /// 두 가지를 각각 다루지 않으면 안 된다:
    ///
    /// 1. `isHittable`은 순수하게 기하학적 판정이다 — 화면 안에 있고
    ///    가려지지 않았으면 참이다. SwiftUI에서 `.disabled(true)`로 비활성화한
    ///    버튼도 여전히 `isHittable == true`다. 이걸 모르고 `isHittable`만
    ///    보고 바로 tap()하면, 아직 게임 상태가 커밋을 허용하지 않는(굴림
    ///    애니메이션이 끝나기 전, 또는 이번 턴에 아직 안 굴린) 비활성 버튼을
    ///    두드리게 된다. iOS는 비활성 컨트롤에 터치를 전달하지 않으므로 그
    ///    tap()은 아무 효과 없이 사라진다 — 예외도, 실패도 없이 조용히
    ///    무시된다. 실제로 이 버그 때문에 12턴 테스트가 24번의 탭 중 7번만
    ///    실제로 GameSession.send에 도달하고 나머지는 씹히는 것을
    ///    디바이스 콘솔 로그로 확인했다. `isEnabled`까지 같이 확인해야 한다.
    ///
    /// 2. 스코어보드는 12줄이라 화면(특히 iPhone 17)에 다 들어가지 않는다.
    ///    뒤쪽 카테고리(예: yacht)는 ScrollView 밖에 있어서 존재는 하지만
    ///    히트 테스트는 실패한다 — 사람이 손가락으로 스와이프하면 되는
    ///    정상적인 상황이다. XCUITest의 tap()은 VoiceOver와 달리 대상을
    ///    자동으로 화면 안으로 스크롤해주지 않으므로, 화면 밖에 있는 동안은
    ///    이 헬퍼가 대신 조금씩 스크롤한다. 다만 "존재하지만 히트 불가"에는
    ///    화면 밖에 있는 경우와, 화면 안에 있지만 아직 비활성인 경우가 섞여
    ///    있으므로, frame이 실제로 스크롤뷰 아래로 벗어났을 때만 스크롤한다
    ///    — 안 그러면 이미 화면 안에서 활성화를 기다리는 행을 밀어내 버린다.
    @MainActor
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let app = XCUIApplication()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists && isEnabled && isHittable { return true }
            if exists {
                let scrollView = app.scrollViews.firstMatch
                if scrollView.exists, frame.maxY > scrollView.frame.maxY {
                    scrollView.swipeUp()
                }
            }
            _ = app.wait(for: .runningForeground, timeout: 0.2)
        }
        return false
    }
}
