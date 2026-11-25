import Foundation

/// Row 14: a Ghaf AI conversation left alone for 15 minutes is over; the next visit starts fresh.
public enum AISessionExpiry {
    public static let timeout: TimeInterval = 15 * 60
    public static func isStale(lastActive: Date?, now: Date) -> Bool {
        guard let lastActive else { return false }
        return now.timeIntervalSince(lastActive) >= timeout
    }
}
