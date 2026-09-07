import Foundation

/// 외부 파일 없이 짧은 효과음을 합성한다. 결정적이라 테스트할 수 있다.
enum SoundSynth {
    static let sampleRate: Double = 44_100

    /// 주사위가 부딪히는 "톡". 노이즈 버스트 + 낮은 톤, 지수 감쇠.
    static func tock(intensity: Float) -> [Float] {
        let n = Int(0.06 * sampleRate)
        var rng = LCG(seed: 7)
        return (0..<n).map { i in
            let t = Float(i) / Float(sampleRate)
            let env = exp(-t * 70)
            let noise = rng.nextFloat() * 2 - 1
            let tone = sin(2 * .pi * 180 * t)
            return (noise * 0.6 + tone * 0.4) * env * (0.15 + 0.85 * intensity) * 0.9
        }
    }

    /// 고정 토글 "틱". 2kHz 클릭.
    static func tick() -> [Float] {
        let n = Int(0.025 * sampleRate)
        return (0..<n).map { i in
            let t = Float(i) / Float(sampleRate)
            return sin(2 * .pi * 2000 * t) * exp(-t * 200) * 0.5
        }
    }

    /// 기록 "탁". 노이즈 버스트 + 120Hz.
    static func stamp() -> [Float] {
        let n = Int(0.12 * sampleRate)
        var rng = LCG(seed: 11)
        return (0..<n).map { i in
            let t = Float(i) / Float(sampleRate)
            let noise = rng.nextFloat() * 2 - 1
            return (noise * 0.5 * exp(-t * 90) + sin(2 * .pi * 120 * t) * 0.5 * exp(-t * 25)) * 0.8
        }
    }

    /// 야추·보너스 "딩". C5-E5-G5 감쇠.
    static func chime() -> [Float] {
        let n = Int(0.4 * sampleRate)
        let freqs: [Float] = [523.25, 659.25, 783.99]
        return (0..<n).map { i in
            let t = Float(i) / Float(sampleRate)
            let sum = freqs.enumerated().reduce(Float(0)) { acc, f in
                acc + sin(2 * .pi * f.element * t) * exp(-t * (4 + Float(f.offset)))
            }
            return sum / 3 * 0.8
        }
    }

    /// 결정적 난수. 같은 파형이 나온다.
    struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func nextFloat() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(state >> 40) / Float(1 << 24)
        }
    }
}
