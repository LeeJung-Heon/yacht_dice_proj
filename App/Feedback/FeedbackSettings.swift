import Foundation

/// 사운드·햅틱 설정. 메뉴의 설정 시트가 `@AppStorage`로 쓰고, 피드백 코드는 여기서 읽는다.
enum FeedbackSettings {
    static let soundKey = "sound.enabled"
    static let hapticsKey = "haptics.enabled"

    static var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true
    }

    static var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: hapticsKey) as? Bool ?? true
    }
}
