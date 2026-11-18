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

final class SubscriptionPaymentMatchTests: XCTestCase {
    private let due = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ offset: Int) -> Date { due.addingTimeInterval(Double(offset) * 86_400) }

    func testChargeNearDueDateWithSameServicePays() {
        XCTAssertTrue(SubscriptionDetector.isPayment(
            merchant: "NETFLIX.COM 8829", amount: 56, date: day(2),
            subscriptionName: "Netflix", subscriptionAmount: 56, dueDate: due, toleranceDays: 5))
    }

    func testDifferentServiceOrAmountOrDateDoesNotPay() {
        func pays(_ merchant: String, _ amount: Decimal, _ offset: Int) -> Bool {
            SubscriptionDetector.isPayment(merchant: merchant, amount: amount, date: day(offset),
                subscriptionName: "Netflix", subscriptionAmount: 56, dueDate: due, toleranceDays: 5)
        }
        XCTAssertFalse(pays("Netflixer Store", 56, 0))
        XCTAssertTrue(SubscriptionDetector.sameService(merchant: "CHATGPT", subscriptionName: "Chat GPT"))
        XCTAssertTrue(SubscriptionDetector.sameService(merchant: "OPENAI *CHATGPT SUBSCR", subscriptionName: "ChatGPT"))
        XCTAssertTrue(SubscriptionDetector.sameService(merchant: "NETFLIX.COM 8829", subscriptionName: "Netflix"))
        XCTAssertFalse(SubscriptionDetector.sameService(merchant: "CHATGPTX", subscriptionName: "Chat GPT"))
        XCTAssertFalse(SubscriptionDetector.sameService(merchant: "CHAT GPTS", subscriptionName: "ChatGPT"))
        XCTAssertFalse(pays("Spotify", 56, 0))
        XCTAssertFalse(pays("Netflix", 120, 0))
        XCTAssertFalse(pays("Netflix", 56, 12))
    }

    func testHigherChargeInDueWindowIsAPriceRise() {
        func raised(_ merchant: String, _ amount: Decimal, _ offset: Int) -> Decimal? {
            SubscriptionDetector.raisedPrice(merchant: merchant, amount: amount, date: day(offset),
                subscriptionName: "ChatGPT", subscriptionAmount: 75, dueDate: due, toleranceDays: 5)
        }
        XCTAssertEqual(raised("CHATGPT SUBSCRIPTION", 79.5, 1), 79.5)
        XCTAssertEqual(raised("ChatGPT", 110, 0), 110)
        XCTAssertNil(raised("ChatGPT", 75, 0))      // same price: a normal payment
        XCTAssertNil(raised("ChatGPT", 60, 0))      // cheaper: not a rise
        XCTAssertNil(raised("ChatGPT", 400, 0))     // over 3x: a different purchase
        XCTAssertNil(raised("ChatGPT", 90, 12))     // outside the due window
        XCTAssertNil(raised("Spotify", 90, 0))
    }
}
