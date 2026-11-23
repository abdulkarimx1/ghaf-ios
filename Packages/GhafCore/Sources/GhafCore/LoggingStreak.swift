import Foundation

/// Counts consecutive local calendar days with a transaction, ending today or yesterday.
public enum GhafLoggingStreak {
    public static let milestones = [7, 30, 100, 365]

    public struct Entry: Equatable, Sendable {
        public let date: Date
        public let needsReview: Bool

        public init(date: Date, needsReview: Bool = false) {
            self.date = date
            self.needsReview = needsReview
        }
    }

    public static func count(_ dates: [Date], through now: Date, calendar: Calendar) -> Int {
        let loggedDays = Set(dates.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
        var day = loggedDays.contains(today) ? today : yesterday
        guard loggedDays.contains(day) else { return 0 }
        var streak = 0
        while loggedDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// Returns the highest milestone reached by the current (today-or-yesterday-ending) streak
    /// that has not already been celebrated for this streak's local start day. `lastCelebrated`
    /// uses `yyyy-MM-dd|milestone`; it is persisted by the app, while this function stays pure.
    public static func newlyReachedMilestone(
        dates: [Entry],
        now: Date,
        calendar: Calendar,
        lastCelebrated: String?
    ) -> Int? {
        let days = Set(dates.filter { !$0.needsReview }.map { calendar.startOfDay(for: $0.date) })
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        guard var day = days.contains(today) ? today : yesterday,
              days.contains(day) else { return nil }

        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        guard let startDay = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        let startKey = localDayKey(startDay, calendar: calendar)
        let previous = lastCelebrated.flatMap(parseCelebration)
        let previousMilestone = previous?.startDay == startKey ? previous?.milestone ?? 0 : 0
        return milestones.last { $0 <= streak && $0 > previousMilestone }
    }

    public static func celebrationKey(for milestone: Int, dates: [Entry], now: Date, calendar: Calendar) -> String? {
        let days = Set(dates.filter { !$0.needsReview }.map { calendar.startOfDay(for: $0.date) })
        let today = calendar.startOfDay(for: now)
        guard var day = days.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today), days.contains(day) else { return nil }
        while let previous = calendar.date(byAdding: .day, value: -1, to: day), days.contains(previous) { day = previous }
        return "\(localDayKey(day, calendar: calendar))|\(milestone)"
    }

    private static func localDayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func parseCelebration(_ value: String) -> (startDay: String, milestone: Int)? {
        let parts = value.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2, let milestone = Int(parts[1]) else { return nil }
        return (String(parts[0]), milestone)
    }
}
