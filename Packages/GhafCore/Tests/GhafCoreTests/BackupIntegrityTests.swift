import XCTest
@testable import GhafCore

final class BackupIntegrityTests: XCTestCase {
    private let a = UUID()
    private let b = UUID()

    func testCleanPayloadAndNilReferences() {
        XCTAssertTrue(validate(transactionIDs: [a], fingerprints: ["one"], accountIDs: [b], subscriptionIDs: [a], merchantRuleKeys: ["merchant"], accountReferences: [b, nil]).isEmpty)
    }

    func testReportsEveryDuplicateKind() {
        let problems = validate(transactionIDs: [a, a], fingerprints: ["x", "x"], accountIDs: [b, b], subscriptionIDs: [a, a], merchantRuleKeys: ["k", "k"], accountReferences: [])
        XCTAssertTrue(problems.contains(.duplicateTransactionID))
        XCTAssertTrue(problems.contains(.duplicateFingerprint))
        XCTAssertTrue(problems.contains(.duplicateAccountID))
        XCTAssertTrue(problems.contains(.duplicateSubscriptionID))
        XCTAssertTrue(problems.contains(.duplicateMerchantRule))
    }

    func testDanglingAndMissingAccountListReferences() {
        XCTAssertTrue(validate(transactionIDs: [], fingerprints: [], accountIDs: [a], subscriptionIDs: [], merchantRuleKeys: [], accountReferences: [b]).contains(.unknownAccountReference(b)))
        XCTAssertFalse(validate(transactionIDs: [], fingerprints: [], accountIDs: nil, subscriptionIDs: [], merchantRuleKeys: [], accountReferences: [a]).contains(.unknownAccountReference(a)))
    }

    func testLegacyBackupSkipsUnknownReferencesAndPresentAccountListCountsOrphan() {
        let references: [UUID?] = [b, nil]
        XCTAssertTrue(BackupIntegrity.missingAccountReferences(accountIDs: nil, references: references).isEmpty)
        XCTAssertEqual(BackupIntegrity.missingAccountReferences(accountIDs: [a], references: references), [b])
    }

    private func validate(transactionIDs: [UUID], fingerprints: [String], accountIDs: [UUID]?, subscriptionIDs: [UUID], merchantRuleKeys: [String], accountReferences: [UUID?]) -> [BackupIntegrityProblem] {
        BackupIntegrity.validate(transactionIDs: transactionIDs, fingerprints: fingerprints, accountIDs: accountIDs, subscriptionIDs: subscriptionIDs, merchantRuleKeys: merchantRuleKeys, accountReferences: accountReferences)
    }
}
