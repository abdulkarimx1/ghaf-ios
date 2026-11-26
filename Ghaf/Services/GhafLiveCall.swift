import AVFoundation
import Combine
import Foundation
import GhafCore
import OSLog

@MainActor
final class GhafLiveCall: ObservableObject {
    enum Phase: Equatable { case connecting, listening, speaking, thinking, reconnecting, ended(String) }
    @Published private(set) var phase: Phase = .ended("")
    @Published private(set) var inputLevel: Float = 0
    @Published private(set) var outputLevel: Float = 0
    @Published var isMuted = false
    @Published private(set) var elapsed: TimeInterval = 0
    var onInputTranscript: ((String, Bool) -> Void)?
    var onOutputTranscript: ((String, Bool) -> Void)?
    var onToolCall: ((LiveToolCall) async -> [String: LiveJSON])?
    var onToolCancellation: (([String]) -> Void)?
    var onTurnFinished: (() -> Void)?
    var onSpeechLimit: (() -> Void)?

    private let session = URLSession.shared
    private var socket: URLSessionWebSocketTask?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var inputConverter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var priorCategory: AVAudioSession.Category = .soloAmbient
    private var priorMode: AVAudioSession.Mode = .default
    private var priorOptions: AVAudioSession.CategoryOptions = []
    private var receiveTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var turnLimitTask: Task<Void, Never>?
    private var turnLimitActive = false
    private var setupWaiter: CheckedContinuation<Void, Error>?
    private var setupTimeout: Task<Void, Never>?
    private var tokenModel = "models/gemini-3.8-live"
    private var language = "en"
    private var character = "Hamad"
    private var tier = "free"
    private var instruction = ""
    private var tools: [LiveFunctionDeclaration] = []
    private var resumeHandle: String?
    private var startedAt = Date()
    private var reconnects = 0
    private var stopping = false
    private var toolTasks: [String: Task<[String: LiveJSON], Never>] = [:]
    private var cancelledToolIDs = Set<String>()
    private var queuedOutputBuffers = 0
    private var turnCompleteReceived = false
    private var speechTextBuffer = ""
    private var speechChunks: [String] = []
    private var speechRequestTask: Task<Void, Never>?
    private var speechRequestActive = false
    private var speechDisabledForTurn = false
    private var speechTurnID = 0
    private var turnFinishNotified = false
    private var inputContinuation: AsyncStream<Data>.Continuation?
    private var inputSenderTask: Task<Void, Never>?
    private var capturingUserTurn = false
    /// Mic audio flows only after activityStart has been sent, so the server never gets speech before the turn opens.
    private var audioGateOpen = false
    private var userRequestedTurn = false
    private var pendingEndReason: String?
    var isCapturingUserTurn: Bool { capturingUserTurn }

