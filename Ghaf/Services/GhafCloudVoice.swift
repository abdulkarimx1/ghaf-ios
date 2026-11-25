import Foundation
import AVFoundation

/// Natural speech for Ghaf AI's voice mode, from Ghaf's server (Gemini speech, Arabic and English).
/// Only used when the user has turned on Cloud AI; only reply text and the selected voice are sent.
@MainActor
final class GhafCloudVoice: NSObject, AVAudioPlayerDelegate {
    enum SpeechResult { case played, limitReached, unavailable, voiceOff }
    static let shared = GhafCloudVoice()
    private static let endpoint = URL(string: "https://ghaf-ai.ghafapp.workers.dev/speak")!

    private var player: AVAudioPlayer?
    private var meter: Timer?
    private var onFinish: (() -> Void)?
    /// Loudness 0…1 while speaking, for the voice-mode orb.
    var onLevel: ((Float) -> Void)?

    var isPlaying: Bool { player?.isPlaying ?? false }

    @discardableResult
    func playBundledGoodbye(character: String, arabic: Bool, userSex: String? = nil, onFinish: @escaping () -> Void) -> Bool {
        playBundledClip(prefix: "goodbye", character: character, arabic: arabic, userSex: userSex, onFinish: onFinish)
    }

    @discardableResult
    func playBundledError(character: String, arabic: Bool, userSex: String? = nil, onFinish: @escaping () -> Void = {}) -> Bool {
        playBundledClip(prefix: "error", character: character, arabic: arabic, userSex: userSex, onFinish: onFinish)
    }

    @discardableResult
    func playBundledSample(character: String, arabic: Bool, userSex: String? = nil, onFinish: @escaping () -> Void = {}) -> Bool {
        playBundledClip(prefix: "sample", character: character, arabic: arabic, userSex: userSex, onFinish: onFinish)
    }

    /// Owner 1.31: a man gets Hamad and a woman gets Mariam by default; once the user picks a voice themselves, it stays.
    static func matchVoice(toSex sex: String?) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "ghaf.ai.voiceChosenByUser") else { return }
        switch sex {
        case "male": defaults.set("Hamad", forKey: "ghaf.ai.voiceCharacter")
        case "female": defaults.set("Mariam", forKey: "ghaf.ai.voiceCharacter")
        default: break
        }
    }

    @discardableResult
    private func playBundledClip(prefix: String, character: String, arabic: Bool, userSex: String? = nil, onFinish: @escaping () -> Void) -> Bool {
        let name = "\(prefix)_\(character == "Mariam" ? "Mariam" : "Hamad")_\(arabic ? "ar" : "en")"
        // V16: the base Arabic clips address a man (ك). Female users get the ج recording, anyone else the neutral one.
        let variant = !arabic || userSex == "male" ? nil : (userSex == "female" ? "\(name)_female" : "\(name)_neutral")
        guard let url = variant.flatMap({ Bundle.main.url(forResource: $0, withExtension: "wav") })
                ?? Bundle.main.url(forResource: name, withExtension: "wav"),
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

    func speak(_ text: String, arabic: Bool, character: String, onStart: @escaping () -> Void, onFinish: @escaping () -> Void) async -> SpeechResult {
        if GhafCloudAI.fixtureNetworkIsDisabledForRequests { return .unavailable }
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 12)
        request.httpMethod = "POST"
        GhafCloudAI.setBuildHeader(on: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(GhafCloudAI.deviceID, forHTTPHeaderField: "X-Ghaf-Device")
        if let code = Keychain.read(GhafCloudAI.accessCodeKey) { request.setValue(code, forHTTPHeaderField: "X-Ghaf-Code") }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text, "language": arabic ? "ar" : "en", "character": character, "tier": GhafAITier.current])
        guard var (data, response) = try? await URLSession.shared.data(for: request),
              var status = (response as? HTTPURLResponse)?.statusCode else { return .unavailable }
        // Row 15: the voice model is often briefly busy (503); one retry keeps Hamad/Mariam speaking.
        if status == 503 {
            try? await Task.sleep(for: .seconds(1))
            guard let retry = try? await URLSession.shared.data(for: request),
                  let retryStatus = (retry.1 as? HTTPURLResponse)?.statusCode else { return .unavailable }
            (data, response, status) = (retry.0, retry.1, retryStatus)
        }
        if status == 429 { return .limitReached }
        // Owner rule: only Hamad/Mariam may speak; the server answers 410 while their voices are off.
        if status == 410 { return .voiceOff }
        if status == 401, Keychain.read(GhafCloudAI.accessCodeKey) != nil { GhafProAccess.removeAccessCode() }
        guard status == 200, let player = try? AVAudioPlayer(data: data) else { return .unavailable }
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        player.delegate = self
        player.isMeteringEnabled = true
        self.player = player
        self.onFinish = onFinish
        guard player.play() else { return .unavailable }
        onStart()
        meter = Timer.scheduledTimer(withTimeInterval: 1 / 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                player.updateMeters()
                // -50 dB (quiet) … 0 dB (loud) mapped to 0…1.
                self.onLevel?(max(0, min(1, (player.averagePower(forChannel: 0) + 50) / 50)))
            }
        }
        return .played
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
