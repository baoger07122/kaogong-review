import AVFAudio
import Combine

/// Prepare once per practice session, not during SwiftUI body evaluation or for every tap.
@MainActor
final class SpeedKeySound: ObservableObject {
    private var players: [AVAudioPlayer] = []
    private var nextPlayer = 0

    func prepare() {
        guard players.isEmpty else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let data = SpeedKeyTone.wavData()
            players = try (0..<4).map { _ in
                let player = try AVAudioPlayer(data: data)
                player.volume = 1 // Never change the device's system volume.
                player.prepareToPlay()
                return player
            }
        } catch {
            // An unavailable/interrupted audio route must never block answer entry.
            players = []
        }
    }

    func play() {
        prepare()
        guard !players.isEmpty else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.currentTime = 0
        player.play()
    }

    func stop() {
        players.forEach { $0.stop() }
        players = []
        nextPlayer = 0
    }
}
