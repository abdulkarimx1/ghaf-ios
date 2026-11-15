import XCTest
@testable import GhafCore

final class SubscriptionDetectorTests: XCTestCase {
    let now = Date()
    func daysAgo(_ d: Int) -> Date { Calendar.current.date(byAdding: .day, value: -d, to: now)! }

    func testKnownServiceDetectedOnFirstCharge() {
        XCTAssertEqual(SubscriptionDetector.detect(merchant: "NETFLIX.COM 8829", amount: 39, date: now, history: []), .monthly)
    }

    func testRepeatMonthlyChargeDetected() {
        let history = [SubscriptionDetector.PastCharge(merchant: "Local Gym LLC", amount: 250, date: daysAgo(30))]
        XCTAssertEqual(SubscriptionDetector.detect(merchant: "LOCAL GYM LLC", amount: 255, date: now, history: history), .monthly)
    }

    func testOneOffPurchaseNotDetected() {
        let history = [SubscriptionDetector.PastCharge(merchant: "Carrefour", amount: 120, date: daysAgo(30))]
        XCTAssertNil(SubscriptionDetector.detect(merchant: "Carrefour", amount: 410, date: now, history: history))
        XCTAssertNil(SubscriptionDetector.detect(merchant: "Carrefour", amount: 120, date: now, history: []))
        XCTAssertNil(SubscriptionDetector.detect(merchant: nil, amount: 10, date: now, history: []))
    }

    func testWeeklyAndYearly() {
        let weekly = [SubscriptionDetector.PastCharge(merchant: "Meal Box", amount: 99, date: daysAgo(7))]
        XCTAssertEqual(SubscriptionDetector.detect(merchant: "Meal Box", amount: 99, date: now, history: weekly), .weekly)
        let yearly = [SubscriptionDetector.PastCharge(merchant: "Domain Host", amount: 60, date: daysAgo(365))]
        XCTAssertEqual(SubscriptionDetector.detect(merchant: "Domain Host", amount: 60, date: now, history: yearly), .yearly)
    }
}
