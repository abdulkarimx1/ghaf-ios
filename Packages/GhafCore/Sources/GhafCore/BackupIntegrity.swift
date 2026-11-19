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
    public static func validate(transactionIDs: [UUID], fingerprints: [String], accountIDs: [UUID]?, subscriptionIDs: [UUID], merchantRuleKeys: [String], accountReferences: [UUID?]) -> [BackupIntegrityProblem] {
        var problems: [BackupIntegrityProblem] = []
        if hasDuplicates(transactionIDs) { problems.append(.duplicateTransactionID) }
        if hasDuplicates(fingerprints) { problems.append(.duplicateFingerprint) }
        if let accountIDs, hasDuplicates(accountIDs) { problems.append(.duplicateAccountID) }
        if hasDuplicates(subscriptionIDs) { problems.append(.duplicateSubscriptionID) }
        if hasDuplicates(merchantRuleKeys) { problems.append(.duplicateMerchantRule) }
        for id in accountReferences.compactMap({ $0 }) where accountIDs?.contains(id) != true {
            let problem = BackupIntegrityProblem.unknownAccountReference(id)
            if !problems.contains(problem) { problems.append(problem) }
        }
        return problems
    }

    private static func hasDuplicates<T: Hashable>(_ values: [T]) -> Bool { Set(values).count != values.count }
}
