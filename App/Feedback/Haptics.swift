import UIKit

enum HapticKind: Equatable, Sendable {
    case impactLight, impactMedium, impactHeavy, impactRigid, selection, success
}

/// 충돌 큐의 세기(0...1)를 햅틱 종류로. 순수 함수라 테스트한다.
func hapticKind(forCollisionIntensity intensity: Float) -> HapticKind {
    if intensity < 0.35 { return .impactLight }
    if intensity < 0.7 { return .impactMedium }
    return .impactHeavy
}

@MainActor
final class Haptics {
    static let shared = Haptics()

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    func play(_ kind: HapticKind) {
        guard FeedbackSettings.hapticsEnabled else { return }
        switch kind {
        case .impactLight: light.impactOccurred()
        case .impactMedium: medium.impactOccurred()
        case .impactHeavy: heavy.impactOccurred()
        case .impactRigid: rigid.impactOccurred()
        case .selection: selection.selectionChanged()
        case .success: notification.notificationOccurred(.success)
        }
    }
}
