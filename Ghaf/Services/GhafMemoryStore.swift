import Foundation
import SwiftData

@MainActor
enum GhafMemoryStore {
    static func remember(_ text: String, kind: String = "fact", source: String = "confirmed", in context: ModelContext) throws -> GhafMemory {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 200 else {
            throw NSError(domain: "GhafMemory", code: 1)
        }
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let all = try context.fetch(FetchDescriptor<GhafMemory>())
        let memory = all.first { $0.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalized }
            ?? GhafMemory(text: text, kind: kind, source: source)
        if memory.modelContext == nil { context.insert(memory) }
        memory.updatedAt = .now; memory.kind = kind; memory.source = source
        try context.save()
        return memory
    }

    static func forget(_ text: String, in context: ModelContext) throws {
        let target = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        for memory in try context.fetch(FetchDescriptor<GhafMemory>()) where memory.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(target) {
            context.delete(memory)
        }
        try context.save()
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
struct GhafMemoryTool: Tool {
    let name = "memory"
    let description = "Remember a short user preference or fact they explicitly asked you to remember, or forget a fact they asked you to forget."

    @Generable
    struct Arguments {
        @Guide(description: "Operation to perform", .anyOf(["remember", "forget"])) var operation: String
        @Guide(description: "One short fact or preference, up to 200 characters") var fact: String
    }

    func call(arguments: Arguments) async throws -> String {
        try await MainActor.run {
            guard UserDefaults.standard.bool(forKey: "ghaf.ai.memoryEnabled"),
                  let context = GhafLedgerContext.modelContext else { return "Memory is disabled." }
            if arguments.operation == "remember" {
                _ = try GhafMemoryStore.remember(arguments.fact, in: context)
                return "Saved on this iPhone."
            }
            try GhafMemoryStore.forget(arguments.fact, in: context)
            return "Forgotten."
        }
    }
}
#endif
