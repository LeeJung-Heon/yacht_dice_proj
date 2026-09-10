import Foundation
import GameKit
import Observation
import UIKit

/// Game Center 인증. 턴제 매치 코드는 Task 7이 다시 채운다.
@MainActor
@Observable
final class GameCenterService: NSObject {
    enum AuthState: Equatable {
        case unknown
        case authenticated(name: String)
        case unavailable(String)
    }

    private(set) var authState: AuthState = .unknown

    var localPlayerID: String { GKLocalPlayer.local.gamePlayerID }

    /// 방을 만들 때 서버에 남길 게임별 플레이어(예: 오목의 돌 색). Task 7이 채운다.
    var playerID: String? { nil }

    func authenticate() {
        let player = GKLocalPlayer.local
        if player.isAuthenticated {
            didAuthenticate()
            return
        }
        player.authenticateHandler = { [weak self] viewController, error in
            let presented = UncheckedSendable(viewController)
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let viewController = presented.value {
                    Self.topViewController()?.present(viewController, animated: true)
                    return
                }
                if GKLocalPlayer.local.isAuthenticated {
                    self.didAuthenticate()
                } else {
                    self.authState = .unavailable(message ?? "Game Center에 로그인하지 않았습니다. 설정 앱에서 로그인하세요.")
                }
            }
        }
    }

    private func didAuthenticate() {
        authState = .authenticated(name: GKLocalPlayer.local.displayName)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// GameKit 객체는 Sendable이 아니다. 델리게이트 콜백에서 메인 액터로 넘길 때만 감싼다.
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
