import SwiftUI

@main
struct YachtDiceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            ThemedRoot {
                switch container.status {
                case .menu:
                    MenuScreen(container: container)
                case .playing(let session):
                    if let stage = container.currentStage {
                        GameScreen(session: session, stage: stage, onReturnToMenu: { container.returnToMenu() })
                    }
                case .failed(let message):
                    ContentUnavailableView("시작할 수 없습니다", systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                }
            }
        }
    }
}
