import XCTest
@testable import GhafCore

final class MerchantNameRealNamesTests: XCTestCase {
    func testKeepsNamesThatContainDateLikeWords() {
        for name in ["AL MAYA SUPERMARKET", "DUBAI MARINA MALL", "مطعم ابو علي", "SUN AND SAND SPORTS", "XXL FITNESS",
                     "CAFE AT MARINA", "SPINNEYS DEC", "JUNE BAKERY", "NOVO CINEMAS", "SHOP في المول"] {
            XCTAssertEqual(MerchantName.clean(name), name)
        }
    }

    func testStripsRealDateTails() {
        XCTAssertEqual(MerchantName.clean("CARREFOUR on 19 Nov 2026 18:11"), "CARREFOUR")
        XCTAssertEqual(MerchantName.clean("CARREFOUR Thursday, 19 November 2026"), "CARREFOUR")
        XCTAssertEqual(MerchantName.clean("CARREFOUR 19/11/2026 06:11"), "CARREFOUR")
        XCTAssertEqual(MerchantName.clean("CARREFOUR at 6:11 PM"), "CARREFOUR")
        XCTAssertEqual(MerchantName.clean("ENOC xx1234"), "ENOC")
        XCTAssertEqual(MerchantName.clean("مطعم ابو علي يوم الخميس ١٩ نوفمبر"), "مطعم ابو علي")
        XCTAssertEqual(MerchantName.clean("ADNOC Avl Bal AED 200"), "ADNOC")
    }
}
