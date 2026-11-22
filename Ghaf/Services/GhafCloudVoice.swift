import Foundation
import AVFoundation

/// Natural speech for Ghaf AI's voice mode, from Ghaf's server (Gemini speech, Arabic and English).
/// Only used when the user has turned on Cloud AI; only reply text and the selected voice are sent.
@MainActor
final class GhafCloudVoice: NSObject, AVAudioPlayerDelegate {
    static let shared = GhafCloudVoice()
    private static let endpoint = URL(string: "https://ghaf-ai.ghafapp.workers.dev/speak")!

    private var player: AVAudioPlayer?
    private var meter: Timer?
    private var onFinish: (() -> Void)?
    /// Loudness 0…1 while speaking, for the voice-mode orb.
    var onLevel: ((Float) -> Void)?

    var isPlaying: Bool { player?.isPlaying ?? false }

    @discardableResult
    func playBundledGoodbye(character: String, arabic: Bool, onFinish: @escaping () -> Void) -> Bool {
        let name = "goodbye_\(character == "Mariam" ? "Mariam" : "Hamad")_\(arabic ? "ar" : "en")"
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        player.delegate = self
        self.player = player
        self.onFinish = onFinish
        return player.play()
    }

    func speak(_ text: String, arabic: Bool, character: String, onStart: @escaping () -> Void, onFinish: @escaping () -> Void) async -> Bool {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(GhafCloudAI.deviceID, forHTTPHeaderField: "X-Ghaf-Device")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "language": arabic ? "ar" : "en", "character": character, "tier": GhafAITier.current])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let player = try? AVAudioPlayer(data: data) else { return false }
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        player.delegate = self
        player.isMeteringEnabled = true
        self.player = player
        self.onFinish = onFinish
        guard player.play() else { return false }
        onStart()
        meter = Timer.scheduledTimer(withTimeInterval: 1 / 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                player.updateMeters()
                // -50 dB (quiet) … 0 dB (loud) mapped to 0…1.
                self.onLevel?(max(0, min(1, (player.averagePower(forChannel: 0) + 50) / 50)))
            }
        }
        return true
    }

    func stop() {
        meter?.invalidate(); meter = nil
        player?.stop(); player = nil
        onLevel?(0)
        onLevel = nil
        onFinish = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.meter?.invalidate(); self.meter = nil
            self.onLevel?(0)
            self.onLevel = nil
            let finish = self.onFinish
            self.onFinish = nil
            self.player = nil
            finish?()
        }
    }
}
