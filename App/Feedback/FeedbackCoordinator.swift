import Foundation
import YachtCore

/// `GameSession`의 콜백을 햅틱·사운드로 옮긴다. 세션은 UIKit·AVFoundation을 모른다.
@MainActor
final class FeedbackCoordinator {
    private let haptics: Haptics
    private let sound: SoundPlayer
    private let clock: () -> TimeInterval
    /// 충돌음 사이 최소 간격. 이보다 가까운 충돌은 소리를 내지 않아 다섯 개가 한꺼번에 떨어져도 뭉개지지 않는다.
    static let minimumTockGap: TimeInterval = 0.06
    private var lastTockAt: TimeInterval = -1

    init(haptics: Haptics = .shared, sound: SoundPlayer = .shared,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.haptics = haptics
        self.sound = sound
        self.clock = clock
    }

    /// 이 충돌에 소리를 낼지. 앞 소리와 `minimumTockGap` 이상 떨어져 있어야 한다.
    func shouldPlayTock() -> Bool {
        let now = clock()
        guard now - lastTockAt >= Self.minimumTockGap else { return false }
        lastTockAt = now
        return true
    }

    func attach(_ session: GameSession) {
        session.onCollisionCue = { [weak self, haptics, sound] cue in
            haptics.play(hapticKind(forCollisionIntensity: cue.intensity))
            guard let self, self.shouldPlayTock() else { return }
            let bucket = min(3, Int(cue.intensity * 4))   // 세기를 넷으로 묶어 버퍼를 재사용한다
            let die = Int(cue.dieIndex)
            sound.play(SoundSynth.tock(intensity: Float(bucket + 1) / 4, die: die), key: "tock\(bucket)-\(die)")
        }
        session.onHoldToggled = { [haptics, sound] in
            haptics.play(.selection)
            sound.play(SoundSynth.tick(), key: "tick")
        }
        session.onCommitted = { [haptics, sound] category, points, bonusReached in
            haptics.play(.impactRigid)
            sound.play(SoundSynth.stamp(), key: "stamp")
            let yacht = category == .yacht && points > 0
            if yacht || bonusReached {
                haptics.play(.success)
                sound.play(SoundSynth.chime(), key: "chime")
            }
        }
    }
}
