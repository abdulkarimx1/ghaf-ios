import XCTest
@testable import GhafCore

final class TransactionUnreadPolicyTests: XCTestCase {
    func testVoiceDraftsAreUnreadButManualEntriesAreNot() {
        XCTAssertTrue(TransactionUnreadPolicy.isUnreadForNewTransaction(fingerprint: "voice-123"))
        XCTAssertFalse(TransactionUnreadPolicy.isUnreadForNewTransaction(fingerprint: "manual-123"))
        XCTAssertFalse(TransactionUnreadPolicy.isUnreadForNewTransaction(fingerprint: "manual-adjust-123"))
    }
}
