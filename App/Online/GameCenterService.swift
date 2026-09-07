import Foundation
import GameKit
import Observation
import UIKit
import YachtCore

/// Game Center 인증, 진행 중 매치 목록, 턴 이벤트 수신.
///
/// GameKit은 여기와 `GameCenterTurnTransport`, `MatchmakerView`에서만 import한다.
@MainActor
@Observable
final class GameCenterService: NSObject, GKLocalPlayerListener {
    enum AuthState: Equatable {
        case unknown
        case authenticated(name: String)
        case unavailable(String)
    }

    private(set) var authState: AuthState = .unknown
    private(set) var activeMatches: [GKTurnBasedMatch] = []
    /// 매치메이커나 알림으로 매치가 열렸다. AppContainer가 게임을 시작한다.
    var onMatchOpened: ((GKTurnBasedMatch) -> Void)?

    private var streams: [String: AsyncStream<MatchLog>.Continuation] = [:]
    private var registered = false

    var localPlayerID: String { GKLocalPlayer.local.gamePlayerID }

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
        if !registered {
            GKLocalPlayer.local.register(self)
            registered = true
        }
        Task { await reloadMatches() }
    }

    func reloadMatches() async {
        let matches = (try? await GKTurnBasedMatch.loadMatches()) ?? []
        activeMatches = matches.filter { $0.status != .ended }
    }

    /// 이 매치의 새 로그가 도착할 때마다 흐르는 스트림. `GameCenterTurnTransport`가 쓴다.
    func stream(for matchID: String) -> AsyncStream<MatchLog> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            streams[matchID] = continuation
        }
    }

    // MARK: - GKLocalPlayerListener (턴 이벤트만 쓴다)

    nonisolated func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        let boxed = UncheckedSendable(match)
        Task { @MainActor [weak self] in
            self?.deliver(boxed.value, opened: didBecomeActive)
        }
    }

    nonisolated func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        let boxed = UncheckedSendable(match)
        Task { @MainActor [weak self] in
            self?.deliver(boxed.value, opened: false)
        }
    }

    private func deliver(_ match: GKTurnBasedMatch, opened: Bool) {
        if let data = match.matchData, !data.isEmpty, let log = try? MatchLog.decoded(from: data) {
            streams[match.matchID]?.yield(log)
        }
        if opened { onMatchOpened?(match) }
        Task { await reloadMatches() }
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
