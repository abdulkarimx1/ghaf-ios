import Foundation

public enum BackupIntegrityProblem: Equatable {
    case duplicateTransactionID
    case duplicateFingerprint
    case duplicateAccountID
    case duplicateSubscriptionID
    case duplicateMerchantRule
    case unknownAccountReference(UUID)
}

public enum BackupIntegrity {
    public static func missingAccountReferences(accountIDs: [UUID]?, references: [UUID?]) -> [UUID] {
        guard let accountIDs else { return [] }
        return references.compactMap { $0 }.filter { !accountIDs.contains($0) }
    }

    public static func validate(transactionIDs: [UUID], fingerprints: [String], accountIDs: [UUID]?, subscriptionIDs: [UUID], merchantRuleKeys: [String], accountReferences: [UUID?]) -> [BackupIntegrityProblem] {
        var problems: [BackupIntegrityProblem] = []
        if hasDuplicates(transactionIDs) { problems.append(.duplicateTransactionID) }
        if hasDuplicates(fingerprints) { problems.append(.duplicateFingerprint) }
        if let accountIDs, hasDuplicates(accountIDs) { problems.append(.duplicateAccountID) }
        if hasDuplicates(subscriptionIDs) { problems.append(.duplicateSubscriptionID) }
        if hasDuplicates(merchantRuleKeys) { problems.append(.duplicateMerchantRule) }
        for id in missingAccountReferences(accountIDs: accountIDs, references: accountReferences) {
            let problem = BackupIntegrityProblem.unknownAccountReference(id)
            if !problems.contains(problem) { problems.append(problem) }
        }
        return problems
    }

    private static func hasDuplicates<T: Hashable>(_ values: [T]) -> Bool { Set(values).count != values.count }
}
