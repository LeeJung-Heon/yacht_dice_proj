import SwiftUI

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
