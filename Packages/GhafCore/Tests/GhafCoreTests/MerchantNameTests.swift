import XCTest
@testable import GhafCore

final class MerchantNameTests: XCTestCase {
    func testCleansDateNoiseAndKeepsFallback() {
        XCTAssertEqual(MerchantName.clean("KOOKH AL SHAY CAFETER on Thursday, 19 November 2026, 6:11 am"), "KOOKH AL SHAY CAFETER")
        XCTAssertEqual(MerchantName.clean("SHOP بتاريخ ١٩/١١/٢٠٢٦"), "SHOP")
        XCTAssertEqual(MerchantName.clean("SHOP card ending 1234"), "SHOP")
        XCTAssertEqual(MerchantName.clean("  on 19/11/2026  "), "on 19/11/2026")
    }

    func testExpandsLearnedAndDictionaryNamesButNotAmbiguousOnes() {
        XCTAssertEqual(MerchantName.expand("KOOKH AL SHAY CAFETER", known: []), "KOOKH AL SHAY CAFETERIA")
        XCTAssertEqual(MerchantName.expand("AL MAYA SUPERMARK", known: []), "AL MAYA SUPERMARKET")
        XCTAssertEqual(MerchantName.expand("KOOKH AL SHAY CAFETER", known: ["Kookh Al Shay Cafeteria LLC"]), "Kookh Al Shay Cafeteria LLC")
        XCTAssertEqual(MerchantName.expand("AL MAYA SHOPP", known: ["AL MAYA SHOPPE LTD", "AL MAYA SHOPPING"]), "AL MAYA SHOPP")
    }

    func testMerchantKeysIgnoreBusinessSuffixes() {
        let keys = ["KOOKH AL SHAY", "KOOKH AL SHAY CAFETER", "Kookh Al Shay Cafeteria LLC"].map(MerchantName.key)
        XCTAssertEqual(Set(keys).count, 1)
    }
}
