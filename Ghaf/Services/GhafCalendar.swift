import Foundation

/// The calendar for every period in Ghaf, with the user's chosen first day of the week
/// (More › Preferences). Without a choice it follows the iPhone's region.
enum GhafCalendar {
    static let weekStartKey = "ghaf.weekStart"   // 1 = Sunday, 2 = Monday, 7 = Saturday; 0 = region

    static var current: Calendar {
        var calendar = Calendar.current
        let chosen = UserDefaults.standard.integer(forKey: weekStartKey)
        if (1...7).contains(chosen) { calendar.firstWeekday = chosen }
        return calendar
    }
}
