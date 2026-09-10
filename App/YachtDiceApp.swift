import SwiftUI

@main
struct YachtDiceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            ThemedRoot {
                switch container.status {
                case .hub:
                    HubScreen(container: container)
                case .menu(.yacht):
                    MenuScreen(container: container)
                case .menu(.omok):
                    OmokMenu(container: container)
                case .menu(.cuppong):
                    CupPongMenu(container: container)
                case .menu:
                    // 준비 중인 게임은 허브 타일이 막는다. 그래도 들어오면 허브로 돌린다.
                    HubScreen(container: container)
                case .playingOmok(let match):
                    OmokScreen(match: match, onReturn: { container.returnToMenu() })
                case .playingCupPong(let match):
                    CupPongScreen(match: match, onReturn: { container.returnToMenu() })
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
