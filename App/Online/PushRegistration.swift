import Foundation
import Supabase
import UIKit
import UserNotifications

/// 알림 권한을 묻고 APNs 토큰을 `device_tokens`에 올리며, 알림을 탭하면 그 판을 연다.
///
/// 앱이 뒤에 있거나 닫혀 있을 때 상대가 턴을 끝내면 서버 웹훅이 이 기기로 "내 차례"를 보낸다.
@MainActor
final class PushRegistration: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushRegistration()

    override init() { super.init() }

    /// 알림을 탭했을 때 열 매치. `AppContainer`가 건다. 아직 없으면 `pendingMatchID`에 두었다가 걸릴 때 넘긴다.
    var onOpenMatch: ((UUID) -> Void)? {
        didSet { flushPending() }
    }
    /// 지금 열려 있는 매치. 그 판의 알림은 앞에서 띄우지 않는다.
    var currentMatchID: (() -> UUID?)?
    private var pendingMatchID: UUID?
    private var deviceToken: String?
    private var service: SupabaseService?
    private(set) var lastError: String?

    /// 권한을 묻고(처음 한 번) 원격 알림을 등록한다. 토큰은 `didRegister(token:)`로 온다.
    func requestAndRegister(service: SupabaseService) async {
        self.service = service
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }
        } catch {
            lastError = "\(error)"
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
        await upsertIfReady()
    }

    /// `AppDelegate`가 APNs 토큰을 받으면 부른다.
    func didRegister(token data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        Task { await upsertIfReady() }
    }

    func didFailToRegister(_ error: any Error) {
        lastError = "\(error)"
    }

    private func upsertIfReady() async {
        guard let token = deviceToken, let service, let uid = service.uid else { return }
        do {
            try await service.client.from("device_tokens")
                .upsert(DeviceToken(uid: uid, token: token, platform: "ios", updatedAt: Date()), onConflict: "token")
                .execute()
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    /// 알림 페이로드에서 매치 ID를 꺼낸다. `AppDelegate`와 테스트가 쓴다.
    nonisolated static func matchID(from userInfo: [AnyHashable: Any]) -> UUID? {
        (userInfo["matchID"] as? String).flatMap(UUID.init(uuidString:))
    }

    func open(matchID: UUID) {
        if let onOpenMatch {
            onOpenMatch(matchID)
        } else {
            pendingMatchID = matchID
        }
    }

    private func flushPending() {
        guard let id = pendingMatchID, let onOpenMatch else { return }
        pendingMatchID = nil
        onOpenMatch(id)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let id = Self.matchID(from: userInfo) else { return }
        await MainActor.run { open(matchID: id) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        let id = Self.matchID(from: userInfo)
        let playingThis = await MainActor.run { id != nil && currentMatchID?() == id }
        return playingThis ? [] : [.banner, .sound]
    }

    private struct DeviceToken: Encodable {
        let uid: UUID
        let token: String
        let platform: String
        let updatedAt: Date
        enum CodingKeys: String, CodingKey {
            case uid, token, platform
            case updatedAt = "updated_at"
        }
    }
}

/// APNs 토큰 콜백은 UIKit 델리게이트로만 온다.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = PushRegistration.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistration.shared.didRegister(token: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushRegistration.shared.didFailToRegister(error)
    }
}