    func start(language: String, character: String, tier: String, systemInstruction: String, tools: [LiveFunctionDeclaration]) async throws {
        guard GhafCloudAI.isEnabled else { throw GhafCloudAI.Failure.unavailable }
        self.language = language; self.character = character; self.tier = tier; instruction = systemInstruction; self.tools = tools
        stopping = false; reconnects = 0; startedAt = Date(); turnCompleteReceived = false; phase = .connecting
        clearSpeechQueue(disableTurn: false)
        capturingUserTurn = false; audioGateOpen = false; userRequestedTurn = false
        let stream = AsyncStream<Data>.makeStream()
        inputContinuation = stream.continuation
        inputSenderTask = Task { [weak self, stream = stream.stream] in
            for await chunk in stream {
                guard let self, !self.stopping, self.audioGateOpen else { continue }
                guard !self.isMuted else { self.inputLevel = 0; continue }
                let samples = chunk.withUnsafeBytes { raw in Array(raw.bindMemory(to: Int16.self)) }
                let rms = sqrt(samples.reduce(Float.zero) { $0 + pow(Float($1) / 32768, 2) } / max(1, Float(samples.count)))
                self.inputLevel = min(1, rms * 3)
                for start in stride(from: 0, to: chunk.count, by: 640) {
                    guard self.audioGateOpen, !self.isMuted,
                          let message = try? LiveEncoder.audio(chunk.subdata(in: start..<min(start + 640, chunk.count))) else { continue }
                    self.startTurnLimitIfNeeded()
                    try? await self.send(message)
                }
            }
        }
        let audioSession = AVAudioSession.sharedInstance()
        priorCategory = audioSession.category; priorMode = audioSession.mode; priorOptions = audioSession.categoryOptions
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: audioSession)
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChanged(_:)), name: AVAudioSession.routeChangeNotification, object: audioSession)
        try await connect(resuming: nil)
    }

    func end(reason: String = "") {
        if !stopping && (queuedOutputBuffers > 0 || phase == .speaking || phase == .thinking) {
            pendingEndReason = reason
            // Safety net: if the reply never reports completion, still close the call.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard let self, !self.stopping, let pending = self.pendingEndReason else { return }
                self.endNow(reason: pending)
            }
            if capturingUserTurn {
                capturingUserTurn = false
                audioGateOpen = false
                if let message = try? LiveEncoder.activityEnd() { Task { try? await send(message) } }
            }
            engine.inputNode.removeTap(onBus: 0)
            return
        }
        endNow(reason: reason)
    }

    private func endNow(reason: String) {
        stopping = true
        pendingEndReason = nil
        inputContinuation?.finish(); inputContinuation = nil
        inputSenderTask?.cancel(); inputSenderTask = nil
        setupWaiter?.resume(throwing: CancellationError()); setupWaiter = nil
        setupTimeout?.cancel(); setupTimeout = nil
        receiveTask?.cancel(); receiveTask = nil
        toolTasks.values.forEach { $0.cancel() }; toolTasks.removeAll(); cancelledToolIDs.removeAll()
        elapsedTask?.cancel(); elapsedTask = nil
        turnLimitTask?.cancel(); turnLimitTask = nil
        turnLimitActive = false
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        NotificationCenter.default.removeObserver(self)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop(); player.stop()
        onInputTranscript = nil; onOutputTranscript = nil
        onToolCall = nil; onToolCancellation = nil; onTurnFinished = nil; onSpeechLimit = nil
        clearSpeechQueue(disableTurn: true)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? AVAudioSession.sharedInstance().setCategory(priorCategory, mode: priorMode, options: priorOptions)
        phase = .ended(reason)
        inputLevel = 0; outputLevel = 0
    }

    func sendText(_ text: String) {
        guard !stopping, !text.isEmpty, let message = try? LiveEncoder.text(text) else { return }
        Task { try? await send(message) }
    }

    func setMuted(_ muted: Bool) { isMuted = muted }

    func beginUserTurn() {
        guard !stopping, phase != .connecting, !capturingUserTurn else { return }
        userRequestedTurn = true
        turnCompleteReceived = false
        turnFinishNotified = false
        clearSpeechQueue(disableTurn: false)
        capturingUserTurn = true
        audioGateOpen = true
        phase = .listening
        startTurnLimitIfNeeded()
    }

    /// Stops queued model audio immediately so a new user utterance cannot be answered over.
    func interruptPlayback() {
        guard !stopping else { return }
        player.stop()
        player.reset()
        queuedOutputBuffers = 0
        outputLevel = 0
        turnCompleteReceived = false
        pendingEndReason = nil
        phase = .listening
    }

    func endUserTurn() {
        guard !stopping, capturingUserTurn else { return }
        capturingUserTurn = false
        audioGateOpen = false
        inputLevel = 0
        if let message = try? LiveEncoder.activityEnd() { Task { try? await send(message) } }
    }

    private struct SetupRejected: Error {}

    private func connect(resuming handle: String?, responseModalitiesInGenerationConfig: Bool = true) async throws {
        let token = try await fetchToken()
        tokenModel = token.model
        var components = URLComponents(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained")!
        components.queryItems = [URLQueryItem(name: "access_token", value: token.token)]
        let newSocket = session.webSocketTask(with: components.url!)
        self.socket = newSocket; newSocket.resume()
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in await self?.receiveLoop(newSocket) }
        do { try await withCheckedThrowingContinuation { continuation in
            setupWaiter = continuation
            setupTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard let self, self.setupWaiter != nil else { return }
                self.setupWaiter?.resume(throwing: URLError(.timedOut)); self.setupWaiter = nil
            }
            Task { [weak self] in
                guard let self else { return }
                do { try await self.send(LiveSetup(model: token.model, systemInstruction: self.instruction,
                                                    tools: self.tools, resumptionHandle: handle)
                                            .encoded(responseModalitiesInGenerationConfig: responseModalitiesInGenerationConfig)) }
                catch { self.setupWaiter?.resume(throwing: error); self.setupWaiter = nil }
            }
        } } catch {
            setupTimeout?.cancel(); setupTimeout = nil
            guard responseModalitiesInGenerationConfig, error is SetupRejected else { throw error }
            receiveTask?.cancel(); receiveTask = nil
            socket?.cancel(with: .protocolError, reason: nil); socket = nil
            phase = .reconnecting
            try await connect(resuming: handle, responseModalitiesInGenerationConfig: false)
            return
        }
        setupTimeout?.cancel(); setupTimeout = nil
        if !engine.isRunning { try startAudio() }
        phase = .listening
        if elapsedTask == nil { elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.elapsed = Date().timeIntervalSince(self.startedAt)
            }
        } }
    }

    private struct Token: Decodable { let token: String; let model: String }

    private func fetchToken() async throws -> Token {
        if GhafCloudAI.fixtureNetworkIsDisabledForRequests { throw GhafCloudAI.Failure.unavailable }
        guard let url = URL(string: "/live-token", relativeTo: GhafCloudAI.endpoint.deletingLastPathComponent()) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        GhafCloudAI.setBuildHeader(on: &request)
        request.setValue(GhafCloudAI.deviceID, forHTTPHeaderField: "X-Ghaf-Device")
        if let code = Keychain.read(GhafCloudAI.accessCodeKey) { request.setValue(code, forHTTPHeaderField: "X-Ghaf-Code") }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["language": language, "character": character, "tier": tier])
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw URLError(.badServerResponse) }
        if status == 429 { throw GhafCloudAI.Failure.dailyLimit }
        if status == 410 { throw GhafCloudAI.Failure.voiceOff }
        if status == 401, Keychain.read(GhafCloudAI.accessCodeKey) != nil { GhafProAccess.removeAccessCode() }
        guard status == 200, let token = try? JSONDecoder().decode(Token.self, from: data) else { throw GhafCloudAI.Failure.unavailable }
        return token
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                let data: Data
                switch message { case .data(let bytes): data = bytes; case .string(let string): data = Data(string.utf8); @unknown default: continue }
                for event in LiveServerEvent.parse(data) { await handle(event) }
            }
        } catch {
            guard !stopping, !Task.isCancelled, task === socket else { return }
            log(error)
            await reconnect()
        }
    }

    private func handle(_ event: LiveServerEvent) async {
        switch event {
        case .setupComplete:
            setupWaiter?.resume(); setupWaiter = nil
        case .audio:
            // The server token is locked to TEXT; speaking is always done with approved Gemini TTS below.
            break
        case .inputTranscript(let text): onInputTranscript?(text, false)
        case .outputTranscript(let text):
            finishTurnLimit()
            onOutputTranscript?(text, false)
            if !text.isEmpty { appendSpeechText(text) }
        case .interrupted where userRequestedTurn:
            player.stop(); player.reset(); queuedOutputBuffers = 0; outputLevel = 0
            clearSpeechQueue(disableTurn: true)
            phase = .listening
            onOutputTranscript?("", true)
        case .interrupted: break
        case .turnComplete:
            finishTurnLimit()
            capturingUserTurn = false
            audioGateOpen = false
            inputLevel = 0
            onInputTranscript?("", true); onOutputTranscript?("", true)
            turnCompleteReceived = true
            userRequestedTurn = false
            flushSpeechText()
            startNextSpeechRequest()
            finishSpeechTurnIfReady()
        case .toolCalls(let calls):
            phase = .thinking
            for call in calls {
                toolTasks[call.id] = Task { [weak self] in await self?.onToolCall?(call) ?? [:] }
            }
            Task { [weak self] in await self?.finishTools(calls) }
        case .toolCancellation(let ids):
            ids.forEach { toolTasks[$0]?.cancel(); cancelledToolIDs.insert($0) }
            onToolCancellation?(ids)
        case .resumption(let handle): if let handle { resumeHandle = handle }
        case .goAway: await reconnect()
        case .error:
            if let waiter = setupWaiter {
                setupWaiter = nil
                waiter.resume(throwing: SetupRejected())
            } else { log(URLError(.cannotParseResponse)) }
        case .unknown: break
        }
    }

    private func reconnect() async {
        guard !stopping else { return }
        finishTurnLimit()
        guard reconnects < 3, phase != .reconnecting else { return }
        reconnects += 1; phase = .reconnecting
        socket?.cancel(with: .goingAway, reason: nil)
        do { try await connect(resuming: resumeHandle) } catch { log(error); end(reason: "connection_lost") }
    }

    private func startTurnLimitIfNeeded() {
        guard !turnLimitActive, !stopping else { return }
        turnLimitActive = true
        turnLimitTask?.cancel()
        turnLimitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled, !self.stopping, self.turnLimitActive else { return }
            self.end(reason: "turn_limit")
        }
    }

    private func finishTurnLimit() {
        turnLimitActive = false
        turnLimitTask?.cancel()
        turnLimitTask = nil
    }

    private func finishTools(_ calls: [LiveToolCall]) async {
        var replies: [(id: String, name: String, response: [String: LiveJSON])] = []
        for call in calls {
            guard let task = toolTasks[call.id] else { continue }
            let result = await task.value
            toolTasks[call.id] = nil
            if cancelledToolIDs.remove(call.id) == nil { replies.append((call.id, call.name, result)) }
        }
        if !replies.isEmpty, let data = try? LiveEncoder.toolResponse(replies) { try? await send(data) }
        if toolTasks.isEmpty && !stopping {
            phase = .listening
            finishSpeechTurnIfReady()
        }
    }

    private func send(_ data: Data) async throws {
        guard let socket else { throw URLError(.notConnectedToInternet) }
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func startAudio() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audioSession.setActive(true)
        let input = engine.inputNode
        let hardware = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: hardware, to: target) else { throw URLError(.cannotDecodeContentData) }
        inputConverter = converter; outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)
        if engine.attachedNodes.contains(player) {
            engine.disconnectNodeOutput(player)
            engine.detach(player)
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
        let continuation = inputContinuation
        input.installTap(onBus: 0, bufferSize: 2048, format: hardware) { [weak self, continuation] buffer, _ in
            guard let self else { return }
            self.convert(buffer, target: target, converter: converter, continuation: continuation)
        }
        engine.prepare(); try engine.start()
        if !player.isPlaying { player.play() }
    }

    private nonisolated func convert(_ buffer: AVAudioPCMBuffer, target: AVAudioFormat, converter: AVAudioConverter, continuation: AsyncStream<Data>.Continuation?) {
        let ratio = target.sampleRate / buffer.format.sampleRate
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1) else { return }
        var supplied = false
        converter.convert(to: converted, error: nil) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return buffer
        }
        guard let bytes = converted.int16ChannelData else { return }
        let data = Data(bytes: bytes[0], count: Int(converted.frameLength) * MemoryLayout<Int16>.size)
        continuation?.yield(data)
    }

    private func appendSpeechText(_ text: String) {
        speechTextBuffer += text
        extractSpeechChunks(flush: false)
    }

    private func flushSpeechText() {
        extractSpeechChunks(flush: true)
    }

    private func extractSpeechChunks(flush: Bool) {
        while !speechTextBuffer.isEmpty {
            let characters = Array(speechTextBuffer)
            let boundary = characters.indices.first { index in
                let character = characters[index]
                return (character == "." || character == "!" || character == "?" || character == "؟" || character == "\n")
                    && index + 1 >= 25
            }
            var length: Int?
            if let boundary { length = boundary + 1 }
            else if flush { length = characters.count }
            else if characters.count > 680 {
                length = characters[..<min(680, characters.count)].lastIndex(where: { $0.isWhitespace }).map { $0 + 1 } ?? 680
            }
            guard let length else { break }
            let raw = String(characters.prefix(length))
            let chunk = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            speechTextBuffer = String(characters.dropFirst(length))
            if !chunk.isEmpty { speechChunks.append(chunk) }
        }
        startNextSpeechRequest()
    }

    private func startNextSpeechRequest() {
        guard !stopping, !speechDisabledForTurn, !speechRequestActive, !speechChunks.isEmpty else {
            finishSpeechTurnIfReady()
            return
        }
        let text = speechChunks.removeFirst()
        speechRequestActive = true
        let requestTurn = speechTurnID
        speechRequestTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.fetchSpeech(text)
            guard !Task.isCancelled, self.speechTurnID == requestTurn else { return }
            self.speechRequestTask = nil
            self.speechRequestActive = false
            switch result {
            case .audio(let wav):
                guard wav.count > 44, String(data: wav.prefix(4), encoding: .ascii) == "RIFF" else {
                    self.stopSpeechForTurn()
                    return
                }
                self.playPCM(wav.subdata(in: 44..<wav.count))
                // Start the next fetch immediately while the current chunk plays.
                self.startNextSpeechRequest()
            case .limit:
                self.stopSpeechForTurn()
                self.phase = .listening
                self.onSpeechLimit?()
            case .unavailable:
                self.stopSpeechForTurn()
            }
            self.finishSpeechTurnIfReady()
        }
    }

    private enum SpeechFetchResult { case audio(Data), limit, unavailable }

    private func fetchSpeech(_ text: String) async -> SpeechFetchResult {
        guard GhafCloudAI.isEnabled, !GhafCloudAI.fixtureNetworkIsDisabledForRequests else { return .unavailable }
        var request = URLRequest(url: GhafCloudAI.workerURL("speak"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        GhafCloudAI.setBuildHeader(on: &request)
        request.setValue(GhafCloudAI.deviceID, forHTTPHeaderField: "X-Ghaf-Device")
        if let code = Keychain.read(GhafCloudAI.accessCodeKey) { request.setValue(code, forHTTPHeaderField: "X-Ghaf-Code") }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text, "language": language, "character": character, "tier": tier, "liveSession": true
        ])
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .unavailable }
        if status == 429 { return .limit }
        guard status == 200, response.mimeType == "audio/wav" else { return .unavailable }
        return .audio(data)
    }

    private func playPCM(_ pcm: Data) {
        guard let outputFormat, pcm.count.isMultiple(of: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(pcm.count / 2)),
              let channels = buffer.int16ChannelData else {
            stopSpeechForTurn()
            return
        }
        buffer.frameLength = AVAudioFrameCount(pcm.count / 2)
        pcm.withUnsafeBytes { raw in
            if let source = raw.baseAddress?.assumingMemoryBound(to: Int16.self) {
                channels[0].update(from: source, count: pcm.count / 2)
            }
        }
        let samples = UnsafeBufferPointer(start: channels[0], count: pcm.count / 2)
        let rms = sqrt(samples.reduce(Float.zero) { $0 + pow(Float($1) / 32768, 2) } / max(1, Float(samples.count)))
        outputLevel = min(1, rms * 3)
        phase = .speaking
        queuedOutputBuffers += 1
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.queuedOutputBuffers = max(0, self.queuedOutputBuffers - 1)
                if self.queuedOutputBuffers == 0 {
                    self.outputLevel = 0
                    self.phase = .thinking
                    self.finishSpeechTurnIfReady()
                }
            }
        }
        if !player.isPlaying { player.play() }
    }

    private func stopSpeechForTurn() {
        speechDisabledForTurn = true
        speechChunks.removeAll()
        speechTextBuffer = ""
        speechRequestTask?.cancel()
        speechRequestTask = nil
        speechRequestActive = false
        speechTurnID &+= 1
        player.stop(); player.reset()
        queuedOutputBuffers = 0
        outputLevel = 0
        finishSpeechTurnIfReady()
    }

    private func clearSpeechQueue(disableTurn: Bool) {
        speechRequestTask?.cancel()
        speechRequestTask = nil
        speechRequestActive = false
        speechChunks.removeAll()
        speechTextBuffer = ""
        speechDisabledForTurn = disableTurn
        speechTurnID &+= 1
    }

    private func finishSpeechTurnIfReady() {
        guard !stopping, turnCompleteReceived, !speechRequestActive, speechChunks.isEmpty,
              queuedOutputBuffers == 0, toolTasks.isEmpty, !turnFinishNotified else { return }
        turnFinishNotified = true
        phase = .listening
        onTurnFinished?()
        if let pendingEndReason { endNow(reason: pendingEndReason) }
    }

    @objc private func audioInterrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        end(reason: "audio_interruption")
    }
    @objc private func audioRouteChanged(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: value),
              reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else { return }
        Task { @MainActor [weak self] in
            guard let self, !self.stopping else { return }
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
            self.inputConverter = nil
            try? self.startAudio()
        }
    }

    private func log(_ error: Error) {
        Logger(subsystem: "com.ghaf.app", category: "live-call").error("Live call error code: \(error._code, privacy: .public)")
    }
}
