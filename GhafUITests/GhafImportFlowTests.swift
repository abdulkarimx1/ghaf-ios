import XCTest

final class GhafImportFlowTests: XCTestCase {
    private var outputDirectory: URL {
        let path = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_UI_OUT"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testSyntheticBackupSuccessAndErrorScreensInEnglishAndArabic() throws {
        for (appearance, language) in [("Light", "en"), ("Light", "ar"), ("Dark", "en"), ("Dark", "ar")] {
            let url = try syntheticBackup(language: language, appearance: appearance, unsupported: false)
            defer { try? FileManager.default.removeItem(at: url) }
            let app = launchImport(url, appearance: appearance, language: language)
            let completed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", language == "ar" ? "اكتمل الاستيراد" : "Import complete")).firstMatch
            XCTAssertTrue(completed.waitForExistence(timeout: 15), "Import should finish in \(language)/\(appearance)")
            let expected = language == "ar" ? "الحسابات: 1" : "Accounts: 1"
            XCTAssertTrue(app.staticTexts[expected].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch.exists)
            saveScreenshot(app, name: "import-success-\(appearance.lowercased())-\(language)")
            app.terminate()
        }

        for language in ["en", "ar"] {
            let url = try syntheticBackup(language: language, appearance: "Dark", unsupported: true)
            defer { try? FileManager.default.removeItem(at: url) }
            let app = launchImport(url, appearance: "Dark", language: language)
            let title = language == "ar" ? "تعذّر الاستيراد" : "Couldn’t import this file"
            XCTAssertTrue(app.alerts[title].waitForExistence(timeout: 15))
            let detail = language == "ar" ? "إصدار نسخة غاف هذه غير مدعوم." : "This Ghaf backup version is not supported."
            XCTAssertTrue(app.alerts.staticTexts[detail].exists)
            saveScreenshot(app, name: "import-error-dark-\(language)")
            app.terminate()
        }
    }

