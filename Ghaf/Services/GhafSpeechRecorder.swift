import Foundation
import AVFoundation
import Combine
import Speech

@MainActor
final class GhafSpeechRecorder: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequests: [String: SFSpeechAudioBufferRecognitionRequest] = [:]
    private var recognitionTasks: [String: SFSpeechRecognitionTask] = [:]
    private var candidateResults: [String: (text: String, confidence: Float)] = [:]
    private var activeRecognizers: [String: SFSpeechRecognizer] = [:]
    private var activeLanguageCode = "en"

    func start(languageCode: String) async {
        guard !isRecording else { return }
        errorMessage = nil
        transcript = ""
        activeLanguageCode = languageCode
        candidateResults.removeAll()
        cancelRecognitionTasks()

        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            errorMessage = languageCode == "ar"
                ? "يرجى السماح بالتعرّف على الكلام من إعدادات iPhone."
                : "Allow Speech Recognition in iPhone Settings to use voice entry."
            return
        }

        let microphoneGranted = await requestMicrophonePermission()
        guard microphoneGranted else {
            errorMessage = languageCode == "ar"
                ? "يرجى السماح باستخدام الميكروفون لتسجيل العمليات."
                : "Allow microphone access to record transactions."
            return
        }

        // Run Arabic and English recognition side by side. The selected UI language
        // controls labels only; it must not constrain the spoken language.
        let recognizers = ["en-US", "ar-SA"].compactMap { identifier -> (String, SFSpeechRecognizer)? in
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)),
                  recognizer.isAvailable else { return nil }
            let code = identifier.hasPrefix("ar") ? "ar" : "en"
            return (code, recognizer)
        }

        guard !recognizers.isEmpty else {
            errorMessage = languageCode == "ar"
                ? "التعرّف على الكلام بالعربية والإنجليزية غير متاح حالياً."
                : "Arabic and English speech recognition are currently unavailable."
            return
        }

        activeRecognizers = Dictionary(uniqueKeysWithValues: recognizers)
        do {
            try configureAndStartAudio()
        } catch {
            errorMessage = languageCode == "ar"
                ? "تعذر بدء التسجيل. تحقق من إعدادات الميكروفون."
                : "Could not start recording. Check microphone availability."
            stop()
        }
    }

    func stop() {
        guard isRecording || audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequests.values.forEach { $0.endAudio() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
    }

    func reset() {
        stop()
        cancelRecognitionTasks()
        recognitionRequests.removeAll()
        activeRecognizers.removeAll()
        candidateResults.removeAll()
        transcript = ""
        errorMessage = nil
    }

    private func configureAndStartAudio() throws {
        cancelRecognitionTasks()
        recognitionRequests.removeAll()
        candidateResults.removeAll()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        for (language, recognizer) in activeRecognizers {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            recognitionRequests[language] = request

            recognitionTasks[language] = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let confidence = result.bestTranscription.segments.map(\.confidence).reduce(0, +)
                        let count = max(result.bestTranscription.segments.count, 1)
                        self.candidateResults[language] = (
                            result.bestTranscription.formattedString,
                            confidence / Float(count)
                        )
                        self.updateChosenTranscript()
                    }
                    if error != nil {
                        self.recognitionTasks[language] = nil
                        if self.recognitionTasks.values.allSatisfy({ $0 == nil }) && self.isRecording {
                            self.errorMessage = self.activeLanguageCode == "ar"
                                ? "توقف التعرّف على الكلام. حاول مرة أخرى."
                                : "Speech recognition stopped. Try again."
                            self.stop()
                        }
                    }
                }
            }
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for request in self.recognitionRequests.values {
                    request.append(buffer)
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    private func updateChosenTranscript() {
        guard !candidateResults.isEmpty else { return }

        let candidates = candidateResults.map { language, candidate -> (language: String, text: String, score: Float) in
            let arabicCount = candidate.text.unicodeScalars.filter {
                (0x0600...0x06FF).contains(Int($0.value))
            }.count
            let latinCount = candidate.text.unicodeScalars.filter {
                (0x0041...0x007A).contains(Int($0.value))
            }.count
            let scriptFit: Float
            if arabicCount > 0 {
                scriptFit = language == "ar" ? 0.55 : 0.15
            } else {
                scriptFit = language == "en" ? 0.35 : 0
            }
            let lengthFit = min(Float(candidate.text.count) / 90, 1) * 0.10
            let mixedScriptBonus: Float = arabicCount > 0 && latinCount > 0 ? 0.12 : 0
            return (
                language,
                candidate.text,
                candidate.confidence * 0.35 + scriptFit + lengthFit + mixedScriptBonus
            )
        }

        guard let chosen = candidates.max(by: { $0.score < $1.score }) else { return }
        transcript = chosen.text
        activeLanguageCode = chosen.language
    }

    private func cancelRecognitionTasks() {
        recognitionTasks.values.forEach { $0.cancel() }
        recognitionTasks.removeAll()
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
