import Foundation
import Observation
import YachtCore

/// 앱 조립을 한 곳에 모은다. 복원은 동기라서 로딩 상태가 따로 없다.
@MainActor
@Observable
final class AppContainer {
    enum Status {
        case ready(GameSession, DiceStage)
        case failed(String)
    }

    private(set) var status: Status

    init(store: MatchStore = .default,
         arguments: [String] = ProcessInfo.processInfo.arguments) {
        // UI 테스트가 깨끗한 상태에서 시작할 수 있게 한다
        if arguments.contains("-resetMatch") {
            try? store.clear()
        }

        do {
            let stage = DiceStage(library: try TrajectoryLibrary.bundled())
            let restored = store.load()
            let session = GameSession(driver: LocalDriver(), stage: stage,
                                      log: restored ?? MatchLog(playerCount: 1))
            session.onLogChanged = { log in try? store.save(log) }

            // 복원한 판이면 주사위를 마지막 상태로 앉힌다. 그림은 즉시 확정되지만
            // roll()이 async라 한 틱 뒤에 실행된다 — 첫 입력보다는 항상 먼저다.
            if let restored, restored.state.phase == .rolling {
                Self.seatRestoredDice(restored.state, on: stage)
            }
            status = .ready(session, stage)
        } catch {
            status = .failed("주사위 데이터를 읽지 못했습니다: \(error)")
        }
    }

    private static func seatRestoredDice(_ state: GameState, on stage: DiceStage) {
        Task { @MainActor in
            _ = await stage.roll(values: state.dice, slots: Array(0..<YachtCore.diceCount),
                                 direction: .center, skipAnimation: true)
            stage.placeHeld(state.held.sorted(), values: state.dice)
        }
    }
}
