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
    private var setupWaiter: CheckedContinuation<Void, Error>?
    private var setupTimeout: Task<Void, Never>?
    private var tokenModel = "models/gemini-3.8-live"
    private var language = "en"
    private var instruction = ""
    private var tools: [LiveFunctionDeclaration] = []
    private var resumeHandle: String?
    private var startedAt = Date()
    private var reconnects = 0
    private var stopping = false
    private var toolTasks: [String: Task<[String: LiveJSON], Never>] = [:]
    private var cancelledToolIDs = Set<String>()
    private var queuedOutputBuffers = 0
    private var inputContinuation: AsyncStream<Data>.Continuation?
    private var inputSenderTask: Task<Void, Never>?

    func start(language: String, systemInstruction: String, tools: [LiveFunctionDeclaration]) async throws {
        guard GhafCloudAI.isEnabled else { throw GhafCloudAI.Failure.unavailable }
        self.language = language; instruction = systemInstruction; self.tools = tools
        stopping = false; reconnects = 0; startedAt = Date(); phase = .connecting
        let stream = AsyncStream<Data>.makeStream()
        inputContinuation = stream.continuation
        inputSenderTask = Task { [weak self, stream = stream.stream] in
            for await chunk in stream {
                guard let self, !self.stopping else { continue }
                guard !self.isMuted else { self.inputLevel = 0; continue }
                let samples = chunk.withUnsafeBytes { raw in Array(raw.bindMemory(to: Int16.self)) }
                let rms = sqrt(samples.reduce(Float.zero) { $0 + pow(Float($1) / 32768, 2) } / max(1, Float(samples.count)))
                self.inputLevel = min(1, rms * 3)
                for start in stride(from: 0, to: chunk.count, by: 640) {
                    guard !self.isMuted, let message = try? LiveEncoder.audio(chunk.subdata(in: start..<min(start + 640, chunk.count))) else { continue }
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
        stopping = true
        inputContinuation?.finish(); inputContinuation = nil
        inputSenderTask?.cancel(); inputSenderTask = nil
        setupWaiter?.resume(throwing: CancellationError()); setupWaiter = nil
        setupTimeout?.cancel(); setupTimeout = nil
        receiveTask?.cancel(); receiveTask = nil
        toolTasks.values.forEach { $0.cancel() }; toolTasks.removeAll(); cancelledToolIDs.removeAll()
        elapsedTask?.cancel(); elapsedTask = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        NotificationCenter.default.removeObserver(self)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop(); player.stop()
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
                do { try await self.send(LiveSetup(model: token.model, voice: token.voice, systemInstruction: self.instruction,
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
                if self.elapsed >= 1800 { self.end(reason: "time_limit"); return }
            }
        } }
    }

    private struct Token: Decodable { let token: String; let model: String; let voice: String }

    private func fetchToken() async throws -> Token {
        guard let url = URL(string: "/live-token", relativeTo: GhafCloudAI.endpoint.deletingLastPathComponent()) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(GhafCloudAI.deviceID, forHTTPHeaderField: "X-Ghaf-Device")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["language": language])
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw URLError(.badServerResponse) }
        if status == 429 { throw GhafCloudAI.Failure.dailyLimit }
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
        case .audio(let pcm):
            phase = .speaking; play(pcm)
        case .inputTranscript(let text): onInputTranscript?(text, false)
        case .outputTranscript(let text): onOutputTranscript?(text, false)
        case .interrupted:
            player.stop(); player.reset(); queuedOutputBuffers = 0; outputLevel = 0; phase = .listening
            onOutputTranscript?("", true)
        case .turnComplete:
            onInputTranscript?("", true); onOutputTranscript?("", true)
            if queuedOutputBuffers == 0 { phase = .listening }
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
        guard reconnects < 3, phase != .reconnecting else { return }
        reconnects += 1; phase = .reconnecting
        socket?.cancel(with: .goingAway, reason: nil)
        do { try await connect(resuming: resumeHandle) } catch { log(error); end(reason: "connection_lost") }
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
        if toolTasks.isEmpty && !stopping { phase = .listening }
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

    private func play(_ pcm: Data) {
        guard let outputFormat, pcm.count.isMultiple(of: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(pcm.count / 2)),
              let channels = buffer.int16ChannelData else { return }
        buffer.frameLength = AVAudioFrameCount(pcm.count / 2)
        pcm.withUnsafeBytes { raw in
            if let source = raw.baseAddress?.assumingMemoryBound(to: Int16.self) { channels[0].update(from: source, count: pcm.count / 2) }
        }
        let samples = UnsafeBufferPointer(start: channels[0], count: pcm.count / 2)
        let rms = sqrt(samples.reduce(Float.zero) { $0 + pow(Float($1) / 32768, 2) } / max(1, Float(samples.count)))
        outputLevel = min(1, rms * 3)
        queuedOutputBuffers += 1
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.queuedOutputBuffers = max(0, self.queuedOutputBuffers - 1)
                if self.queuedOutputBuffers == 0 { self.outputLevel = 0; self.phase = .listening }
            }
        }
        if !player.isPlaying { player.play() }
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
