import XCTest
@testable import GhafCore

/// Card clauses leak into merchant names from older parses; cleanup must change only those names.
final class MerchantCleanupBackupTests: XCTestCase {
    func testStripsCardClauseOnly() {
        XCTAssertEqual(MerchantName.clean("Digital Dubai using DFM iVESTOR card xxxx9838"), "Digital Dubai")
        XCTAssertEqual(MerchantName.clean("Tabby card payment"), "Tabby card payment")
        XCTAssertEqual(MerchantName.clean("Coffee with Love"), "Coffee with Love")
    }

    /// Optional check against a real backup: set GHAF_BACKUP to its path (never committed).
    func testRealBackupChangesOnlyBadNames() throws {
        guard let path = ProcessInfo.processInfo.environment["GHAF_BACKUP"] else { throw XCTSkip("GHAF_BACKUP not set") }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
        let merchants = (json["transactions"] as! [[String: Any]]).compactMap { $0["merchant"] as? String }
        let changed = merchants.filter { raw in
            let baseline = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return MerchantName.clean(raw) != baseline
        }
        XCTAssertTrue(changed.allSatisfy { MerchantName.clean($0).range(of: #"(?i)\busing\b.*\bcard\b"#, options: .regularExpression) == nil })
    }
}
