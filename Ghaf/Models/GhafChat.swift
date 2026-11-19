import Foundation
import SwiftData

/// A saved Ghaf AI conversation. Chats stay on this iPhone and are not part of backups;
/// the messages are kept as one JSON blob because they are only ever read back whole.
@Model
final class GhafChat {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var messagesData: Data = Data()

    init(title: String, messages: [GhafStoredChatMessage]) {
        self.title = title
        self.messagesData = (try? JSONEncoder().encode(messages)) ?? Data()
    }

    var messages: [GhafStoredChatMessage] {
        get { (try? JSONDecoder().decode([GhafStoredChatMessage].self, from: messagesData)) ?? [] }
        set {
            messagesData = (try? JSONEncoder().encode(newValue)) ?? messagesData
            updatedAt = Date()
        }
    }
}

/// What a chat keeps of each message: the words, where an answer's numbers came from, and its chart.
/// Unsaved transaction drafts are not kept; their saved transactions already live in the ledger.
struct GhafStoredChatMessage: Codable {
    var isUser: Bool
    var text: String
    var isVoice = false
    var source: String?
    var chart: GhafChatChart?
    var memoryID: UUID?
}
