import XCTest
@testable import GhafCore

final class ImportFileSizeLimitTests: XCTestCase {
    func testAcceptsFileAtOrUnderLimit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        FileManager.default.createFile(atPath: url.path, contents: Data())
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(ImportFileSizeLimit.maximumBytes))
        try handle.close()
        XCTAssertNoThrow(try ImportFileSizeLimit.check(url))
    }

    func testRejectsFileOverLimitBeforeReadingContents() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        FileManager.default.createFile(atPath: url.path, contents: Data())
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(ImportFileSizeLimit.maximumBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try ImportFileSizeLimit.check(url)) { error in
            guard let sizeError = error as? ImportFileSizeError else {
                XCTFail("Expected ImportFileSizeError")
                return
            }
            if case .tooLarge = sizeError { return }
            XCTFail("Expected tooLarge")
        }
    }
}
