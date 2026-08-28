import SwiftUI
import YachtCore

@main
struct YachtDiceApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            switch container.status {
            case .loading:
                ProgressView("불러오는 중")
            case .ready(let session, let stage):
                GameScreen(session: session, stage: stage)
            case .failed(let message):
                ContentUnavailableView("시작할 수 없습니다", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            }
        }
    }
}

/// 앱 조립을 한 곳에 모은다. Task 18에서 저장 복원이 여기 붙는다.
@MainActor
@Observable
final class AppContainer {
    enum Status {
        case loading
        case ready(GameSession, DiceStage)
        case failed(String)
    }

    private(set) var status: Status = .loading
    private let store = MatchStore.default

    init() {
        do {
            let stage = DiceStage(library: try TrajectoryLibrary.bundled())
            let restored = (try? store.load()) ?? nil
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
