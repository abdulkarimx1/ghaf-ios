import XCTest
@testable import GhafCore

final class CrossSourceDuplicateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func rec(_ amount: Decimal, _ merchant: String?, wallet: Bool, minutes: Double = 0) -> CrossSourceDuplicate.Record {
        .init(amount: amount, currency: "AED", isDebit: true, merchant: merchant, arrivedAt: t0.addingTimeInterval(minutes * 60), isWallet: wallet)
    }

    func testWalletAndBankMessageForSamePurchaseMatch() {
        XCTAssertTrue(CrossSourceDuplicate.isSamePurchase(rec(5, "Carrefour", wallet: true), rec(5, "CARREFOUR MOE DUBAI", wallet: false, minutes: 2)))
        XCTAssertTrue(CrossSourceDuplicate.isSamePurchase(rec(5, "Carrefour", wallet: true), rec(5, nil, wallet: false, minutes: 1)))
    }

    func testRepeatedPurchasesFromSameSourceStaySeparate() {
        XCTAssertFalse(CrossSourceDuplicate.isSamePurchase(rec(5, "Cafe", wallet: true), rec(5, "Cafe", wallet: true, minutes: 1)))
        XCTAssertFalse(CrossSourceDuplicate.isSamePurchase(rec(5, "Cafe", wallet: false), rec(5, "Cafe", wallet: false)))
    }

    func testDifferentAmountMerchantOrTimeDoNotMatch() {
        XCTAssertFalse(CrossSourceDuplicate.isSamePurchase(rec(5, "Cafe", wallet: true), rec(6, "Cafe", wallet: false)))
        XCTAssertFalse(CrossSourceDuplicate.isSamePurchase(rec(5, "Cafe", wallet: true), rec(5, "Pharmacy", wallet: false)))
        XCTAssertFalse(CrossSourceDuplicate.isSamePurchase(rec(5, "Cafe", wallet: true), rec(5, "Cafe", wallet: false, minutes: 45)))
    }
}
