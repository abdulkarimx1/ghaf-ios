import XCTest
@testable import GhafCore

final class CategoryLearnerTests: XCTestCase {
    private let noon = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(_ merchant: String, _ amount: Decimal, _ category: String, _ sub: String? = nil) -> CategoryLearner.Sample {
        .init(merchant: merchant, amount: amount, date: noon, category: category, subcategory: sub)
    }

    private var learner: CategoryLearner {
        CategoryLearner(samples: [
            sample("CARREFOUR MOE DUBAI", 210, "Groceries"),
            sample("Carrefour City", 85, "Groceries"),
            sample("Lulu Hypermarket", 140, "Groceries"),
            sample("Costa Coffee DIFC", 18, "Dining", "Coffee"),
            sample("Starbucks Marina", 22, "Dining", "Coffee"),
            sample("ADNOC 1234", 120, "Fuel"),
            sample("ADNOC Station", 95, "Fuel")
        ])
    }

    func testLearnsMerchantVariantsFromConfirmedHistory() {
        let prediction = learner.predict(merchant: "CARREFOUR AL WAHDA", amount: 160, date: noon)
        XCTAssertEqual(prediction?.category, "Groceries")
        XCTAssertGreaterThan(prediction?.confidence ?? 0, 0.6)
    }

    func testCarriesSubcategory() {
        XCTAssertEqual(learner.predict(merchant: "Costa Coffee Mall", amount: 20, date: noon)?.subcategory, "Coffee")
    }

    func testUnknownMerchantGivesNoGuess() {
        XCTAssertNil(learner.predict(merchant: "Zzqx Ltd", amount: 50, date: noon))
    }

    func testNeedsSomeHistoryFirst() {
        XCTAssertNil(CategoryLearner(samples: [sample("Carrefour", 10, "Groceries")]).predict(merchant: "Carrefour", amount: 10, date: noon))
    }

    func testUnseenWordUsesOnDeviceEmbedding() {
        let model = CategoryLearner(samples: [
            sample("Gasoline Corner", 100, "Fuel"), sample("Gasoline Express", 90, "Fuel"),
            sample("Coffee Corner", 15, "Dining"), sample("Coffee Express", 12, "Dining")
        ])
        // "latte" never appears in training; the on-device embedding links it to "coffee".
        XCTAssertEqual(model.predict(merchant: "Latte Point", amount: 14, date: noon)?.category, "Dining")
    }

    func testCorrectionChangesTheAnswer() {
        var model = learner
        for _ in 0..<4 { model.learn(sample("ADNOC Oasis", 30, "Groceries")) }
        XCTAssertEqual(model.predict(merchant: "ADNOC Oasis", amount: 30, date: noon)?.category, "Groceries")
    }
}
