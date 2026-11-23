import XCTest
@testable import GhafCore

final class LoggingStreakTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Dubai")!
        return value
    }

    private func date(_ offset: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    func testReachesSevenDayMilestone() {
        let now = Date()
        let entries = (-6...0).map { GhafLoggingStreak.Entry(date: date($0, from: now)) }
        XCTAssertEqual(GhafLoggingStreak.newlyReachedMilestone(dates: entries, now: now, calendar: calendar, lastCelebrated: nil), 7)
    }

    func testDoesNotRepeatAlreadyCelebratedMilestone() {
        let now = Date()
        let entries = (-6...0).map { GhafLoggingStreak.Entry(date: date($0, from: now)) }
        XCTAssertNil(GhafLoggingStreak.newlyReachedMilestone(dates: entries, now: now, calendar: calendar, lastCelebrated: "\(dayKey(date(-6, from: now)))|7"))
    }

    func testBrokenAndRebuiltSevenDayStreakCanCelebrateAgain() {
        let now = Date()
        let old = date(-20, from: now)
        let entries = [GhafLoggingStreak.Entry(date: old)] + (-6...0).map { GhafLoggingStreak.Entry(date: date($0, from: now)) }
        XCTAssertEqual(GhafLoggingStreak.newlyReachedMilestone(dates: entries, now: now, calendar: calendar, lastCelebrated: "\(dayKey(old))|7"), 7)
    }

    func testNeedsReviewEntriesDoNotCompleteStreak() {
        let now = Date()
        let entries = (-5...0).map { GhafLoggingStreak.Entry(date: date($0, from: now)) }
            + [.init(date: date(-6, from: now), needsReview: true)]
        XCTAssertNil(GhafLoggingStreak.newlyReachedMilestone(dates: entries, now: now, calendar: calendar, lastCelebrated: nil))
    }

    func testShortcutCapturedEntriesCountLikeAnyConfirmedEntry() {
        let now = Date()
        let entries = (-6...0).map { GhafLoggingStreak.Entry(date: date($0, from: now), needsReview: false) }
        XCTAssertEqual(GhafLoggingStreak.newlyReachedMilestone(dates: entries, now: now, calendar: calendar, lastCelebrated: nil), 7)
    }

    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
