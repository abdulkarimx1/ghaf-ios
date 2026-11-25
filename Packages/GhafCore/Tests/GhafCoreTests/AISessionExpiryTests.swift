import XCTest
@testable import GhafCore

final class AISessionExpiryTests: XCTestCase {
    func testFifteenMinuteRule() {
        let now = Date()
        XCTAssertFalse(AISessionExpiry.isStale(lastActive: nil, now: now))
        XCTAssertFalse(AISessionExpiry.isStale(lastActive: now.addingTimeInterval(-14 * 60), now: now))
        XCTAssertTrue(AISessionExpiry.isStale(lastActive: now.addingTimeInterval(-15 * 60), now: now))
    }
}