    /// The owner's real backup imports through the same code path as the button.
    func testOwnerBackup9Restores() throws {
        let path = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_BACKUP9"] ?? "/Users/abdulkarim/Downloads/Ghaf-Backup-9.json"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("Owner backup 9 is unavailable") }
        let app = launchImport(URL(fileURLWithPath: path), appearance: "Dark", language: "en")
        let completed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Import complete")).firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 30), "Backup 9 should import")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Transactions: 1212")).firstMatch.exists, completed.label)
        saveScreenshot(app, name: "import-backup9-dark-en")
    }

    /// Tapping "Ghaf backup" then "Continue" must open the Files picker (it used to do nothing).
    func testGhafBackupButtonOpensFilesPicker() {
        let app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafScreen", "importSheet", "-GhafTheme", "Graphite",
                              "-GhafAppearance", "Dark", "-GhafLanguage", "en"]
        app.launch()
        let choice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ghaf backup")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 15))
        choice.tap()
        let alert = app.alerts["Replace current data?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Continue"].tap()
        let picker = app.navigationBars.matching(NSPredicate(format: "identifier IN %@", ["Recents", "Browse", "On My iPhone"])).firstMatch
        let browse = app.buttons["Browse"].firstMatch
        let opened = picker.waitForExistence(timeout: 8) || browse.exists
        saveScreenshot(app, name: "import-button-picker")
        XCTAssertTrue(opened, "Files picker did not open after Continue")
        // Pick the real file the way a user does (needs Ghaf-Backup-9.json in the simulator's Files).
        if browse.exists { browse.tap() }
        let onMyPhone = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "On My iPhone")).firstMatch
        if onMyPhone.waitForExistence(timeout: 5) { onMyPhone.tap() }
        let file = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Ghaf-Backup-9")).firstMatch
        guard file.waitForExistence(timeout: 10) else { return }
        app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Ghaf-Backup-9")).firstMatch.tap()
        Thread.sleep(forTimeInterval: 5)
        saveScreenshot(app, name: "import-after-real-pick")
        let done = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Import complete")).firstMatch
        XCTAssertTrue(done.exists, "Picking the backup in Files changed nothing")
    }

    /// Real-device path: fresh onboarding → Import Ghaf backup → Ghaf backup → Continue → pick the file in Files.
    /// Needs Ghaf-Backup-9.json in the simulator's Files "On My iPhone".
    func testOnboardingImportPicksFileFromFiles() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafLaunchProof", "1", "-GhafLaunchNewUser", "1", "-GhafAppearance", "Dark"]
        app.launch()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let importButton = app.buttons["Restore a backup"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 15))
        let title = app.staticTexts["Bring your data into Ghaf"]
        for _ in 0..<3 where !title.exists { importButton.tap(); _ = title.waitForExistence(timeout: 3) }
        XCTAssertTrue(title.exists, "Import sheet did not open from onboarding")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ghaf JSON backup")).firstMatch.tap()
        app.alerts["Replace current data?"].buttons["Continue"].tap()
        let browse = app.buttons["Browse"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 10))
        browse.tap()
        let onMyPhone = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "On My iPhone")).firstMatch
        if onMyPhone.waitForExistence(timeout: 5) { onMyPhone.tap() }
        let cell = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Ghaf-Backup-9")).firstMatch
        guard cell.waitForExistence(timeout: 10) else { throw XCTSkip("Ghaf-Backup-9.json not in simulator Files") }
        cell.tap()
        Thread.sleep(forTimeInterval: 6)
        saveScreenshot(app, name: "onboarding-import-after-pick")
        let done = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Import complete")).firstMatch
        XCTAssertTrue(done.exists || app.tabBars.firstMatch.exists, "Picking the backup from onboarding changed nothing")
    }

    private func launchImport(_ url: URL, appearance: String, language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-GhafFixture", "1", "-GhafScreen", "importSheet", "-GhafTheme", "Graphite",
                              "-GhafAppearance", appearance, "-GhafLanguage", language,
                              "-GhafImportKind", "ghaf", "-GhafImportFile", url.path]
        app.launch()
        return app
    }

    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    private func syntheticBackup(language: String, appearance: String, unsupported: Bool) throws -> URL {
        let now = ISO8601DateFormatter().string(from: .now)
        let next = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now)
        let accountID = UUID().uuidString
        let root: [String: Any] = [
            "version": unsupported ? 99 : 4,
            "exportedAt": now,
            "settings": ["userName": "Synthetic", "languageCode": language, "currency": "AED",
                         "monthlyIncome": 1000, "fixedCommitments": 0, "themeName": "Graphite",
                         "appearanceMode": appearance, "budgetMode": "Monthly", "categories": ["Dining"],
                         "categoryBudgets": [:], "hasCompletedOnboarding": true],
            "accounts": [["id": accountID, "name": "Test wallet", "accountType": "cash", "currency": "AED",
                          "openingBalance": 100, "openingDate": now, "isArchived": false, "isPrimary": true,
                          "sortOrder": 0, "createdAt": now]],
            "transactions": [["id": UUID().uuidString, "fingerprint": "synthetic-cafe", "amount": 12.50,
                              "currency": "AED", "merchant": "Test Cafe", "date": now, "direction": "debit",
                              "category": "Dining", "confidence": 1, "needsReview": false, "isReversal": false,
                              "createdAt": now, "accountID": accountID]],
            "merchantRules": [],
            "subscriptions": [["id": UUID().uuidString, "name": "Test plan", "amount": 5, "currency": "AED",
                               "billingCycle": "monthly", "nextPaymentDate": next, "category": "Subscriptions",
                               "accountID": accountID, "reminderDays": 2, "isActive": true, "needsConfirmation": false]]
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ghaf-import-ui-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]).write(to: url, options: .atomic)
        return url
    }
}
