import Foundation

/// The calendar for every period in Ghaf, with the user's chosen first day of the week
/// (More › Preferences). Without a choice it follows the iPhone's region.
enum GhafCalendar {
    static let weekStartKey = "ghaf.weekStart"   // 1 = Sunday, 2 = Monday, 7 = Saturday; 0 = region
#if DEBUG
    static var snapshotCalendar: Calendar?
#endif

    static var current: Calendar {
#if DEBUG
        if let snapshotCalendar { return snapshotCalendar }
#endif
        var calendar = Calendar.current
        let chosen = UserDefaults.standard.integer(forKey: weekStartKey)
        if (1...7).contains(chosen) { calendar.firstWeekday = chosen }
        return calendar
    }
}

/// A clock seam used by deterministic debug snapshots. Production always reads the device clock.
enum GhafClock {
#if DEBUG
    static var snapshotNow: Date?
    static var now: Date { snapshotNow ?? Date.now }
#else
    static var now: Date { Date.now }
#endif
}
