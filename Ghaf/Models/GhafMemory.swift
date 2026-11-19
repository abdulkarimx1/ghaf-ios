import Foundation
import SwiftData

@Model
final class GhafMemory {
    var id: UUID = UUID()
    var text: String
    var kind: String
    var source: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastUsedAt: Date?

    init(text: String, kind: String, source: String) {
        self.text = String(text.prefix(200))
        self.kind = kind
        self.source = source
    }
}
