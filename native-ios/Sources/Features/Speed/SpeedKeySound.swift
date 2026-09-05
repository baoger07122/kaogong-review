import AVFAudio
import Combine

/// A pre-started audio engine keeps keypad feedback on the render thread.
/// Restarting a file-backed player has a noticeable startup path on some iPads;
/// WebAudio does not because its context remains running.
@MainActor
final class SpeedKeySound: ObservableObject {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var tone: AVAudioPCMBuffer?
    private var nextPlayer = 0

    func prepare() {
        guard players.isEmpty || !engine.isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(Double(SpeedKeyTone.sampleRate))
            try session.setPreferredIOBufferDuration(0.0029)
            try session.setActive(true)

            if tone == nil {
                tone = SpeedKeyTone.pcmBuffer()
            }
            if players.isEmpty, let tone {
                players = (0..<4).map { _ in
                    let player = AVAudioPlayerNode()
                    engine.attach(player)
                    engine.connect(player, to: engine.mainMixerNode, format: tone.format)
                    return player
                }
            }
            engine.prepare()
            if !engine.isRunning { try engine.start() }
            players.forEach { if !$0.isPlaying { $0.play() } }
        } catch {
            // An unavailable/interrupted audio route must never block answer entry.
            engine.stop()
        }
    }

    func play() {
        prepare()
        guard engine.isRunning, let tone, !players.isEmpty else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        // The four already-running nodes allow rapid taps to overlap without
        // stopping, seeking or restarting an audio object on the main thread.
        player.scheduleBuffer(tone, at: nil, options: [.interrupts])
    }

    func stop() {
        players.forEach { $0.stop() }
        engine.stop()
        nextPlayer = 0
    }
}

private extension SpeedKeyTone {
    static func pcmBuffer() -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(sampleRate),
            channels: 1
        ) else { return nil }
        let pcm = samples()
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(pcm.count)
        ), let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(pcm.count)
        for (index, sample) in pcm.enumerated() {
            channel[index] = Float(sample) / Float(Int16.max)
        }
        return buffer
    }
}
