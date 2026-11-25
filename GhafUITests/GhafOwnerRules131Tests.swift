import XCTest

/// Locks owner-approved 1.31 behaviours: undoable delete, stats "View transactions", per-currency wallet total.
final class GhafOwnerRules131Tests: XCTestCase {
    private func launch(_ extra: [String] = [], waitTabBar: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafTheme", "Graphite",
                               "-GhafAppearance", "Light", "-GhafLanguage", "en"] + extra
        app.launch()
        if waitTabBar { XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30)) }
        return app
    }

    private func carrefourRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Carrefour"))
    }

    /// Swipe-deletes the first Carrefour row; returns the Carrefour match count before deleting.
    private func swipeDeleteCarrefour(_ app: XCUIApplication) -> Int {
        app.tabBars.buttons["Transactions"].tap()
        let row = carrefourRows(app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Carrefour row missing")
        let before = carrefourRows(app).count
        row.swipeLeft()
        let trash = app.buttons["Delete"].firstMatch
        XCTAssertTrue(trash.waitForExistence(timeout: 5), "Trash swipe action missing")
        trash.tap()
        return before
    }

    func testOwnerRule_DeleteShowsUndoAndUndoRestoresRow() throws {
        let app = launch()
        let before = swipeDeleteCarrefour(app)
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2), "Undo must appear after delete")
        XCTAssertLessThan(carrefourRows(app).count, before, "Row must disappear on delete")
        undo.tap()
        XCTAssertEqual(carrefourRows(app).count, before, "Undo must restore the row")
        sleep(6)
        XCTAssertEqual(carrefourRows(app).count, before, "Row must stay after undo timeout")
    }

    func testOwnerRule_DeleteWithoutUndoRemovesRow() throws {
        let app = launch()
        let before = swipeDeleteCarrefour(app)
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 2))
        sleep(7)
        XCTAssertFalse(app.buttons["Undo"].exists, "Undo must expire")
        XCTAssertLessThan(carrefourRows(app).count, before, "Deleted row must stay removed")
    }

    func testOwnerRule_StatsBarOffersViewTransactions() throws {
        let app = launch(["-GhafTab", "insights", "-GhafSelection", "bar"])
        let button = app.buttons["View transactions"]
        XCTAssertTrue(button.waitForExistence(timeout: 4))
        button.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Carrefour"))
            .firstMatch.waitForExistence(timeout: 5), "Sheet must list a transaction")
    }

    func testOwnerRule_WalletShowsPerCurrencyTotal() throws {
        let app = launch(["-GhafScreen", "wallet"], waitTabBar: false)
        XCTAssertTrue(app.staticTexts["Total"].waitForExistence(timeout: 10))
    }
}
