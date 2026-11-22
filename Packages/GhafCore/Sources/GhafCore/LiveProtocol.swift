import Foundation

public struct LiveFunctionDeclaration: Codable, Equatable {
    public var name: String
    public var description: String
    public var parameters: [String: LiveJSON]
    public var behavior: String?

    public init(name: String, description: String, parameters: [String: LiveJSON], behavior: String? = nil) {
        self.name = name; self.description = description; self.parameters = parameters; self.behavior = behavior
    }
}

public indirect enum LiveJSON: Codable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: LiveJSON]), array([LiveJSON]), null

    public init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([String: LiveJSON].self) { self = .object(value) }
        else { self = .array(try box.decode([LiveJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .string(let value): try box.encode(value)
        case .number(let value): try box.encode(value)
        case .bool(let value): try box.encode(value)
        case .object(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .null: try box.encodeNil()
        }
    }
}

public struct LiveToolCall: Equatable {
    public let id: String
    public let name: String
    public let args: [String: LiveJSON]
}

public struct LiveSetup {
    public var model: String
    public var voice: String
    public var systemInstruction: String
    public var tools: [LiveFunctionDeclaration]
    public var resumptionHandle: String?

    public init(model: String = "models/gemini-3.8-live", voice: String, systemInstruction: String,
                tools: [LiveFunctionDeclaration], resumptionHandle: String? = nil) {
        self.model = model; self.voice = voice; self.systemInstruction = systemInstruction
        self.tools = tools; self.resumptionHandle = resumptionHandle
    }

    public func encoded(responseModalitiesInGenerationConfig: Bool = true) throws -> Data {
        var generationConfig: [String: Any] = ["speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voice]]]]
        if responseModalitiesInGenerationConfig { generationConfig["responseModalities"] = ["AUDIO"] }
        var setup: [String: Any] = [
            "model": model,
            "generationConfig": generationConfig,
            "systemInstruction": ["parts": [["text": systemInstruction]]],
            "tools": [["functionDeclarations": try JSONSerialization.jsonObject(with: JSONEncoder().encode(tools))]],
            "inputAudioTranscription": [:], "outputAudioTranscription": [:],
            "realtimeInputConfig": ["automaticActivityDetection": ["disabled": true]],
            "contextWindowCompression": ["slidingWindow": [:]], "sessionResumption": [:]
        ]
        if !responseModalitiesInGenerationConfig { setup["responseModalities"] = ["AUDIO"] }
        if let resumptionHandle { setup["sessionResumption"] = ["handle": resumptionHandle] }
        return try JSONSerialization.data(withJSONObject: ["setup": setup])
    }
}

public enum LiveServerEvent {
    case setupComplete, audio(Data), inputTranscript(String), outputTranscript(String), interrupted
    case turnComplete, toolCalls([LiveToolCall]), toolCancellation([String])
    case resumption(handle: String?), goAway(seconds: Double?), error(String), unknown

    public static func parse(_ data: Data) -> [LiveServerEvent] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [.unknown] }
        var events: [LiveServerEvent] = []
        if root["setupComplete"] != nil { events.append(.setupComplete) }
        if let content = root["serverContent"] as? [String: Any] {
            if let transcript = (content["inputTranscription"] as? [String: Any])?["text"] as? String { events.append(.inputTranscript(transcript)) }
            if let transcript = (content["outputTranscription"] as? [String: Any])?["text"] as? String { events.append(.outputTranscript(transcript)) }
            if let parts = (content["modelTurn"] as? [String: Any])?["parts"] as? [[String: Any]] {
                for part in parts {
                    if let inline = part["inlineData"] as? [String: Any], let b64 = inline["data"] as? String,
                       let audio = Data(base64Encoded: b64) { events.append(.audio(audio)) }
                }
            }
            if content["interrupted"] as? Bool == true { events.append(.interrupted) }
            if content["turnComplete"] as? Bool == true || content["generationComplete"] as? Bool == true { events.append(.turnComplete) }
        }
        if let calls = (root["toolCall"] as? [String: Any])?["functionCalls"] as? [[String: Any]] {
            let parsed = calls.compactMap { call -> LiveToolCall? in
                guard let id = call["id"] as? String, let name = call["name"] as? String else { return nil }
                let args = (try? JSONSerialization.data(withJSONObject: call["args"] ?? [:]))
                    .flatMap { try? JSONDecoder().decode([String: LiveJSON].self, from: $0) } ?? [:]
                return LiveToolCall(id: id, name: name, args: args)
            }
            if !parsed.isEmpty { events.append(.toolCalls(parsed)) }
        }
        if let ids = (root["toolCallCancellation"] as? [String: Any])?["ids"] as? [String] { events.append(.toolCancellation(ids)) }
        if let update = root["sessionResumptionUpdate"] as? [String: Any], update["resumable"] as? Bool == true {
            events.append(.resumption(handle: update["newHandle"] as? String))
        }
        if let left = (root["goAway"] as? [String: Any])?["timeLeft"] {
            let seconds = left as? Double ?? (left as? String).flatMap { Double($0.replacingOccurrences(of: "s", with: "")) }
            events.append(.goAway(seconds: seconds))
        }
        if let error = root["error"] as? [String: Any] { events.append(.error(error["message"] as? String ?? "Live API error")) }
        return events.isEmpty ? [.unknown] : events
    }
}

public enum LiveEncoder {
    public static func activityStart() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["realtimeInput": ["activityStart": [:]]])
    }
    public static func activityEnd() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["realtimeInput": ["activityEnd": [:]]])
    }
    public static func audio(_ pcm: Data) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["realtimeInput": ["audio": ["data": pcm.base64EncodedString(), "mimeType": "audio/pcm;rate=16000"]]])
    }
    public static func text(_ text: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["realtimeInput": ["text": text]])
    }
    public static func toolResponse(_ responses: [(id: String, name: String, response: [String: LiveJSON])]) throws -> Data {
        let values = responses.map { ["id": LiveJSON.string($0.id), "name": .string($0.name), "response": .object($0.response)] }
        let bytes = try JSONEncoder().encode(LiveJSON.object(["toolResponse": .object(["functionResponses": .array(values.map(LiveJSON.object))])]))
        return bytes
    }
}
