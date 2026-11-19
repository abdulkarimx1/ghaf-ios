import Foundation

/// Counts consecutive local calendar days with a transaction, ending today or yesterday.
public enum GhafLoggingStreak {
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
}
