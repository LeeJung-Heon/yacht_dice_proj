import AVFoundation

/// 합성한 버퍼를 재생한다. 엔진이 못 뜨면 조용히 포기한다 — 소리 없는 게임이 죽는 게임보다 낫다.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var ready = false
    private var failed = false
    private var cache: [String: AVAudioPCMBuffer] = [:]

    private func startIfNeeded() {
        guard !ready, !failed else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.sampleRate, channels: 1) else {
                failed = true
                return
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            try engine.start()
            node.play()
            self.format = format
            ready = true
        } catch {
            failed = true
        }
    }

    /// `key`가 같으면 버퍼를 다시 만들지 않는다.
    func play(_ samples: @autoclosure () -> [Float], key: String) {
        guard FeedbackSettings.soundEnabled else { return }
        startIfNeeded()
        guard ready, let format else { return }
        let buffer: AVAudioPCMBuffer
        if let cached = cache[key] {
            buffer = cached
        } else {
            let data = samples()
            guard let made = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count)),
                  let channel = made.floatChannelData?[0] else { return }
            made.frameLength = AVAudioFrameCount(data.count)
            for (i, s) in data.enumerated() { channel[i] = s }
            cache[key] = made
            buffer = made
        }
        node.scheduleBuffer(buffer, completionHandler: nil)
    }
}
