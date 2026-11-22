/// Stable source rule for transactions saved outside the shared ingestion service.
public enum TransactionUnreadPolicy {
    /// Voice drafts are saved through a separate confirmation path from message ingestion.
    public static func isUnreadForNewTransaction(fingerprint: String) -> Bool {
        fingerprint.hasPrefix("voice-")
    }
}
