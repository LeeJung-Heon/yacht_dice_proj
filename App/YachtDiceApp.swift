import SwiftUI
import YachtCore

@main
struct YachtDiceApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            switch container.status {
            case .ready(let session, let stage):
                GameScreen(session: session, stage: stage)
            case .failed(let message):
                ContentUnavailableView("시작할 수 없습니다", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            }
        }
    }
}

/// 앱 조립을 한 곳에 모은다. 복원은 동기라서 로딩 상태가 따로 없다.
@MainActor
@Observable
final class AppContainer {
    enum Status {
        case ready(GameSession, DiceStage)
        case failed(String)
    }

    private(set) var status: Status
    private let store = MatchStore.default

    init() {
        // UI 테스트가 깨끗한 상태에서 시작할 수 있게 한다
        if ProcessInfo.processInfo.arguments.contains("-resetMatch") {
            try? MatchStore.default.clear()
        }

        do {
            let stage = DiceStage(library: try TrajectoryLibrary.bundled())
            let restored = store.load()
            let session = GameSession(driver: LocalDriver(), stage: stage,
                                      log: restored ?? MatchLog(playerCount: 1))

            // 복원한 판이면 주사위를 마지막 상태로 앉힌다
            if let restored, restored.state.phase == .rolling {
                let state = restored.state
                Task { @MainActor in
                    _ = await stage.roll(values: state.dice, slots: Array(0..<YachtCore.diceCount),
                                         direction: .center, skipAnimation: true)
                    stage.placeHeld(state.held.sorted(), values: state.dice)
                }
            }

            let store = store
            session.onLogChanged = { log in
                try? store.save(log)
            }
            status = .ready(session, stage)
        } catch {
            status = .failed("주사위 데이터를 읽지 못했습니다: \(error)")
        }
    }
}
