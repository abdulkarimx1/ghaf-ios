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

    func testAreaRequiresAccurateFixAtMostFiftyMeters() {
        XCTAssertTrue(PlaceSelection.acceptsAreaAccuracy(50))
        XCTAssertFalse(PlaceSelection.acceptsAreaAccuracy(50.1))
        XCTAssertFalse(PlaceSelection.acceptsAreaAccuracy(-1))
    }
}
