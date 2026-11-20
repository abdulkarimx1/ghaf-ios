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

    func testSlashISODate() {
        XCTAssertNotNil(DelimitedImport.date("2026/02/13"))
    }

    func testAmountSeparatorsAndSignedDirection() {
        XCTAssertEqual(DelimitedImport.decimal("1,234"), 1234)
        XCTAssertEqual(DelimitedImport.decimal("12,500"), 12500)
        XCTAssertEqual(DelimitedImport.decimal("12,5"), Decimal(string: "12.5"))
        XCTAssertEqual(DelimitedImport.decimal("1.234,56"), Decimal(string: "1234.56"))
        XCTAssertNil(DelimitedImport.decimal("1,23,4"))
        XCTAssertNil(DelimitedImport.decimal("1.23,45"))
        XCTAssertEqual(DelimitedImport.decimal("1,234,567"), 1_234_567)
        XCTAssertEqual(DelimitedImport.direction(amount: 15_000), .credit)
        XCTAssertEqual(DelimitedImport.direction(amount: -45), .debit)
        XCTAssertNil(DelimitedImport.direction(debit: "10", credit: "20"))
    }

    func testFirstNonblankDuplicateHeaderWinsAndHeaderAliasesAreExact() {
        let row = DelimitedImport.dictionary(headers: ["", "Amount", "Amount", "Value Date", "Account Name"], values: ["bad", "15", "99", "2026-01-01", "Mashreq"])
        XCTAssertEqual(row["amount"], "15")
        XCTAssertNil(row[""])
        XCTAssertNil(DelimitedImport.value(row, aliases: ["value"]))
        XCTAssertNil(DelimitedImport.value(row, aliases: ["name"]))
    }

    func testDebitCreditColumns() {
        XCTAssertEqual(DelimitedImport.direction(amount: nil, debit: "45", credit: nil), .debit)
        XCTAssertEqual(DelimitedImport.direction(amount: nil, debit: nil, credit: "15000"), .credit)
    }
}
