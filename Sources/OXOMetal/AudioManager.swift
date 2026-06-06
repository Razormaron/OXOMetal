import AVFoundation

final class AudioManager {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let queue  = DispatchQueue(label: "oxo.audio", qos: .userInteractive)

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        try? engine.start()
    }

    func playMove() { queue.async { self.tone(freq: 660,  dur: 0.07, amp: 0.25) } }
    func playWin()  { queue.async { self.tone(freq: 1046, dur: 0.25, amp: 0.30) } }
    func playDraw() { queue.async { self.tone(freq: 330,  dur: 0.20, amp: 0.20) } }

    private func tone(freq: Float, dur: Float, amp: Float) {
        let rate   = Double(44100)
        let frames = AVAudioFrameCount(rate * Double(dur))
        let fmt    = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else { return }
        buf.frameLength = frames
        let data = buf.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Float(i) / Float(rate)
            let env = min(1.0, min(t * 40, (dur - t) * 40))   // fast attack/release
            data[i] = sin(2 * .pi * freq * t) * amp * env
        }
        player.scheduleBuffer(buf, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}
