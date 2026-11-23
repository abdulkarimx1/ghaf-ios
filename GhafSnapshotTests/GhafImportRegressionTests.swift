import XCTest
import SwiftData
import GhafCore
@testable import Ghaf

@MainActor
final class GhafImportRegressionTests: XCTestCase {
    private let schema = Schema([GhafTransaction.self, GhafSettings.self, GhafAccount.self,
                                 MerchantCategoryRule.self, GhafSubscription.self, GhafChat.self, GhafMemory.self])

    func testLegacyBackupVersionsMigrateSyntheticRecords() throws {
        for version in 1...4 {
            var root = try syntheticBackup()
            root["version"] = version
            if version < 2, var settings = root["settings"] as? [String: Any] {
                for key in ["arabicName", "languageCode", "hasSeenAutomationIntro", "salaryEnabled", "salaryDay",
                            "salaryAmount", "salaryCurrency", "salaryAccountID", "salaryReminderEnabled",
                            "biometricLockEnabled", "balanceSetupMode", "lastSalaryDecisionKey", "createdAt"] {
                    settings.removeValue(forKey: key)
                }
                root["settings"] = settings
            }
            if version < 3 {
                root.removeValue(forKey: "subscriptions")
                root.removeValue(forKey: "glass")
            }
            if version < 4 {
                root.removeValue(forKey: "memories")
                root.removeValue(forKey: "preferences")
            }
            if version < 5 {
                root.removeValue(forKey: "accountMappings")
                var settings = root["settings"] as! [String: Any]
                settings.removeValue(forKey: "deletedCategories")
                root["settings"] = settings
            }

            let url = try write(root)
            defer { try? FileManager.default.removeItem(at: url) }
            let container = try makeContainer()
            let result = try GhafBackupService.restore(from: url, context: container.mainContext)
            XCTAssertEqual(result.recordsWithoutAccounts, 0, "Version \(version)")
            XCTAssertEqual(result.accountsImported, 1, "Version \(version)")
            XCTAssertEqual(result.transactionsImported, 1, "Version \(version)")
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<GhafAccount>()), 1, "Version \(version)")
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<GhafTransaction>()), 1, "Version \(version)")
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<GhafSubscription>()), version < 3 ? 0 : 1, "Version \(version)")
        }
    }

    func testLegacyBackupDefaultsNewRequiredSettingsAndClearsMissingAccountLinks() throws {
        var root = try syntheticBackup()
        root["version"] = 1
        root.removeValue(forKey: "accounts")
        var settings = root["settings"] as! [String: Any]
        for key in ["currency", "monthlyIncome", "fixedCommitments", "themeName", "appearanceMode",
                    "budgetMode", "categories", "categoryBudgets", "hasCompletedOnboarding"] {
            settings.removeValue(forKey: key)
        }
        root["settings"] = settings

        let url = try write(root)
        defer { try? FileManager.default.removeItem(at: url) }
        let container = try makeContainer()
        let result = try GhafBackupService.restore(from: url, context: container.mainContext)
        XCTAssertEqual(result.recordsWithoutAccounts, 2, "An unassigned transaction and subscription should be reported")
        XCTAssertNil(try container.mainContext.fetch(FetchDescriptor<GhafTransaction>()).first?.accountID)
        XCTAssertNil(try container.mainContext.fetch(FetchDescriptor<GhafSubscription>()).first?.accountID)
        let restoredSettings = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<GhafSettings>()).first)
        XCTAssertEqual(restoredSettings.currency, "AED")
        XCTAssertTrue(restoredSettings.categories.contains("Other"))
        XCTAssertTrue(restoredSettings.hasCompletedOnboarding)
    }

    func testUnsupportedBackupDoesNotChangeExistingRecords() throws {
        let container = try makeContainer()
        let original = GhafSettings(userName: "Original", currency: "AED", monthlyIncome: 50)
        container.mainContext.insert(original)
        try container.mainContext.save()

        var root = try syntheticBackup()
        root["version"] = 99
        let url = try write(root)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try GhafBackupService.restore(from: url, context: container.mainContext))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<GhafSettings>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<GhafTransaction>()), 0)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<GhafSettings>()).first?.userName, "Original")
    }

    func testFreshExportReimportsEverySyntheticRecord() throws {
        let data = try JSONSerialization.data(withJSONObject: syntheticBackup(), options: [.sortedKeys])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ghaf-current-roundtrip-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let container = try makeContainer()
        let result = try GhafBackupService.restore(from: url, context: container.mainContext)
        XCTAssertEqual(result.accountsImported, 1)
        XCTAssertEqual(result.transactionsImported, 1)
        XCTAssertEqual(result.subscriptionsImported, 1)
        XCTAssertEqual(result.recordsWithoutAccounts, 0)
    }

    func testOwnerBackupsRestoreReadOnlyAndMatchFileCounts() throws {
        let environment = ProcessInfo.processInfo.environment
        let paths = [environment["TEST_RUNNER_GHAF_BACKUP"], environment["TEST_RUNNER_GHAF_BACKUP4"]].compactMap { $0 }
        guard !paths.isEmpty else { throw XCTSkip("Set TEST_RUNNER_GHAF_BACKUP and optionally TEST_RUNNER_GHAF_BACKUP4") }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let expectedAccounts = (root["accounts"] as? [[String: Any]])?.count ?? 0
            let expectedTransactions = (root["transactions"] as? [[String: Any]])?.count ?? 0
            let expectedSubscriptions = (root["subscriptions"] as? [[String: Any]])?.count ?? 0
            let container = try makeContainer()
            let result = try GhafBackupService.restore(from: url, context: container.mainContext)
            XCTAssertEqual(result.accountsImported, expectedAccounts, "Backup account count did not match")
            XCTAssertEqual(result.transactionsImported, expectedTransactions, "Backup transaction count did not match")
            XCTAssertEqual(result.subscriptionsImported, expectedSubscriptions, "Backup subscription count did not match")
        }
    }

    func testDelimitedRowsHandleUAEAmountFormatsAndRejectMalformedFiles() throws {
        XCTAssertEqual(DelimitedImport.decimal("١٬٢٣٤٫٥٠"), Decimal(string: "1234.50"))
        XCTAssertEqual(DelimitedImport.decimal("1,234.50"), Decimal(string: "1234.50"))
        XCTAssertEqual(DelimitedImport.decimal("1.234,50"), Decimal(string: "1234.50"))
        XCTAssertThrowsError(try DelimitedImport.rows("date,amount,merchant\n2026-01-01,5,\"unfinished"))
        XCTAssertThrowsError(try DelimitedImport.rows(""))
    }

    func testCSVImportCommitsDecimalCurrencyAndSkipsItsDuplicate() throws {
        let container = try makeContainer()
        let settings = GhafSettings(userName: "Synthetic", currency: "AED")
        container.mainContext.insert(settings)
        try container.mainContext.save()
        let csv = "date,amount,merchant,currency,account\n2026-11-20,\"-1,234.50\",Test Cafe,AED,Test wallet\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ghaf-synthetic-\(UUID().uuidString).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let preview = try GhafFileImport.preview(url, context: container.mainContext)
        XCTAssertEqual(preview.rows.count, 1)
        XCTAssertEqual(preview.rows[0].amount, Decimal(string: "1234.50"))
        XCTAssertEqual(preview.rows[0].currency, "AED")
        XCTAssertEqual(preview.accountsToCreate, ["Test wallet"])
        let first = try GhafFileImport.commit(preview, createAccounts: true, context: container.mainContext)
        XCTAssertEqual(first.imported, 1)
        XCTAssertEqual(first.duplicates, 0)
        let second = try GhafFileImport.commit(preview, createAccounts: true, context: container.mainContext)
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.duplicates, 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<GhafTransaction>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<GhafAccount>()), 1)
    }

    func testExpendImportValidatesAndImportsSyntheticLedger() throws {
        let container = try makeContainer()
        let root: [String: Any] = [
            "profile": ["mainCurrency": "AED", "name": "Synthetic"],
            "wallets": [["_id": "wallet-1", "name": "Test wallet", "currencyCode": "AED",
                         "initialAmount": 100, "currentAmount": 88, "dateCreated": "2026-11-20T00:00:00Z"]],
            "transactions": [["_id": "transaction-1", "type": "expense", "amount": 12,
                              "name": "Test Cafe", "srcWallet": "wallet-1", "dateCreated": "2026-11-20T12:00:00Z"]]
        ]
        let url = try write(root)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(GhafExpendImportService.canImport(url))
        let result = try GhafExpendImportService.importFile(from: url, context: container.mainContext)
        XCTAssertEqual(result.accountsImported, 1)
        XCTAssertEqual(result.transactionsImported, 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<GhafAccount>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<GhafTransaction>()), 1)
    }

    private func syntheticBackup() throws -> [String: Any] {
        let container = try makeContainer()
        let account = GhafAccount(name: "Test wallet", accountType: .cash, currency: "AED", openingBalance: 100)
        let settings = GhafSettings(userName: "Synthetic", currency: "AED", monthlyIncome: 1000)
        container.mainContext.insert(settings)
        container.mainContext.insert(account)
        let parsed = ParsedTransaction(amount: 12.50, currency: "AED", merchant: "Test Cafe", date: .now,
                                       direction: .debit, confidence: 1, bank: nil)
        container.mainContext.insert(GhafTransaction(fingerprint: "synthetic-cafe", parsed: parsed,
            category: "Dining", needsReview: false, isReversal: false, accountID: account.id))
        container.mainContext.insert(GhafSubscription(name: "Test plan", amount: 5, currency: "AED",
            billingCycle: .monthly, nextPaymentDate: .now, category: "Subscriptions", accountID: account.id))
        try container.mainContext.save()
        let url = try GhafBackupService.export(context: container.mainContext)
        defer { try? FileManager.default.removeItem(at: url) }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [ModelConfiguration("ImportTest-\(UUID().uuidString)",
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }

    private func write(_ root: [String: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ghaf-synthetic-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]).write(to: url, options: .atomic)
        return url
    }
}
