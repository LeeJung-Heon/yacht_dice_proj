import Testing
import Foundation
@testable import YachtDice

@Suite("피드백")
struct FeedbackTests {
    @Test("충돌 세기 → 햅틱 종류 경계")
    func 햅틱_매핑() {
        #expect(hapticKind(forCollisionIntensity: 0.0) == .impactLight)
        #expect(hapticKind(forCollisionIntensity: 0.34) == .impactLight)
        #expect(hapticKind(forCollisionIntensity: 0.35) == .impactMedium)
        #expect(hapticKind(forCollisionIntensity: 0.69) == .impactMedium)
        #expect(hapticKind(forCollisionIntensity: 0.7) == .impactHeavy)
        #expect(hapticKind(forCollisionIntensity: 1.0) == .impactHeavy)
    }

    @Test("합성 소리는 길이가 맞고 진폭이 0 초과 1 이하다")
    func 사운드_버퍼() {
        let cases: [(String, [Float], Double)] = [
            ("tock", SoundSynth.tock(intensity: 1), 0.08),
            ("tick", SoundSynth.tick(), 0.025),
            ("stamp", SoundSynth.stamp(), 0.12),
            ("chime", SoundSynth.chime(), 0.4),
            ("pong", SoundSynth.pong(), 0.18),
            ("clack", SoundSynth.clack(), 0.08),
            ("drop", SoundSynth.drop(), 0.12),
        ]
        for (name, samples, seconds) in cases {
            #expect(samples.count == Int(seconds * SoundSynth.sampleRate), "\(name) 길이 \(samples.count)")
            let peak = samples.map(abs).max() ?? 0
            #expect(peak > 0.05 && peak <= 1.0, "\(name) 최대 진폭 \(peak)")
        }
    }

    @Test("약한 충돌은 조용하다")
    func 세기_반영() {
        let loud = SoundSynth.tock(intensity: 1).map(abs).max()!
        let soft = SoundSynth.tock(intensity: 0.2).map(abs).max()!
        #expect(soft < loud * 0.5)
    }

    @Test("주사위마다 충돌음 파형이 다르다")
    func 주사위별_변주() {
        let a = SoundSynth.tock(intensity: 1, die: 0)
        let b = SoundSynth.tock(intensity: 1, die: 4)
        #expect(a != b)
        #expect(SoundSynth.tock(intensity: 1, die: 0) == a, "같은 입력이면 같은 파형")
    }

    @Test("60ms 안에 겹친 충돌은 소리를 건너뛴다")
    @MainActor
    func 충돌음_간격() {
        var now: TimeInterval = 10
        let feedback = FeedbackCoordinator(clock: { now })
        #expect(feedback.shouldPlayTock())
        now += 0.04
        #expect(!feedback.shouldPlayTock())
        now += 0.04   // 앞 소리에서 80ms
        #expect(feedback.shouldPlayTock())
        now += 0.2
        #expect(feedback.shouldPlayTock())
    }
}
