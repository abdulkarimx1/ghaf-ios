import XCTest
@testable import GhafCore

final class PlaceSelectionTests: XCTestCase {
    func testSelectsOnlyAUniquelyNearestShopWithinThirtyMeters() {
        XCTAssertEqual(PlaceSelection.selectedCandidateIndex(distances: [22, 65]), 0)
        XCTAssertEqual(PlaceSelection.selectedCandidateIndex(distances: [75, 12, 100]), 1)
    }

    func testRejectsAmbiguousOrDistantShopCandidates() {
        XCTAssertNil(PlaceSelection.selectedCandidateIndex(distances: [29, 59]))
        XCTAssertNil(PlaceSelection.selectedCandidateIndex(distances: [31, 90]))
        XCTAssertNil(PlaceSelection.selectedCandidateIndex(distances: []))
    }

    func testAreaAcceptsIndoorFixUpToHundredMeters() {
        XCTAssertTrue(PlaceSelection.acceptsAreaAccuracy(65))
        XCTAssertTrue(PlaceSelection.acceptsAreaAccuracy(100))
        XCTAssertFalse(PlaceSelection.acceptsAreaAccuracy(100.1))
        XCTAssertFalse(PlaceSelection.acceptsAreaAccuracy(-1))
    }

    func testShopRequiresFixAtMostFiftyMeters() {
        XCTAssertTrue(PlaceSelection.acceptsShopAccuracy(50))
        XCTAssertFalse(PlaceSelection.acceptsShopAccuracy(65))
    }

    func testLiveLocationOnlyForRecentPurchases() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(PlaceSelection.isLiveLocationValid(for: now.addingTimeInterval(-29 * 60), now: now))
        XCTAssertFalse(PlaceSelection.isLiveLocationValid(for: now.addingTimeInterval(-31 * 60), now: now))
        XCTAssertFalse(PlaceSelection.isLiveLocationValid(for: now.addingTimeInterval(-86_400), now: now))
    }
}
