import Foundation
import YachtCore

/// `GameSession`의 콜백을 햅틱·사운드로 옮긴다. 세션은 UIKit·AVFoundation을 모른다.
@MainActor
final class FeedbackCoordinator {
    private let haptics: Haptics
    private let sound: SoundPlayer

    init(haptics: Haptics = .shared, sound: SoundPlayer = .shared) {
        self.haptics = haptics
        self.sound = sound
    }

    func attach(_ session: GameSession) {
        session.onCollisionCue = { [haptics, sound] cue in
            haptics.play(hapticKind(forCollisionIntensity: cue.intensity))
            let bucket = min(3, Int(cue.intensity * 4))   // 세기를 넷으로 묶어 버퍼를 재사용한다
            sound.play(SoundSynth.tock(intensity: Float(bucket + 1) / 4), key: "tock\(bucket)")
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
