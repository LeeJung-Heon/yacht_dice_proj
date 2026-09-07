import SwiftUI
import GameKit

/// Game Center 기본 매치메이커. 친구 초대와 자동 매칭을 모두 다룬다.
/// 매치가 잡히면 `GKTurnBasedEventListener`(GameCenterService)가 `didBecomeActive`로 받는다.
struct MatchmakerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> GKTurnBasedMatchmakerViewController {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.inviteMessage = "요트 다이스 한 판 어때요?"
        let controller = GKTurnBasedMatchmakerViewController(matchRequest: request)
        controller.turnBasedMatchmakerDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: GKTurnBasedMatchmakerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    final class Coordinator: NSObject, GKTurnBasedMatchmakerViewControllerDelegate {
        private let dismiss: @Sendable @MainActor () -> Void
        init(dismiss: @escaping @Sendable @MainActor () -> Void) { self.dismiss = dismiss }

        nonisolated func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {
            let dismiss = self.dismiss
            Task { @MainActor in dismiss() }
        }

        nonisolated func turnBasedMatchmakerViewController(_ viewController: GKTurnBasedMatchmakerViewController,
                                                           didFailWithError error: any Error) {
            let dismiss = self.dismiss
            Task { @MainActor in dismiss() }
        }
    }
}
