import Foundation
import Observation
import YachtCore

/// 앱 조립을 한 곳에 모은다. 씬(DiceStage)은 무겁고 게임마다 같으므로 한 번만 만든다.
@MainActor
@Observable
final class AppContainer {
    enum Status {
        case menu
        case playing(GameSession)
        case failed(String)
    }

    private(set) var status: Status
    /// 메뉴의 "이어하기"에 보여줄 저장된 판.
    private(set) var savedRecord: MatchRecord?

    private let store: MatchStore
    private let stage: DiceStage?

    var currentStage: DiceStage? { stage }

    init(store: MatchStore = .default,
         arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.store = store
        // UI 테스트가 깨끗한 상태에서 시작할 수 있게 한다
        if arguments.contains("-resetMatch") {
            try? store.clear()
        }
        do {
            stage = DiceStage(library: try TrajectoryLibrary.bundled())
            status = .menu
        } catch {
            stage = nil
            status = .failed("주사위 데이터를 읽지 못했습니다: \(error)")
        }
        savedRecord = store.load()
    }

    func startGame(mode: GameMode) {
        try? store.clear()
        savedRecord = nil
        launch(MatchRecord(mode: mode))
    }

    func resumeSavedGame() {
        guard let record = savedRecord ?? store.load() else { return }
        launch(record)
    }

    func returnToMenu() {
        savedRecord = store.load()
        status = .menu
    }

    private func launch(_ record: MatchRecord) {
        guard let stage else { return }
        stage.reset()
        let session = GameSession(driver: LocalDriver(), stage: stage, record: record)
        let store = store
        session.onLogChanged = { record in try? store.save(record) }

        // 복원한 판이면 주사위를 마지막 상태로 앉힌다. 그림은 즉시 확정되지만
        // roll()이 async라 한 틱 뒤에 실행된다 — 첫 입력보다는 항상 먼저다.
        let state = record.log.state
        if state.phase == .rolling {
            Task { @MainActor in
                _ = await stage.roll(values: state.dice, slots: Array(0..<YachtCore.diceCount),
                                     direction: .center, skipAnimation: true)
                stage.placeHeld(state.held.sorted(), values: state.dice)
                session.resumeTurnOwner()
            }
        } else {
            session.resumeTurnOwner()
        }
        status = .playing(session)
    }
}
