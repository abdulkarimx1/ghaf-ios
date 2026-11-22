import Foundation
import XCTest
@testable import GhafCore

final class LiveProtocolTests: XCTestCase {
    func testSetupShape() throws {
        let setup = LiveSetup(voice: "Orus", systemInstruction: "Ghaf", tools: [], resumptionHandle: "resume")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: setup.encoded()) as? [String: Any])
        let value = try XCTUnwrap(object["setup"] as? [String: Any])
        XCTAssertEqual(value["model"] as? String, "models/gemini-3.8-live")
        XCTAssertEqual((value["generationConfig"] as? [String: Any])?["responseModalities"] as? [String], ["AUDIO"])
        XCTAssertEqual((value["sessionResumption"] as? [String: Any])?["handle"] as? String, "resume")
        XCTAssertNotNil(value["inputAudioTranscription"])
        XCTAssertEqual(((value["realtimeInputConfig"] as? [String: Any])?["automaticActivityDetection"] as? [String: Any])?["disabled"] as? Bool, true)
        XCTAssertNotNil(value["outputAudioTranscription"])
        XCTAssertNotNil(value["contextWindowCompression"])
        let rawModalities = try XCTUnwrap(JSONSerialization.jsonObject(with: setup.encoded(responseModalitiesInGenerationConfig: false)) as? [String: Any])
        let rawSetup = try XCTUnwrap(rawModalities["setup"] as? [String: Any])
        XCTAssertEqual(rawSetup["responseModalities"] as? [String], ["AUDIO"])
        XCTAssertNil((rawSetup["generationConfig"] as? [String: Any])?["responseModalities"])
    }

    func testServerEventFixtures() throws {
        func parse(_ source: String) -> [LiveServerEvent] { LiveServerEvent.parse(Data(source.utf8)) }
        XCTAssertTrue(parse(#"{"setupComplete":{}}"#).contains { if case .setupComplete = $0 { true } else { false } })
        let audioTranscript = parse(#"{"serverContent":{"inputTranscription":{"text":"hello"},"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm;rate=24000","data":"AQI="}}]}}}"#)
        XCTAssertEqual(audioTranscript.count, 2)
        XCTAssertTrue(audioTranscript.contains { if case .inputTranscript("hello") = $0 { true } else { false } })
        XCTAssertTrue(audioTranscript.contains { if case .audio(Data([1, 2])) = $0 { true } else { false } })
        XCTAssertTrue(parse(#"{"serverContent":{"interrupted":true}}"#).contains { if case .interrupted = $0 { true } else { false } })
        let tools = parse(#"{"toolCall":{"functionCalls":[{"id":"1","name":"a","args":{"x":1}},{"id":"2","name":"b","args":{}}]}}"#)
        XCTAssertTrue(tools.contains { if case .toolCalls(let calls) = $0 { calls.count == 2 } else { false } })
        if case .toolCalls(let calls) = tools[0] { XCTAssertEqual(calls[0].args["x"], .number(1)) }
        XCTAssertTrue(parse(#"{"goAway":{"timeLeft":"5s"}}"#).contains { if case .goAway(seconds: 5) = $0 { true } else { false } })
        XCTAssertTrue(parse(#"{"sessionResumptionUpdate":{"resumable":true,"newHandle":"h"}}"#).contains { if case .resumption(handle: "h") = $0 { true } else { false } })
        let ending = parse(#"{"serverContent":{"outputTranscription":{"text":"done"},"turnComplete":true}}"#)
        XCTAssertTrue(ending.contains { if case .outputTranscript("done") = $0 { true } else { false } })
        XCTAssertTrue(ending.contains { if case .turnComplete = $0 { true } else { false } })
        XCTAssertTrue(parse(#"{"toolCallCancellation":{"ids":["1"]}}"#).contains { if case .toolCancellation(["1"]) = $0 { true } else { false } })
        XCTAssertTrue(parse(#"{"error":{"message":"bad"}}"#).contains { if case .error("bad") = $0 { true } else { false } })
    }

    func testToolResponseRoundTrip() throws {
        let encoded = try LiveEncoder.toolResponse([(id: "call", name: "answer", response: ["amount": .number(12.5)])])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let tool = try XCTUnwrap(object["toolResponse"] as? [String: Any])
        let calls = try XCTUnwrap(tool["functionResponses"] as? [[String: Any]])
        XCTAssertEqual(calls.first?["id"] as? String, "call")
        XCTAssertEqual((calls.first?["response"] as? [String: Any])?["amount"] as? Double, 12.5)
    }

    func testRealtimeInputEncoders() throws {
        let audio = try XCTUnwrap(JSONSerialization.jsonObject(with: LiveEncoder.audio(Data([1, 2]))) as? [String: Any])
        let audioPart = try XCTUnwrap((audio["realtimeInput"] as? [String: Any])?["audio"] as? [String: Any])
        XCTAssertEqual(audioPart["mimeType"] as? String, "audio/pcm;rate=16000")
        XCTAssertEqual(audioPart["data"] as? String, "AQI=")
        let text = try XCTUnwrap(JSONSerialization.jsonObject(with: LiveEncoder.text("hi")) as? [String: Any])
        XCTAssertEqual((text["realtimeInput"] as? [String: Any])?["text"] as? String, "hi")
        let start = try XCTUnwrap(JSONSerialization.jsonObject(with: LiveEncoder.activityStart()) as? [String: Any])
        XCTAssertNotNil((start["realtimeInput"] as? [String: Any])?["activityStart"])
        let end = try XCTUnwrap(JSONSerialization.jsonObject(with: LiveEncoder.activityEnd()) as? [String: Any])
        XCTAssertNotNil((end["realtimeInput"] as? [String: Any])?["activityEnd"])
    }

    func testLiveToolDeclarationCanBeNonBlocking() throws {
        let declaration = LiveFunctionDeclaration(name: "get_finance_answer", description: "Ledger answer", parameters: [:], behavior: "NON_BLOCKING")
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(declaration)) as? [String: Any])
        XCTAssertEqual(encoded["behavior"] as? String, "NON_BLOCKING")
    }
}
