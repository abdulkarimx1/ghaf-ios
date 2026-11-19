import Foundation

public enum MemoryIntent: Equatable {
    case remember(String), forget(String), name(String)

    public var isName: Bool { if case .name = self { true } else { false } }

    public static func parse(_ text: String) -> MemoryIntent? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.hasSuffix("?"), !clean.hasSuffix("؟") else { return nil }
        let english: [(String, (String) -> MemoryIntent)] = [
            (#"(?i)^remember(?:\s+that)?\s+(.+?)\s*[.!؟?]*$"#, MemoryIntent.remember),
            (#"(?i)^forget(?:\s+that)?\s+(.+?)\s*[.!؟?]*$"#, MemoryIntent.forget),
            (#"(?i)^call\s+me\s+(.+?)\s*[.!؟?]*$"#, MemoryIntent.name),
            (#"(?i)^my\s+name\s+is\s+(.+?)\s*[.!؟?]*$"#, MemoryIntent.name)
        ]
        for (pattern, make) in english {
            if let value = capture(pattern, clean), valid(value), !startsWithQuestionWord(value, arabic: false) { return make(value) }
        }
        let normalized = clean.replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا").replacingOccurrences(of: "آ", with: "ا")
            .replacingOccurrences(of: "ى", with: "ي")
        let arabic: [(String, (String) -> MemoryIntent)] = [
            (#"^(?:تذكر\s+ان|تذكر|تذكّر\s+ان|تذكّر)\s+(.+?)\s*[.!؟?]*$"#, MemoryIntent.remember),
            (#"^(?:انس|انسي|انسَ|انسى)\s+(.+?)\s*[.!؟?]*$"#, MemoryIntent.forget),
            (#"^ناديني\s+(.+?)\s*[.!؟?]*$"#, MemoryIntent.name),
            (#"^اسمي\s+(.+?)\s*[.!؟?]*$"#, MemoryIntent.name)
        ]
        for (pattern, make) in arabic {
            if let value = capture(pattern, normalized), valid(value), !startsWithQuestionWord(value, arabic: true) { return make(value) }
        }
        return nil
    }

    public static func matches(memory: String, target: String) -> Bool {
        let normalize: (String) -> String = { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).trimmingCharacters(in: .whitespacesAndNewlines) }
        let memory = normalize(memory), target = normalize(target)
        guard target.count >= 3 else { return false }
        if memory == target { return true }
        guard target.count >= 4 else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: target)
        guard let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])" + escaped + "(?![\\p{L}\\p{N}])", options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: memory, range: NSRange(memory.startIndex..., in: memory)) != nil
    }

    private static func startsWithQuestionWord(_ text: String, arabic: Bool) -> Bool {
        let words = arabic ? ["كم", "شو", "ايش", "وين", "متى", "ليش", "هل"] : ["how", "what", "when", "where", "which", "who", "why", "did", "do"]
        let first = text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)?.lowercased() ?? ""
        return words.contains(first)
    }

    private static func capture(_ pattern: String, _ input: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let range = Range(match.range(at: 1), in: input) else { return nil }
        return String(input[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func valid(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 200
    }
}
