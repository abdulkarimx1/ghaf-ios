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
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var activeLanguageCode = "en"

    func start(languageCode: String) async {
        guard !isRecording else { return }
        errorMessage = nil
        transcript = ""
        activeLanguageCode = languageCode

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

        let localeIdentifier = languageCode == "ar" ? "ar-SA" : "en-US"
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable else {
            errorMessage = languageCode == "ar"
                ? "التعرّف على الكلام بهذه اللغة غير متاح حالياً."
                : "Speech recognition is currently unavailable for this language."
            return
        }
        speechRecognizer = recognizer

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
        recognitionRequest?.endAudio()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
    }

    func reset() {
        stop()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        transcript = ""
        errorMessage = nil
    }

    private func configureAndStartAudio() throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = speechRecognizer?.supportsOnDeviceRecognition ?? false
        recognitionRequest = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        isRecording = true
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                }
                if let error {
                    self?.errorMessage = self?.activeLanguageCode == "ar"
                        ? "توقف التعرّف على الكلام. حاول مرة أخرى."
                        : "Speech recognition stopped. Try again."
                    self?.stop()
                }
            }
        }
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

