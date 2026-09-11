import Foundation

/// 외부 파일 없이 짧은 효과음을 합성한다. 결정적이라 테스트할 수 있다.
enum SoundSynth {
    static let sampleRate: Double = 44_100

    /// 주사위가 부딪히는 소리. 나무 공진과 아크릴 클릭을 세기로 섞는다 — 약하게 닿으면 둔한 나무 소리,
    /// 세게 닿으면 밝은 클릭이 더해진다. 주사위마다 피치와 노이즈가 달라 다섯 개가 따로 들린다.
    static func tock(intensity: Float, die: Int = 2) -> [Float] {
        let n = Int(0.08 * sampleRate)
        var rng = LCG(seed: UInt64(67 + die * 3))
        let detune = 1 + (Float(die) - 2) * 0.05
        var wood = Resonator(frequency: 700 * detune, q: 8)
        var wood2 = Resonator(frequency: 1300 * detune, q: 10)
        var click = Resonator(frequency: 3600 * detune, q: 12)
        var body = Resonator(frequency: 130, q: 3)
        let brightness = 0.2 + 0.8 * intensity
        let samples = (0..<n).map { i -> Float in
            let t = Float(i) / Float(sampleRate)
            let impulse = (rng.nextFloat() * 2 - 1) * exp(-t * 600)
            let s = wood.run(impulse) * 0.9 + wood2.run(impulse) * 0.4
                + click.run(impulse) * 0.7 * brightness
                + body.run(impulse) * 1.5 * (1 - 0.5 * intensity)
            return s * exp(-t * (30 + 20 * intensity))
        }
        return normalized(samples, peak: 0.22 + 0.63 * intensity)
    }

    /// 최대 진폭을 `peak`로 맞춘다.
    static func normalized(_ samples: [Float], peak: Float) -> [Float] {
        let max = samples.map(abs).max() ?? 0
        return max > 0 ? samples.map { $0 / max * peak } : samples
    }

    /// 2차 공진(밴드패스) 필터. 나무·플라스틱의 울림을 만든다.
    struct Resonator {
        private let b0: Float, a1: Float, a2: Float
        private var y1: Float = 0, y2: Float = 0
        init(frequency: Float, q: Float) {
            let w = 2 * Float.pi * frequency / Float(sampleRate)
            let r = exp(-w / (2 * q))
            a1 = -2 * r * cos(w)
            a2 = r * r
            b0 = 1 - r
        }
        mutating func run(_ x: Float) -> Float {
            let y = b0 * x - a1 * y1 - a2 * y2
            y2 = y1; y1 = y
            return y
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

    /// 공이 컵에 들어가는 "퐁". 물 튀는 노이즈에 낮은 공진.
    static func pong() -> [Float] {
        let n = Int(0.18 * sampleRate)
        var rng = LCG(seed: 91)
        var body = Resonator(frequency: 320, q: 6)
        var splash = Resonator(frequency: 2400, q: 3)
        let samples = (0..<n).map { i -> Float in
            let t = Float(i) / Float(sampleRate)
            let noise = rng.nextFloat() * 2 - 1
            return body.run(noise * exp(-t * 300)) * 1.4 * exp(-t * 18) + splash.run(noise) * 0.25 * exp(-t * 40)
        }
        return normalized(samples, peak: 0.7)
    }

    /// 돌끼리 부딪히는 "딱". 짧고 밝은 클릭.
    static func clack() -> [Float] {
        let n = Int(0.08 * sampleRate)
        var rng = LCG(seed: 131)
        var r1 = Resonator(frequency: 2600, q: 10), r2 = Resonator(frequency: 4100, q: 8)
        let samples = (0..<n).map { i -> Float in
            let t = Float(i) / Float(sampleRate)
            let x = (rng.nextFloat() * 2 - 1) * exp(-t * 900)
            return (r1.run(x) * 0.9 + r2.run(x) * 0.5) * exp(-t * 55)
        }
        return normalized(samples, peak: 0.7)
    }

    /// 판에서 떨어지는 "툭". 낮은 바디에 짧은 노이즈.
    static func drop() -> [Float] {
        let n = Int(0.12 * sampleRate)
        var rng = LCG(seed: 137)
        var body = Resonator(frequency: 110, q: 4), knock = Resonator(frequency: 900, q: 5)
        let samples = (0..<n).map { i -> Float in
            let t = Float(i) / Float(sampleRate)
            let x = (rng.nextFloat() * 2 - 1) * exp(-t * 300)
            return body.run(x) * 2.0 * exp(-t * 20) + knock.run(x) * 0.6 * exp(-t * 60)
        }
        return normalized(samples, peak: 0.7)
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
