import Foundation
import GameKit
import Observation
import UIKit
import os

/// GameKit 인증과 점수 제출. 테스트는 가짜를 끼운다.
protocol GameCenterAuthenticating: Sendable {
    func authenticate() async throws -> (playerID: String, name: String)
    func submitScore(_ score: Int, leaderboardID: String) async throws
}

/// 실제 GameKit. 로그인 창은 GameKit이 주는 뷰 컨트롤러를 최상단에 띄운다.
struct LiveAuthenticator: GameCenterAuthenticating {
    func authenticate() async throws -> (playerID: String, name: String) {
        let player = GKLocalPlayer.local
        if player.isAuthenticated { return (player.gamePlayerID, player.displayName) }
        return try await withCheckedThrowingContinuation { continuation in
            // authenticateHandler는 로그인 창을 닫을 때마다 다시 불린다. continuation은 한 번만 재개해야 한다.
            // Mutex는 복사할 수 없어 이 클로저 두 겹을 넘지 못하므로 잠금은 OSAllocatedUnfairLock으로 든다.
            let done = OSAllocatedUnfairLock(initialState: false)
            player.authenticateHandler = { viewController, error in
                let presented = UncheckedSendable(viewController)
                Task { @MainActor in
                    if let viewController = presented.value {
                        Self.topViewController()?.present(viewController, animated: true)
                        return   // 사용자가 창을 닫으면 핸들러가 다시 불린다
                    }
                    guard done.withLock({ done -> Bool in
                        let was = done
                        done = true
                        return !was
                    }) else { return }
                    if GKLocalPlayer.local.isAuthenticated {
                        continuation.resume(returning: (GKLocalPlayer.local.gamePlayerID, GKLocalPlayer.local.displayName))
                    } else {
                        continuation.resume(throwing: error ?? CocoaError(.userCancelled))
                    }
                }
            }
        }
    }

    func submitScore(_ score: Int, leaderboardID: String) async throws {
        try await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                            leaderboardIDs: [leaderboardID])
    }

    @MainActor
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Game Center 신원. 로그인은 선택이라 실패해도 앱은 익명으로 돈다.
@MainActor
@Observable
final class GameCenterService {
    enum AuthState: Equatable {
        case unknown
        case authenticated(playerID: String, name: String)
        case unavailable(String)
    }

    private(set) var authState: AuthState = .unknown
    private let authenticator: any GameCenterAuthenticating

    init(authenticator: any GameCenterAuthenticating = LiveAuthenticator()) {
        self.authenticator = authenticator
    }

    /// 방을 만들 때 서버 `matches.host_player`에 남길 신원. 미로그인이면 nil이다.
    var playerID: String? { if case .authenticated(let id, _) = authState { id } else { nil } }
    var displayName: String? { if case .authenticated(_, let name) = authState { name } else { nil } }

    /// 여러 번 불러도 안전하다. 허브로 돌아올 때마다 로그인 창이 다시 뜨면 안 되므로
    /// 한 번 결론이 난 뒤에는(로그인이든 실패든) 아무것도 하지 않는다.
    func authenticate() async {
        guard case .unknown = authState else { return }
        do {
            let (id, name) = try await authenticator.authenticate()
            authState = .authenticated(playerID: id, name: name)
        } catch {
            authState = .unavailable(error.localizedDescription)
        }
    }

    /// 게임별 승수를 리더보드 `wins.<game>`에 올린다. 미로그인이면 아무것도 하지 않는다.
    func submit(wins: Int, game: GameID) async {
        guard playerID != nil else { return }
        try? await authenticator.submitScore(wins, leaderboardID: "wins.\(game.rawValue)")
    }

    func presentLeaderboards() {
        let controller = GKGameCenterViewController(state: .leaderboards)
        controller.gameCenterDelegate = Dismisser.shared
        LiveAuthenticator.topViewController()?.present(controller, animated: true)
    }

    /// 리더보드 창의 "완료"를 닫는 것 말고는 할 일이 없다.
    private final class Dismisser: NSObject, GKGameCenterControllerDelegate {
        @MainActor static let shared = Dismisser()
        func gameCenterViewControllerDidFinish(_ controller: GKGameCenterViewController) {
            controller.dismiss(animated: true)
        }
    }
}

/// GameKit 객체는 Sendable이 아니다. 델리게이트 콜백에서 메인 액터로 넘길 때만 감싼다.
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
