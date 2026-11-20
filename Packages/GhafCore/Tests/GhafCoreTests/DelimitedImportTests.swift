import XCTest
@testable import GhafCore

final class DelimitedImportTests: XCTestCase {
    func testCommaCSV() throws { XCTAssertEqual(try DelimitedImport.rows("Date,Amount,Merchant\n2026-01-02,12.5,Cafe")[1], ["2026-01-02", "12.5", "Cafe"]) }
    func testSemicolonCSVAndDayFirstDate() throws {
        let values = try DelimitedImport.rows("Date;Amount;Merchant\n02/01/2026;12,5;Cafe")[1]
        XCTAssertEqual(values, ["02/01/2026", "12,5", "Cafe"])
        XCTAssertEqual(DelimitedImport.date("13/02/2026"), DelimitedImport.date("02/13/2026"))
    }
    func testArabicHeadersAndQuotedComma() throws { XCTAssertEqual(try DelimitedImport.rows("التاريخ,المبلغ,الوصف\n2026-01-02,12,\"مقهى, دبي\"")[1][2], "مقهى, دبي") }
    func testUnclosedQuoteReadableFailure() {
        XCTAssertThrowsError(try DelimitedImport.rows("date,amount\n\"broken,3")) { error in
            XCTAssertEqual(error.localizedDescription, "A quoted value is missing its closing quotation mark.")
        }
    }
    func testJSONArrayRows() throws {
        let data = #"[{"date":"2026-01-02","amount":12.5,"description":"Cafe"}]"#.data(using: .utf8)!
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array[0]["description"] as? String, "Cafe")
    }
}
