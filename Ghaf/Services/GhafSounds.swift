import AVFoundation
import UIKit

/// Small, synthesised in-app cues. The ambient category respects the silent switch.
@MainActor
final class GhafSounds {
    enum Cue: String { case orbOn = "orb_on", orbOff = "orb_off", added, deleted, streak }

    static let shared = GhafSounds()
    static let addedDelay: TimeInterval = 2.0
    private var players: [String: AVAudioPlayer] = [:]

    private init() {
        for cue in [Cue.orbOn, .orbOff, .added, .deleted, .streak] {
            guard let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[cue.rawValue] = player
        }
    }

    func play(_ cue: Cue) {
        guard UserDefaults.standard.object(forKey: "ghaf.inAppSounds") as? Bool ?? true,
              UIApplication.shared.applicationState == .active else { return }
        let session = AVAudioSession.sharedInstance()
        // Never replace the live voice session's playAndRecord configuration.
        if session.category != .playAndRecord {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
        }
        guard let player = players[cue.rawValue] else { return }
        // The shared player stays alive for its full sample; a repeated cue cannot restart and cut it off.
        guard !player.isPlaying else { return }
        player.currentTime = 0
        if cue == .added { player.volume = 0.2 }
        player.play()
    }

    func playSimulatorCheckIfRequested() {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-GhafSoundCheck") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_500))
            for cue in [Cue.orbOn, .orbOff, .added, .deleted, .streak] {
                play(cue)
                try? await Task.sleep(for: .milliseconds(800))
            }
        }
#endif
    }
}
